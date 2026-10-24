# 完整构建步骤

以小米 11 Ultra（star）为例，在 Linux 容器里编译澎湃 OS 4.0 / Android 17 可用的 5.4.302 内核。

## 0. 原则

1. **必须在大小写敏感的 Linux 文件系统上编译。** macOS 的 APFS 默认不区分大小写，会把 `xt_DSCP.c` 与 `xt_dscp.c` 合并成同一个文件（全树 26 个），编译直接报 `No rule to make target 'net/netfilter/xt_DSCP.o'`。把源码 `bind mount` 进 Docker 也不行——文件系统仍是宿主的。
2. **配置以 ROM 原厂 config 为基线**，只做加法。这样驱动集合与 ROM 完全一致，开机成功率最高；直接改 defconfig 反而容易漏驱动。
3. **vermagic 必须逐字节一致。** 它是模块加载的硬门槛，差一个字符 vendor 模块就拒载。

## 1. 准备构建环境

```bash
docker run -d --name kbuild -v "$PWD":/work ubuntu:22.04 sleep infinity
docker exec kbuild bash -c '
  apt-get update
  apt-get install -y --no-install-recommends \
    build-essential bc bison flex libssl-dev libelf-dev python3 rsync \
    kmod cpio device-tree-compiler xz-utils git curl ca-certificates \
    dwarves zip unzip file
'
```

clang 18（Docker 镜像内的 `apt.llvm.org` 在国内常拉不动，用清华镜像）：

```bash
docker exec kbuild bash -c '
  echo "deb [trusted=yes] https://mirrors.tuna.tsinghua.edu.cn/llvm-apt/jammy/ llvm-toolchain-jammy-18 main" \
    > /etc/apt/sources.list.d/llvm18.list
  sed -i "s|http://ports.ubuntu.com/ubuntu-ports|https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports|g" /etc/apt/sources.list
  apt-get update
  apt-get install -y --no-install-recommends clang-18 lld-18 llvm-18
  for t in clang clang++ ld.lld llvm-ar llvm-nm llvm-objcopy llvm-objdump llvm-strip llvm-readelf llvm-addr2line; do
    ln -sf /usr/bin/$t-18 /usr/local/bin/$t
  done
  clang --version | head -1
'
```

## 2. 取源码

```bash
# release 直链在国内经常 502，用 tarball 接口
curl -sL -o /tmp/stable4.tar.gz \
  "https://api.github.com/repos/MiYume0721/android_kernel_xiaomi_sm8350_miyume/tarball/Stable4"

# 关键：解包到容器内（Linux ext4），不要在宿主机上解
cat /tmp/stable4.tar.gz | docker exec -i kbuild bash -c \
  'mkdir -p /build/kernel && tar -xzf - -C /build/kernel --strip-components=1'
```

## 3. 装 KernelSU 子模块

tarball 不含子模块，`KernelSU/` 是空目录，而 `drivers/kernelsu` 是指向 `KernelSU/kernel` 的软链。
不处理会报：

```
-- Can't find ReSukiSU git submodule!
../drivers/kernelsu/Kbuild:67: *** You should use ReSukiSU as a git submodule instead of copying code directly.  Stop.
```

`Kbuild` 会检查 `KernelSU/.git` 是否存在，并且用 git 提交数计算版本号：

```make
KSU_VERSION     := $(shell expr 30000 + $(KSU_LOCAL_VERSION) + 700)
KSU_TAG_NAME    := $(shell git describe --abbrev=0 --tags 2>/dev/null || echo "v4.1.0")
KSU_COMMIT_SHA  := $(shell git rev-parse --short=8 HEAD 2>/dev/null || echo "unknown")
```

所以手动放代码必须自己造 git 历史：

```bash
curl -sL -o /tmp/ksu.tar.gz \
  "https://api.github.com/repos/ReSukiSU/ReSukiSU/tarball/v4.2.0-rc1"   # = a9216b04

cat /tmp/ksu.tar.gz | docker exec -i kbuild bash -c '
  cd /build/kernel/KernelSU
  tar -xzf - --strip-components=1
  git init -q && git config user.email ci@local && git config user.name ci
  git add -A && git commit -qm "ReSukiSU v4.2.0-rc1 (a9216b04)"
'
```

要让版本号等于某个目标值，需要补足够的提交数量：

```
提交数 = 目标版本码 - 30700
例：目标 35158（rc2 管理器） -> 4458 个提交
```

用 `git fast-import` 造历史（比循环 `git commit` 快得多）：

