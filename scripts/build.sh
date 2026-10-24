#!/usr/bin/env bash
# 小米 11 Ultra (star) 5.4.302 Droidspaces 内核一键构建
# 在 Linux 容器内运行（务必是大小写敏感的文件系统，见 docs/PITFALLS.md 第 3 条）
#
# 用法：
#   docker run --rm -it -v "$PWD":/work ubuntu:22.04 bash
#   apt-get update && apt-get install -y build-essential bc bison flex libssl-dev \
#     libelf-dev python3 rsync kmod cpio device-tree-compiler xz-utils git curl
#   bash /work/scripts/build.sh
#
# 可覆盖的环境变量：
#   DEVICE=star            设备代号（star / mars / venus / haydn）
#   TAG=Stable4            上游源码 tag
#   KSU_TAG=v4.2.0-rc1     ReSukiSU / BakaSU tag
#   KSU_VERSION_CODE=35159 期望的 KSU 版本码（决定伪造的提交数量）
#   LOCALVERSION='-ikun-NekoMake-star-260929-qgqi+'  必须与目标 ROM 的 uname -r 一致
#   BASE_CONFIG=/path/to/original.config  用 ROM 原厂 config 作基线（推荐）

set -euo pipefail

DEVICE="${DEVICE:-star}"
TAG="${TAG:-Stable4}"
KSU_TAG="${KSU_TAG:-v4.2.0-rc1}"
KSU_VERSION_CODE="${KSU_VERSION_CODE:-35159}"
LOCALVERSION="${LOCALVERSION:--ikun-NekoMake-star-260929-qgqi+}"
BASE_CONFIG="${BASE_CONFIG:-}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${WORK:-$REPO_ROOT/work}"
KERNEL="$WORK/kernel"
OUT="$KERNEL/out-$DEVICE"
LOG="$WORK/build.log"

msg() { printf '\n\033[1m== %s\033[0m\n' "$*"; }

mkdir -p "$WORK"

msg "1/7 取源码 $TAG"
if [ ! -d "$KERNEL" ]; then
  curl -sL -o "$WORK/src.tar.gz" \
    "https://api.github.com/repos/MiYume0721/android_kernel_xiaomi_sm8350_miyume/tarball/$TAG"
  mkdir -p "$KERNEL"
  tar -xzf "$WORK/src.tar.gz" -C "$KERNEL" --strip-components=1
fi
head -5 "$KERNEL/Makefile" | tr '\n' ' '; echo

msg "2/7 装 KernelSU 子模块 $KSU_TAG"
if [ ! -d "$KERNEL/KernelSU/.git" ]; then
  curl -sL -o "$WORK/ksu.tar.gz" \
    "https://api.github.com/repos/ReSukiSU/ReSukiSU/tarball/$KSU_TAG"
  rm -rf "$KERNEL/KernelSU"; mkdir -p "$KERNEL/KernelSU"
  tar -xzf "$WORK/ksu.tar.gz" -C "$KERNEL/KernelSU" --strip-components=1
  cd "$KERNEL/KernelSU"
  git init -q
  git config user.email ci@local
  git config user.name ci
  git add -A && git commit -qm "ReSukiSU $KSU_TAG"

  # Kbuild 用提交数算版本码：30000 + count + 700
  target=$(( KSU_VERSION_CODE - 30700 ))
  base=$(git rev-parse HEAD)
  python3 - "$base" "$target" > "$WORK/fi.stream" <<'PY'
import sys
base, target = sys.argv[1], int(sys.argv[2])
out = []
for i in range(1, target):
    ts = 1700000000 + i * 3600
    prev = base if i == 1 else ":%d" % (i - 1)
    out.append(
        "commit refs/heads/master\n"
        "mark :%d\n"
        "author ci <ci@local> %d +0800\n"
        "committer ci <ci@local> %d +0800\n"
        "data 2\nx\n"
        "from %s\n\n" % (i, ts, ts, prev)
    )
sys.stdout.write("".join(out))
PY
  git fast-import --quiet --force < "$WORK/fi.stream"
  git checkout -q master
  git tag -f "v$(echo "$KSU_TAG" | sed 's/^v//')" HEAD >/dev/null 2>&1 || true
  echo "KSU commits=$(git rev-list --count HEAD) version=$(( 30000 + $(git rev-list --count HEAD) + 700 ))"
  cd - >/dev/null
fi

msg "3/7 打 ABI 补丁"
cd "$KERNEL"
if ! grep -q "ANDROID_KABI_USE(6, struct sysv_sem sysvsem)" include/linux/sched.h; then
  patch -p1 --fuzz=2 < "$REPO_ROOT/patches/001-sysvipc-kabi.patch"
fi
if ! grep -q "ANDROID_KABI_USE(1, unsigned long mq_bytes)" include/linux/sched/user.h; then
  patch -p1 < "$REPO_ROOT/patches/002-posix-mqueue-kabi.patch"
fi

msg "4/7 生成配置"
mkdir -p "$OUT"
if [ -n "$BASE_CONFIG" ] && [ -f "$BASE_CONFIG" ]; then
  cp "$BASE_CONFIG" "$OUT/.config"
  sed -i "s|^CONFIG_LOCALVERSION=.*|CONFIG_LOCALVERSION=\"$LOCALVERSION\"|" "$OUT/.config"
  cat "$REPO_ROOT/config/droidspaces.fragment" "$REPO_ROOT/config/extra-docker-cgroup.fragment" >> "$OUT/.config"
  make ARCH=arm64 LLVM=1 LLVM_IAS=1 O="$OUT" olddefconfig >/dev/null
else
  make ARCH=arm64 LLVM=1 LLVM_IAS=1 O="$OUT" "${DEVICE}_defconfig" >/dev/null
  cat "$REPO_ROOT/config/droidspaces.fragment" "$REPO_ROOT/config/extra-docker-cgroup.fragment" >> "$OUT/.config"
  sed -i "s|^CONFIG_LOCALVERSION=.*|CONFIG_LOCALVERSION=\"$LOCALVERSION\"|" "$OUT/.config"
  make ARCH=arm64 LLVM=1 LLVM_IAS=1 O="$OUT" olddefconfig >/dev/null
fi

echo "关键项："
grep -E "^CONFIG_(SYSVIPC|POSIX_MQUEUE|IPC_NS|PID_NS|USER_NS|MACVLAN|CGROUP_PIDS|TMPFS_XATTR|IP_SET|LOCALVERSION)=" "$OUT/.config" || true

msg "5/7 编译（约 10 分钟）"
make -j"$(nproc)" ARCH=arm64 LLVM=1 LLVM_IAS=1 O="$OUT" Image modules 2>&1 | tee "$LOG" | tail -5

IMAGE="$OUT/arch/arm64/boot/Image"
[ -f "$IMAGE" ] || { echo "编译失败，见 $LOG"; exit 1; }
ls -l "$IMAGE"

msg "6/7 校验"
echo "-- Android 17 依赖的 syscall --"
for s in epoll_pwait2 openat2 faccessat2 close_range pidfd_getfd; do
  printf '  %-16s %s\n' "$s" "$(grep -c "$s" "$OUT/System.map" || true)"
done
echo "-- vermagic --"
strings -a "$IMAGE" | grep -m1 "SMP preempt mod_unload"
echo "-- KSU 版本 --"
grep -E "version code|version name" "$LOG" | head -2 || true

msg "7/7 完成"
echo "Image: $IMAGE"
echo "下一步：按 docs/BUILD.md 第 8 节打包 AK3"
