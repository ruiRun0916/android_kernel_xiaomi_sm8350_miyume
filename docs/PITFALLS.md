# 踩坑记录

按踩坑顺序排列，每条都给了现象与判据，方便别人快速定位。

## 1. clang 拉不下来

**现象**：Dockerfile 里 `curl apt.llvm.org/llvm-snapshot.gpg.key` 卡住或超时。

**处理**：改用清华镜像 `https://mirrors.tuna.tsinghua.edu.cn/llvm-apt/jammy/`，并把 `ports.ubuntu.com` 换成 `mirrors.tuna.tsinghua.edu.cn/ubuntu-ports`。镜像源缺 GPG key 时加 `[trusted=yes]` 即可（构建机本地可信）。

## 2. 子模块缺失导致 Kbuild 直接 Stop

**现象**：

```
-- Can't find ReSukiSU git submodule!
../drivers/kernelsu/Kbuild:67: *** You should use ReSukiSU as a git submodule instead of copying code directly.  Stop.
```

**原因**：GitHub 的 tarball 不含 submodule；`drivers/kernelsu` 是软链，`KernelSU/` 是空目录；Kbuild 硬检查 `KernelSU/.git`。

**处理**：放入源码 + `git init` + 至少一次提交，见 BUILD.md 第 3 节。

## 3. macOS 大小写不敏感，内核编不过（最隐蔽）

**现象**：

```
make[3]: *** No rule to make target 'net/netfilter/xt_DSCP.o', needed by 'net/netfilter/built-in.a'.  Stop.
```

**原因**：APFS 默认大小写不敏感，`xt_DSCP.c` 与 `xt_dscp.c` 被合并为同一 inode。全树共 13 组 26 个此类文件，都在 `net/netfilter/` 与一个 litmus 测试里。

**判据**：

```bash
ls -li xt_DSCP.c xt_dscp.c   # inode 相同即中招
```

**处理**：整棵树拷进容器的 ext4 再编；若已合并，只能从 tarball 里用 `tar -xO` 逐文件恢复正确内容。

## 4. 版本串拼写错误会静默失败

原厂 `uname -r` 与 boot.img 里 `strings` 出来的字符串要以 **boot.img 为准**。本次实际是 `...-260929-qgqi+`，末尾带一个 `+` 而 `CONFIG_LOCALVERSION_AUTO` 未开启——直接写进 `CONFIG_LOCALVERSION` 最稳，不要指望 setlocalversion 自动补。

## 5. 源码版本选错 → 编译成功但开不了机

**现象**：Image 正常产出，vermagic 也对，刷入后黑屏/卡开机。

**判据**：原厂 config 里存在源码树中**没有**的符号：

```
CONFIG_ZRAM_MULTI_COMP / CONFIG_DM_USER / CONFIG_ANDROID_VENDOR_FREEZER_COMPAT / CONFIG_OPLUS_FEATURE_HANS
```

且原厂内核二进制里有 `dm_user` 符号，自己编的没有。说明 ROM 内核是「上游 + 作者私有补丁」，用当前公开分支复刻不出等同物。

**本例真正原因**：用了旧分支 Stable2，而新版 HyperOS 4.0 / Android 17 需要 `epoll_pwait2`，缺了 SystemUI 自检崩溃。换 **Stable4** 后一次成功。

**教训**：先读上游 release notes 的"无法开机/修复"条目，再去排自己的配置。

## 6. AK3 报 Unsupported device

**现象**：TWRP 里刷 AK3 提示 `Unsupported device. Aborting...`

**原因**：`do.devicecheck=1` 且 `device.name1=star`，但 TWRP 环境下 `ro.product.device` 未必等于 `star`。

**处理**：`do.devicecheck=0`（自己在刷机前确认机型）。

## 7. 别用自己重打的 boot.img 顶替 AK3

ROM 安装脚本里，选「面具」会把 `magisk.img`（ramdisk 被 Magisk 改造）刷进 boot，选「无面具」才刷原厂 `boot.img`。用安装包里的 `boot.img` 重新打包再刷，等于把设备上真实的 ramdisk 换掉，容易卡开机。

AK3 的 `split_boot` + `flash_boot` 只换 kernel、保留设备当前 ramdisk，是最稳的换核方式。

## 8. KernelSU 版本号 / UAPI 的两层匹配

- **版本码**：`30000 + git 提交数 + 700`。手动 `git init` 只有 1 个提交 → `30701`，管理器会判为过旧。
- **UAPI 版本**：才是管理器判断"功能是否完整"的真正依据：

```kotlin
fun isFullFeatured(): Boolean = isManager && kernelUAPIVersion == managerUAPIVersion
```

界面上 `35159/2` 的含义是「版本码 / UAPI 版本」。内核是 rc1 代码（UAPI=2），管理器若是 rc2（UAPI=4）就会一直提示"需要更新内核"，此时**换成 rc1 管理器**比改内核划算。

## 9. CPU 限流修不了

`init/Kconfig`：

```kconfig
config CFS_BANDWIDTH
	bool "CPU bandwidth provisioning for FAIR_GROUP_SCHED"
	depends on FAIR_GROUP_SCHED && !SCHED_WALT
```

骁龙内核开 `SCHED_WALT`，于是 `CFS_BANDWIDTH` 连 `.config` 里都不会出现。
另外设备 cgroup v2 只暴露 `pids`（`/sys/fs/cgroup/cgroup.controllers`），cpu 控制器挂在 cgroup v1 的 `/dev/cpuctl`，而那里没有 `cpu.cfs_quota_us`。

Droidspaces 官方文档亦警告：GKI 上开 `CFS_BANDWIDTH` 会改变调度结构体、破坏约数千个导出符号的 CRC，stock vendor 模块拒载导致 bootloop，除非能重编设备上全部模块。

**替代**：`taskset -c 0-3`（`sched_setaffinity`，不依赖 cgroup）+ 内存限制 + `--pids-limit`。
