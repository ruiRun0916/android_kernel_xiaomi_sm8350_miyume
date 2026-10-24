# Release v2 · 2026-10-24

## 小米 11 Ultra · 澎湃 OS 4.0 / Android 17 · Droidspaces 内核

基于 HoshinoNeko **Stable4**（`d5dae54`，Linux 5.4.302）重编，只叠加容器所需开关。

### 支持设备

上游源码覆盖四台骁龙 888 机型，本 Release 提供 **star** 的成品：

| 设备 | 代号 | 译名 | defconfig | 本 Release |
|---|---|---|---|---|
| 小米 11 Ultra | `star` | 星级 | `star_defconfig` | 已提供 |
| 小米 11 Pro | `mars` | 三月 | `star_defconfig` | 需自行编译 |
| 小米 11 | `venus` | 金星 | `venus_defconfig` | 需自行编译 |
| Redmi K40 Pro / Pro+ | `haydn` | — | `haydn_defconfig` | 需自行编译 |

其他机型不可直接刷本包（ramdisk、DTB、vendor 模块与 vermagic 机型标识均不同），请按仓库 `docs/BUILD.md` 用对应 defconfig 重编。

### 附件

| 文件 | 大小 | 用途 |
|---|---|---|
| `AK3-Star-Stable4-Droidspaces-v2.zip` | 24.8 MB | TWRP 卡刷，解包设备当前 boot 只换 kernel，ramdisk 保留（推荐） |
| `boot-stable4-droidspaces-v2.img` | 94.3 MB | fastboot 直刷，ramdisk 取自 ROM 包 `OS4.0.4.0`，系统版本不同请用 AK3 |

### 内核

- 版本：`5.4.302-ikun-NekoMake-star-260929-qgqi+`
- vermagic：`5.4.302-ikun-NekoMake-star-260929-qgqi+ SMP preempt mod_unload aarch64`（与朗月 ROM 原厂一致，vendor 模块可正常加载）
- 编译器：clang 18.1.8 + ThinLTO
- 构建时间：2026-10-24
- Image 大小：47,634,944 字节

### 新增配置

- IPC：`SYSVIPC`、`POSIX_MQUEUE`（走 ABI padding 槽位，结构体零位移）
- 命名空间：`IPC_NS`、`PID_NS`、`USER_NS`
- 网络：`MACVLAN`、`IP_SET`、`IP6_NF_NAT`、`IP6_NF_TARGET_MASQUERADE`、`XT_TARGET_REJECT/LOG`、`XT_MATCH_ADDRTYPE/RECENT`、`XT_SET`
- 文件系统：`TMPFS_XATTR`、`TMPFS_POSIX_ACL`
- Docker cgroup：`CGROUP_PIDS`、`CGROUP_DEVICE`、`CGROUP_PERF`、`CGROUP_NET_PRIO`、`BLK_DEV_THROTTLING`、`NET_CLS_CGROUP`

### Root

- 内核内置 BakaSU（原 ReSukiSU）v4.2.0-rc1
- 内核侧版本：`v4.2.0-rc2-337bdf71@ReSukiSU`，版本码 **35159**，UAPI **2**
- 配套管理器：**v4.2.0-rc1（35061/2）**。管理器 UAPI 必须等于 2，否则会提示"需要更新内核"

### 刷入

TWRP 卡刷 `AK3-Star-Stable4-Droidspaces-v2.zip`。
AnyKernel3 会解包设备当前 boot，**只替换 kernel，ramdisk 原样保留**，不影响 data。

### 已知限制

- `--cpus` / CPU 限流不可用（`CFS_BANDWIDTH` 与高通 `SCHED_WALT` 在内核 Kconfig 中互斥；且 cgroup v2 仅暴露 `pids`）。请用 `taskset -c 0-3` 绑核
- 缺少 ROM 作者私有的 zram 压缩器（LZ4KD / ZSTDN）与 `ZRAM_MULTI_COMP`、`OPLUS_FEATURE_HANS`
- 仅适用于小米 11 Ultra + 朗月澎湃 OS 4.0 移植包；换 ROM 需改 `CONFIG_LOCALVERSION` 重编
- 不要安装官方 KernelSU 管理器（版本号体系不同，永久提示不匹配）

### 回滚

TWRP 重刷 ROM 包，或恢复备份的 boot 分区。

### 校验值

见 GitHub Release 页面附带的 SHA256。
