# 给小米 11 Ultra 亲手编一颗内核：让澎湃 OS 4.0 / 安卓 17 跑起 Docker

> 一句话结论：在骁龙 888 的小米 11 Ultra 上，把开源 HoshinoNeko 内核按自己的需求重编一版，Droidspaces 检查从"内核不支持"变成全绿，Ubuntu 容器和 Docker 都能跑，root 也没丢。

---

## 一、先看结果

| 项目 | 值 |
|---|---|
| 机型 | 小米 11 Ultra（star / M2102K1C） |
| SoC | 骁龙 888（SM8350 / lahaina），8 核，大核 2.84GHz |
| 内存 | 12GB（MemTotal 11.48GB），zram 12GB |
| 系统 | 安卓 17 · 澎湃 OS 4.0（OS4.0.4.0.XPBCNXM，安全补丁 2026-10-01） |
| ROM | 朗月移植包 26.10.23 |
| 内核 | `5.4.302-ikun-NekoMake-star-260929-qgqi+`（自制） |
| 分区 | A/B，当前 `_a` 槽 |
| SELinux | Enforcing |
| Root | BakaSU（原 ReSukiSU）v4.2.0 系，内核内置，管理器 v4.2.0-rc1 |

Droidspaces 检查结果：命名空间、OverlayFS、FUSE、TUN/TAP、veth、macvlan、内存限制、进程限制、CPU 统计 —— **全绿**；只有 `CPU limit support`（CFS 带宽）是黄的，原因后面单说。

---

## 二、为什么要自己编

想在这台机器上跑 Immich（照片管理 + 人脸识别），官方那套"手机端跑服务"的方案太重，Droidspaces 这种"在安卓里开 Linux 容器"的路子更合适。

但装好 Droidspaces 一检查：**内核不支持**。缺的是 SYSVIPC、POSIX 消息队列、IPC/PID/USER 命名空间、macvlan、IP_SET 这些。

而 ROM 作者明确写过「**当前版本不要刷入其他内核**」——因为这块屏幕的背屏、LHDC、Widevine L1 都跟原内核绑定。

**思路**：不动 ROM，只把 ROM 用的那颗内核源码拿来重编一遍，只加容器需要的开关，其他一律不动。这样既满足 Droidspaces，又不破坏 ROM 特性。

---

## 三、开发过程（真实踩坑记录）

### 10:30 · 顺藤摸瓜找源码

设备上 `uname -r` 是：

```
5.4.302-ikun-NekoMake-star-260929-qgqi+
```

`Neko` 指向 **MiYume0721/android_kernel_xiaomi_sm8350_miyume**（HoshinoNeko 内核），`ikun` 前缀是 ROM 作者编内核时加的本地版本串。

同源，可以开搞。

### 11:00 · 第一轮：编译成功，装机开不了机

用仓库的 **Stable2** 分支编出来的 Image，47.5MB，vermagic 对得上，AK3 刷入 —— **开不了机**。

这一轮先踩了三个坑（都是教训，值得记）：

**坑 1：apt.llvm.org 在国内拉不动**
Dockerfile 里装的 clang-18 一直失败，换成清华镜像的 llvm-apt 才通。

**坑 2：KernelSU 是 git 子模块，tarball 里是空的**
报错长这样：

```
-- Can't find ReSukiSU git submodule!
../drivers/kernelsu/Kbuild:67: *** You should use ReSukiSU as a git submodule instead of copying code directly.  Stop.
```

Kbuild 里硬检查 `drivers/kernelsu/../.git`，手动放代码不算，得是个真 git 仓库。解法：把 KSU 源码解到 `KernelSU/`，`git init` 提交一次，`drivers/kernelsu` 软链到 `KernelSU/kernel`。

**坑 3（最阴）：macOS 是大小写不敏感文件系统**
内核里有 `xt_DSCP.c` 和 `xt_dscp.c` 这种只差大小写的文件，全树 26 个。APFS 把它们合并成同一个文件，编译时直接报：

```
No rule to make target 'net/netfilter/xt_DSCP.o'
```

即使把源码 bind mount 进 Docker 也没用——文件系统还是宿主的。**解法：把整棵树拷进容器自己的 ext4 再编。**

### 12:47 · 刷进去了，然后黑屏