```bash
docker exec kbuild bash -c '
  cd /build/kernel/KernelSU
  base=$(git rev-parse HEAD); target=4458
  python3 - "$base" "$target" <<PY
import sys
base, target = sys.argv[1], int(sys.argv[2])
out=[]
for i in range(1, target):
    ts=1700000000+i*3600
    prev = base if i==1 else ":%d" % (i-1)
    out.append(f"commit refs/heads/master\nmark :{i}\nauthor ci <ci@local> {ts} +0800\ncommitter ci <ci@local> {ts} +0800\ndata 2\nx\nfrom {prev}\n\n")
open("/tmp/fi.stream","w").write("".join(out))
PY
  git fast-import --quiet --force < /tmp/fi.stream
  git checkout -q master
  git tag -f v4.2.0-rc2 HEAD
  git rev-list --count HEAD
'
```

注意每个 commit 的 `from` 必须指向上一个 mark（`:%d`），否则会变成兄弟分支，`rev-list --count` 只数到 2。

## 4. 打 ABI 补丁

开启 `CONFIG_SYSVIPC` / `CONFIG_POSIX_MQUEUE` 会让 `task_struct` 与 `user_struct` 变长，而 ROM 里的闭源 vendor 模块是按旧偏移编译的。GKI 的做法是把字段挪进 ABI padding 槽位：

```bash
docker exec kbuild bash -c '
  cd /build/kernel
  patch -p1 --fuzz=2 < /work/patches/001-sysvipc-kabi.patch
  patch -p1          < /work/patches/002-posix-mqueue-kabi.patch
'
```

校验结果：

```bash
grep -n "ANDROID_KABI_USE(6" include/linux/sched.h        # sysv_sem
grep -n "ANDROID_KABI_USE(1" include/linux/sched/user.h   # mq_bytes
```

## 5. 配置

**方式 A（推荐，可复现本仓库产物）**：以 ROM 原厂 config 为基线。
从设备或 ROM 包的 `boot.img` 里提取 `/proc/config.gz` 得到 `original.config`，然后：

```bash
cat config/droidspaces.fragment config/extra-docker-cgroup.fragment >> original.config
# 把版本串改成目标 ROM 的（必须与 uname -r 一致，含结尾的 +）
sed -i 's|^CONFIG_LOCALVERSION=.*|CONFIG_LOCALVERSION="-ikun-NekoMake-star-260929-qgqi+"|' original.config
```

**方式 B（移植到别的 ROM）**：用仓库自带 defconfig，再合并 fragment：

```bash
make ARCH=arm64 star_defconfig
cat config/droidspaces.fragment config/extra-docker-cgroup.fragment >> .config
```

收敛配置：

```bash
make -j8 ARCH=arm64 LLVM=1 LLVM_IAS=1 O=out-star olddefconfig
```

`olddefconfig` 会丢掉源码树里不存在的符号（原厂 config 里的私有补丁项），这是预期的。
收敛后务必确认关键项仍在：

```bash
grep -E "^CONFIG_(SYSVIPC|POSIX_MQUEUE|IPC_NS|PID_NS|USER_NS|MACVLAN|CGROUP_PIDS|TMPFS_XATTR|IP_SET)=" out-star/.config
```

## 6. 编译

```bash
docker exec kbuild bash -c '
  cd /build/kernel
  make -j8 ARCH=arm64 LLVM=1 LLVM_IAS=1 O=out-star Image modules
'
```

8 核约 9~12 分钟，产物 `out-star/arch/arm64/boot/Image` 约 47.6MB。

## 7. 校验（别跳过）

```bash
# Android 17 用户态依赖，缺一个就可能开机自检崩溃
grep -E "epoll_pwait2|openat2|faccessat2|close_range|pidfd_getfd" out-star/System.map

# vermagic 必须与目标 ROM 的 uname -r 完全一致
strings out-star/arch/arm64/boot/Image | grep "SMP preempt mod_unload"

# KSU 版本码
grep -E "version code|version name" build.log
```

## 8. 打包 AK3

```bash
git clone --depth=1 https://github.com/osm0sis/AnyKernel3
cp out-star/arch/arm64/boot/Image AnyKernel3/Image
```

`AnyKernel3/anykernel.sh` 关键改动：

```sh
kernel.string=HoshinoNeko-Droidspaces Stable4 (star)
do.devicecheck=0            # TWRP 里 ro.product.device 未必等于 star，开着会报 Unsupported device
do.modules=0
BLOCK=/dev/block/bootdevice/by-name/boot;
IS_SLOT_DEVICE=auto;        # A/B 自动识别槽位
```

末尾保留：

```sh
split_boot;
flash_boot;
```

`split_boot` 解包设备当前 boot（拿到真实 ramdisk），`flash_boot` 回打时只换 kernel。
这正是不要直接 `fastboot flash boot` 自己重打包的原因——ROM 安装时的 ramdisk 可能被 Magisk 改过，版本也可能与安装包不一致。

```bash
cd AnyKernel3 && zip -r -1 ../AK3-Star-Stable4-Droidspaces.zip . -x "*.DS_Store"
```

## 9. 刷入与验证

TWRP 卡刷 zip，重启，打开 Droidspaces 检查要求。
`adb shell uname -a` 应显示新的构建时间。
