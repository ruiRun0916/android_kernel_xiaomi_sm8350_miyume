# star-droidspaces-kernel

给 **小米 11 Ultra（star / M2102K1C）· 澎湃 OS 4.0 / Android 17** 用的容器友好内核。
基于 [MiYume0721/android_kernel_xiaomi_sm8350_miyume](https://github.com/MiYume0721/android_kernel_xiaomi_sm8350_miyume) **Stable4**（commit `d5dae54`，Linux 5.4.302）重编，
只叠加 Droidspaces / Docker 所需的开关，其余配置与 ROM 原厂保持一致。

产物是一个 AnyKernel3 卡刷包：解包设备上当前真实的 boot，**只替换 kernel**，ramdisk 原样保留。

---

## 支持设备

**只有一台：小米 11 Ultra（`star` / M2102K1C）。**

| 设备 | 代号 | 译名 | 本仓库支持情况 |
|---|---|---|---|
| **小米 11 Ultra** | `star` | 星级 | **支持**，提供成品刷机包 |
| 小米 11 | `venus` | 金星 | 不支持 |
| 小米 11 Pro | `mars` | 三月 | 不支持 |
| Redmi K40 Pro / Pro+ | `haydn` | — | 不支持 |

上游 HoshinoNeko 源码本身覆盖上面四台，但**本仓库只在 star 上验证过并出了成品包**。其余三台的 ramdisk、DTB、vendor 模块与 vermagic 机型标识都不同，未做任何测试，因此不列为支持机型。想自己试的话可以照 [docs/BUILD.md](docs/BUILD.md) 用对应 defconfig 编（`venus_defconfig` / `star_defconfig` / `haydn_defconfig`），风险自负。

### 成品包适用范围

| 项目 | 要求 |
|---|---|
| 机型 | 小米 11 Ultra（`star` / M2102K1C） |
| 系统 | 澎湃 OS 4.0 / Android 17，朗月移植包 `26.10.x`（`OS4.0.4.0.XPBCNXM`） |
| 内核版本串 | `5.4.302-ikun-NekoMake-star-260929-qgqi+`（vermagic 必须一致） |
| 刷入方式 | TWRP 卡刷 |

换成官方澎湃或其他移植 ROM 也要重编——vermagic 对不上会导致 vendor 模块拒载，表现为白屏 / 无 WiFi。

---

## 这个内核加了什么

| 类别 | 选项 |
|---|---|
| IPC | `SYSVIPC`、`POSIX_MQUEUE`（含 SYSCTL） |
| 命名空间 | `IPC_NS`、`PID_NS`、`USER_NS` |
| 网络 | `MACVLAN`、`IP_SET`、`IP6_NF_NAT`、`IP6_NF_TARGET_MASQUERADE`、`XT_TARGET_REJECT`、`XT_TARGET_LOG`、`XT_MATCH_ADDRTYPE`、`XT_MATCH_RECENT`、`XT_SET` |
| 文件系统 | `TMPFS_XATTR`、`TMPFS_POSIX_ACL` |
| Docker cgroup | `CGROUP_PIDS`、`CGROUP_DEVICE`、`CGROUP_PERF`、`CGROUP_NET_PRIO`、`BLK_DEV_THROTTLING`、`NET_CLS_CGROUP` |

其余全部照抄 ROM 原厂 config，驱动集合、调度、显示、相机相关一行未改。

Root 沿用内核内置的 **BakaSU（原 ReSukiSU）v4.2.0-rc1**，与 RC1 管理器（`35061/2`）配对使用；UAPI 版本必须相等，否则管理器会提示更新内核。

---

## 已知不支持的项

| 项 | 原因 |
|---|---|
| `--cpus` / CPU 限流（CFS_BANDWIDTH） | `init/Kconfig` 中 `CFS_BANDWIDTH depends on !SCHED_WALT`，而骁龙内核开启高通 WALT；同时设备 cgroup v2 只暴露 `pids` 控制器。官方文档亦明确：GKI 上开启会破坏 kABI，需重编全部 vendor 模块 |
| zram 的 LZ4KD / ZSTDN 压缩器、`ZRAM_MULTI_COMP`、`OPLUS_FEATURE_HANS` | ROM 作者私有补丁，公开源码中不存在 |
| 官方 KernelSU 管理器 | 版本号体系不同（BakaSU 为 `30000+提交数+700`），会一直提示不匹配 |

CPU 想限流请用 `taskset -c 0-3`（走 `sched_setaffinity`，不依赖 cgroup），内存与进程限制正常可用。

---

## 刷入

下载（Release 页面 `droidspaces-v2`）：

- **推荐**：[AK3-Star-Stable4-Droidspaces-v2.zip](https://github.com/ruiRun0916/android_kernel_xiaomi_sm8350_miyume/releases/download/droidspaces-v2/AK3-Star-Stable4-Droidspaces-v2.zip)（24.8MB，TWRP 卡刷）
  SHA256 `065b04489f72d07874cf2ea6aefe17024d465c494089c56be5aba2d83f11c8ae`
- 备选：[boot-stable4-droidspaces-v2.img](https://github.com/ruiRun0916/android_kernel_xiaomi_sm8350_miyume/releases/download/droidspaces-v2/boot-stable4-droidspaces-v2.img)（fastboot 直刷）

方式一（AK3 卡刷，ramdisk 保留）：

```
1. TWRP 中刷入 AK3 zip
2. 重启，首次开机耐心等待约 5~10 分钟
3. 打开 Droidspaces -> 设置 -> 要求 -> 检查要求
```

方式二（fastboot 直刷）：

```bash
fastboot flash boot boot-stable4-droidspaces-v2.img
fastboot reboot
```

该镜像的 ramdisk 取自 ROM 安装包（`OS4.0.4.0`），**仅当你的系统也是这个版本时使用**；系统版本不同请走 AK3，或直接重编。

回滚：TWRP 重刷 ROM 包（不动 data 分区），或 `fastboot flash boot` 刷回原厂 boot。

---

## 目录结构

```
patches/    两个 GKI ABI padding 补丁（SYSVIPC / POSIX_MQUEUE）
config/     Droidspaces 与 Docker cgroup 的 config fragment
scripts/    一键构建脚本（下载源码、装 KSU 子模块、打补丁、编译、校验）
docs/       BUILD.md 完整复现步骤 / PITFALLS.md 踩坑记录
artifacts/  编译好的 AnyKernel3 刷机包
```

复现构建见 [docs/BUILD.md](docs/BUILD.md)，踩坑记录见 [docs/PITFALLS.md](docs/PITFALLS.md)。

---

## 许可

- `patches/` 派生自 Linux 内核与 ReSukiSU，遵循 **GPL-2.0**。
- `scripts/`、`docs/` 采用 MIT。
- 内核二进制按 GPL-2.0 分发，源码指向上述两个上游仓库及本仓库的补丁与配置。

## 致谢

- [MiYume0721](https://github.com/MiYume0721) — HoshinoNeko 内核
- [Baka-SU/BakaSU](https://github.com/Baka-SU/BakaSU)（原 ReSukiSU）— root 方案
- [ravindu644/Droidspaces-OSS](https://github.com/ravindu644/Droidspaces-OSS) — 容器运行时与内核配置指南
- 朗月 — 澎湃 OS 4.0 的 11U 移植包

刷机有风险，自负。