AK3 在 TWRP 里报 `Unsupported device. Aborting...`（设备名校验没过），改成整包 fastboot 刷 boot.img，结果**开不了机**。

复盘发现关键证据：原厂 config 里有 4 个选项，在两棵源码树里**根本不存在**——

```
CONFIG_ZRAM_MULTI_COMP
CONFIG_DM_USER
CONFIG_ANDROID_VENDOR_FREEZER_COMPAT
CONFIG_OPLUS_FEATURE_HANS
```

反过来验证：原厂内核二进制里有 `dm_user` 符号 6 处，我编的内核里 0 处。**说明 ROM 内核不是这个仓库的当前状态**，是「miyume + 作者私有补丁」。

### 13:30 · 找到真正的原因

翻 Stable4 的 release notes，第一句就写明白了：

> 强烈建议更新，**老内核在新版 HyperOS4.0 Android 17 无法正常开机**
> 修复新版 Android 17 无法开机：实现 epoll_pwait2，SystemUI 不再自检失败导致崩溃

原来 Stable2 那版**天生就开不了机**，跟我的配置改动一点关系都没有。安卓 17 的 SystemUI 要调 `epoll_pwait2`，老内核没这个系统调用，自检失败直接崩。

### 14:05 · 第二轮：Stable4，一次成功

换 **Stable4**（commit `d5dae54`）重编，同样的配置策略，刷入 —— 开机正常，Droidspaces 全绿。

### 14:20 · 收尾：把版本号对齐

KernelSU 的版本号不是写死的，是 Kbuild 现算的：

```make
KSU_VERSION := $(shell expr 30000 + $(KSU_LOCAL_VERSION) + 700)
KSU_TAG_NAME := $(shell git describe --abbrev=0 --tags || echo "v4.1.0")
```

我手动 `git init` 的仓库只有 1 个 commit，于是算成 `30701`、标签 fallback 成 `v4.1.0`。管理器一比对就提示「需要更新内核」。

补了提交历史、打了正确 tag，版本号变成 35159。后来才发现真正的判据不是版本号大小，而是 **UAPI 协议版本是否相等**：

```kotlin
fun isFullFeatured(): Boolean = isManager && kernelUAPIVersion == managerUAPIVersion
```

界面上的 `35159/2` 就是「版本码 / UAPI」。内核 UAPI 是 2（rc1 代码），管理器 rc2 是 4，所以红条一直在。**最后换回 rc1 管理器（35061/2），2==2，红条消失。**

---

## 四、四个关键技术点

### 1. 为什么必须 Stable4

`epoll_pwait2`、`openat2`、`faccessat2`、`close_range`、`pidfd_getfd`、`futex_waitv` —— 安卓 17 用户态依赖这些。少一个就可能在开机自检阶段崩。编完我在 `System.map` 里逐个查过：

```
ffffffc0103904a0 T __arm64_sys_epoll_pwait2
ffffffc010390710 T __arm64_compat_sys_epoll_pwait2
```

### 2. 为什么要打 ABI 补丁（这步最关键）

`CONFIG_SYSVIPC` 和 `CONFIG_POSIX_MQUEUE` 一开，`struct task_struct` 和 `struct user_struct` 就会**变长**。而 ROM 里那些闭源的 vendor 模块（WiFi、相机、显示）是按旧结构体的**固定偏移**编译的，偏移一变就全乱。

GKI 内核的标准做法是用 ABI padding 槽位：把新字段塞进预留的空槽，总大小不变，老偏移不动。

```c
/* 原来是原位定义 */
// struct sysv_sem sysvsem;
// struct sysv_shm sysvshm;

/* 改成占用 KABI 预留槽 6/7/8 */
ANDROID_KABI_USE(6, struct sysv_sem sysvsem);
_ANDROID_KABI_REPLACE(ANDROID_KABI_RESERVE(7); ANDROID_KABI_RESERVE(8), struct sysv_shm sysvshm);
```

`user_struct` 里的 `mq_bytes` 同理，塞进 `ANDROID_KABI_USE(1, ...)`。

**没有这一步，开 SYSVIPC 就是给 vendor 模块埋雷。**

### 3. vermagic 必须逐字节一致

模块加载时内核会比对 vermagic 字符串：

```
5.4.302-ikun-NekoMake-star-260929-qgqi+ SMP preempt mod_unload aarch64
```

差一个字符，vendor 模块直接拒载 —— 表现是开机白屏或者没 WiFi。所以我直接把 `CONFIG_LOCALVERSION` 写成原厂那串（包括结尾那个 `+`）。

顺带一提：**原厂给的版本串和 `uname -r` 显示的不完全一样**，`qgqi` 和 `qqgi` 我一开始还看错了，最后以 boot.img 里 `strings` 出来的为准。

### 4. 为什么用 AK3 而不是直接刷 boot.img

第一次失败还有个隐藏原因：我 fastboot 刷的 boot.img 用的是 **ROM 安装包里的 ramdisk**。但如果你装 ROM 时选了「面具」，设备上的 boot 其实是 `magisk.img`（ramdisk 被 Magisk 改过）；系统版本也可能和安装包不一致。

**AK3 的做法是：解包设备上当前真实的 boot，只替换 kernel，ramdisk 原样保留。** 这才是正确的换内核姿势。

---

## 五、最终加了什么（config 增量）

| 类别 | 加了什么 |
|---|---|
| IPC | SYSVIPC、POSIX_MQUEUE（含 SYSCTL） |
| 命名空间 | IPC_NS、PID_NS、USER_NS |
| 网络 | MACVLAN、IP_SET、IP6_NF_NAT、IP6_NF_TARGET_MASQUERADE、XT_TARGET_REJECT/LOG、XT_MATCH_ADDRTYPE/RECENT、XT_SET |
| 文件系统 | TMPFS_XATTR、TMPFS_POSIX_ACL |
| Docker 用 cgroup | CGROUP_PIDS、CGROUP_DEVICE、CGROUP_PERF、CGROUP_NET_PRIO、BLK_DEV_THROTTLING、NET_CLS_CGROUP |

其余一律照抄 ROM 原厂配置，一个字没动。

编译参数：

```bash
make -j8 ARCH=arm64 LLVM=1 LLVM_IAS=1 O=out-star Image modules
# clang 18.1.8 + ThinLTO，8 核约 9~12 分钟
```

产物：`Image` 47.6MB，AK3 zip 25MB。

---

## 六、注意事项（重点，想折腾的必读）

### ⚠️ 1. 这颗内核只认这套 ROM
vermagic 被我写死成朗月的版本串。换成官方澎湃、或者其他移植包，vendor 模块对不上号 —— 会白屏、没 WiFi。**换 ROM 就必须重编**，改 `CONFIG_LOCALVERSION` 即可。

### ⚠️ 2. 只适用小米 11 Ultra
包里的校验写的是 `star`。11 Pro（mars）、11（venus）、K40 Pro（haydn）都不行，得用各自 defconfig 重编（源码本身支持这几台）。

### ⚠️ 3. 别装官方 KernelSU 管理器
BakaSU 支持多管理器，官方 KernelSU 管理器能驱动它，但**两套版本号体系完全不同**（官方 32xxx，BakaSU 是 `30000+提交数+700`），会永远显示"版本不匹配"。用 BakaSU 自己的管理器，而且版本要跟内核 UAPI 对上。

### ⚠️ 4. CPU 限流（`--cpus`）修不了
检查里唯一黄的就是它。三个原因叠在一起：

1. `init/Kconfig` 写着 `CFS_BANDWIDTH depends on FAIR_GROUP_SCHED && !SCHED_WALT`，而骁龙内核开了高通 WALT 调度，**结构性互斥**；
2. 你这台设备 cgroup v2 只暴露了 `pids` 控制器（`/sys/fs/cgroup/cgroup.controllers` 只有一行），cpu 控制器绑在 cgroup v1 的 `/dev/cpuctl`，而那里没有 `cpu.cfs_quota_us`（正是 CFS_BANDWIDTH 缺失的表现）；
3. Droidspaces 官方文档明确警告：在 GKI 上开 CFS_BANDWIDTH 会改掉数千个导出符号的 CRC，**stock vendor 模块会拒载导致 bootloop**，除非你能用同一份源码重编设备上全部模块 —— 闭源模块做不到。

**替代方案**：用 `taskset -c 0-3` 绑核（走 `sched_setaffinity`，不依赖 cgroup），再配合已经绿色的**内存限制**和 `--pids-limit`。

### ⚠️ 5. 少了几种 zram 压缩算法
ROM 内核里的 LZ4KD / ZSTDN 压缩器、`ZRAM_MULTI_COMP`、`OPLUS_FEATURE_HANS` 是作者私有补丁，公开仓库里没有。不影响开机和使用，只是 zram 少几个算法可选。

### ⚠️ 6. 一定要留回滚
换内核前把原 boot 备份好（或留着 ROM 安装包）。翻车了 TWRP 重刷 ROM 包就回来了，数据不丢。换内核本身不动 data 分区。

### ⚠️ 7. 跑 Docker 的实际建议
- 内存限制一定要开（`--memory=4G`），12GB 内存听着多，Immich 一跑人脸识别照样能吃完；
- 用 `taskset` 把重任务摁在 4 个核上，避免 8 核全开掉电发热；
- SELinux 是 Enforcing，容器里跑 rootless Docker / Podman 要开 Droidspaces 的"允许沙箱"（需要 USER_NS，这颗内核有）。

---

## 七、想自己复现？命令都在这

```bash
# 1. 拉源码（用 tarball，release 直链国内常 502）
curl -sL -o s4.tar.gz "https://api.github.com/repos/MiYume0721/android_kernel_xiaomi_sm8350_miyume/tarball/Stable4"

# 2. 解压到 Linux 容器里（不要放在 macOS 的 APFS 上编）
docker run -d --name kbuild -v "$PWD":/work ubuntu:22.04 sleep infinity
docker exec kbuild bash -c 'apt update && apt install -y build-essential bc bison flex libssl-dev libelf-dev python3 rsync kmod cpio device-tree-compiler xz-utils git clang-18 lld-18 llvm-18'

# 3. KSU 子模块（rc1 = a9216b04）
curl -sL -o ksu.tar.gz "https://api.github.com/repos/ReSukiSU/ReSukiSU/tarball/v4.2.0-rc1"
tar -xzf ksu.tar.gz -C KernelSU --strip-components=1
cd KernelSU && git init && git add -A && git commit -m init

# 4. 打两个 ABI 补丁（sysvipc / posix_mqueue）
patch -p1 < 001.GKI-below-6.12-fix_sysvipc_kabi_6_7_8.patch
patch -p1 < 002.5.10_or_lower_use_android_abi_padding_for_posix_mqueue.patch

# 5. 配置 + 编译
make -j8 ARCH=arm64 LLVM=1 LLVM_IAS=1 O=out-star olddefconfig
make -j8 ARCH=arm64 LLVM=1 LLVM_IAS=1 O=out-star Image modules

# 6. 验证（别跳过这步）
grep epoll_pwait2 out-star/System.map        # 必须有
strings out-star/arch/arm64/boot/Image | grep "SMP preempt mod_unload"
```

打包用 AnyKernel3，`anykernel.sh` 里把 `do.devicecheck` 设成 0（TWRP 里 `ro.product.device` 未必等于 `star`），`split_boot` + `flash_boot` 只换 kernel。

---

## 八、最后

从早上十点半定位源码，到下午两点出可用内核，中间交了两次学费：一次是源码版本选错，一次是没意识到 ramdisk 的来源问题。

有几点感受：

1. **ROM 作者的「不要刷其他内核」是有道理的**，但他们说的是"别刷别人的"，不是"别自己编"。同源重编 + 只加必要开关，是这个限制下的正解。
2. **安卓 17 对新 syscall 的依赖比想象中硬**，SystemUI 缺个 `epoll_pwait2` 就直接崩，这不是配置问题，是版本问题。
3. **GKI 的 ABI padding 机制是保命的**，没有它，开任何影响结构体布局的选项都会连累闭源模块。
4. **别迷信版本号**，KernelSU 那套 UAPI 匹配比版本号大小重要得多。

感谢 HoshinoNeko 内核作者 MiYume0721 和 BakaSU(ReSukiSU) 团队的开源工作，也感谢朗月把 OS4.0 移植到 11U 上。

折腾有风险，刷机前请备份，出问题自己负责 😄

#小米11Ultra #安卓17 #澎湃OS #内核编译 #Docker #Droidspaces #骁龙888
