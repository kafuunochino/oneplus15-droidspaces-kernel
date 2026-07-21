# OnePlus 15 Droidspaces kernel

一加 15（PLK110 / OP60FFL1）Android 16、GKI 6.12 的 Droidspaces
兼容内核构建记录与测试镜像。

> **警告：这是 TEST 镜像，不是通用刷机包。** 仅面向下列已审计系统，刷入前必须确认
> Bootloader 已解锁并保留原版 `boot.img`。不要刷写本仓库生成或提到的
> `vendor_boot`、`init_boot`、`dtbo`、`vbmeta`。

## 最新实机状态（012）

- 设备：OnePlus 15 / PLK110 / OP60FFL1
- 系统：`PLK110_16.0.9.400(CN01)`，安全补丁 `2026-07-01`
- 内核版本：`6.12.23-android16-5-gb2a876903b49-ab14541642-4k`
- 发布镜像：`boot-oneplus15-droidspaces-gki-r53-kabi-pointer-state-vendor-guards-e0a6769ae18f-stockcert-TEST.img`
- SHA-256：`7337a199f709720be7a82560c0bc7df8d5d41f59c4b528d155b65501f45db517`

012 已在上述手机上刷入并完成实机测试：

- Android 正常开机，Wi-Fi、蓝牙、双卡 LTE 注册、音频、指纹和 USB 充电正常。
- Droidspaces v6.4.5 的 MUST HAVE、RECOMMENDED、OPTIONAL 检查全部通过。
- Ubuntu 24.04.4 LTS 的 systemd 作为容器 PID 1 运行。
- PID、IPC、mount、UTS、network、cgroup namespace 已与 Android 隔离。
- NAT、DNS、HTTPS 外网访问及 Android 内部存储挂载正常。
- 连续 5 次“子 PID namespace 内非主线程 exec”回归测试通过，没有重启、panic、Oops
  或 boot ID 变化。

详细实机检查见 [`validation/012/LIVE-FUNCTIONAL-AUDIT.md`](validation/012/LIVE-FUNCTIONAL-AUDIT.md)。

## 012 内核改动

- 启用 Droidspaces 必需的 `CONFIG_SYSVIPC`、`CONFIG_POSIX_MQUEUE`、
  `CONFIG_PID_NS`、`CONFIG_IPC_NS`、`CONFIG_DEVTMPFS`。
- 保持 `CONFIG_USER_NS` 关闭，保留 CFI、modversions、SELinux、模块签名保护等
  stock GKI 安全基线。
- 使用 Android 官方 `task_struct` kABI reserve：slot 1 保存 `sysv_sem`，slot 2
  保存独立分配的 `sysv_shm` 指针，slot 3 保持未占用。
- 嵌入从原版内核提取的 OnePlus **公开**模块签名证书，使原厂
  `system_dlkm` / `vendor_dlkm` 模块继续通过签名验证；仓库不包含任何私钥。
- 011：子 PID namespace 任务不再进入不兼容的 OnePlus Midas cpufreq vendor hook，
  Android 初始 PID namespace 行为不变。
- 012：仅对来自子 PID namespace、目标恰为 `do_execveat_common` 的 kprobe
  跳过 OnePlus Secure Guard pre/post handler，原始指令仍正常单步执行；Android 任务和
  其他 kprobe 目标不变。

## 离线验证

- `task_struct` 大小保持 5184 bytes。
- 211 个共同顶层字段没有布局变化。
- 8901 个共同导出符号没有非 Rust CRC 变化。
- 检查 539 个原厂模块，没有非 Rust 不匹配。
- 唯一 4 个不匹配来自未使用的 `system_dlkm/rust_binder.ko` Rust 符号。
- `abi_symbollist` 与 `vmlinux.symvers` 相比 011 未变化。
- boot header v4、原版 ramdisk、96 MiB 分区大小、16 KiB pre-AVB padding 均已核对。
- AVB footer 为 `Algorithm: NONE`；必须使用真正解锁的 Bootloader。

原始验证输出位于 [`validation/012/`](validation/012/)。

## 当前已知限制

- Docker 尚不完整。当前缺少 `CONFIG_NETFILTER_XT_MATCH_ADDRTYPE`、
  `CONFIG_CGROUP_DEVICE`、`CONFIG_CGROUP_PIDS`、`CONFIG_BRIDGE_NETFILTER`，容器内
  cgroup v2 也没有可用控制器，因此 `docker.service` 会失败。
- Termux:X11、VirGL、PulseAudio 需要 Termux 用户空间组件和套接字；它们不随
  boot 镜像提供。测试手机当前这些 Termux 包尚未完整安装。
- GPU 设备节点可见，但测试 Ubuntu 尚无 Mesa/Vulkan/EGL 用户态栈，不能据此声称
  3D 加速已完整可用。
- `CONFIG_KVM=y`，但 Android 没有创建 `/dev/kvm`，所以当前不能使用 KVM。
- 硬件访问模式测试时处于关闭状态。
- Android 全局 SELinux 仍为 Enforcing，但 Droidspaces 模块把 `droidspacesd` 域设为
  permissive，会产生大量 AVC 审计日志。

## 下载、校验与刷入

从仓库的 **Releases** 下载最新 012 TEST 镜像及 `SHA256SUMS.txt`，在电脑校验：

```powershell
Get-FileHash -Algorithm SHA256 .\boot-oneplus15-droidspaces-gki-r53-kabi-pointer-state-vendor-guards-e0a6769ae18f-stockcert-TEST.img
```

仅在 live fastboot 明确显示 Bootloader 已解锁、并已备份当前槽位原版 boot 后测试：

```text
fastboot getvar current-slot
fastboot getvar unlocked
fastboot flash boot boot-oneplus15-droidspaces-gki-r53-kabi-pointer-state-vendor-guards-e0a6769ae18f-stockcert-TEST.img
fastboot reboot
```

若无法开机或硬件功能异常，立即进入 fastboot 刷回自己备份的原版 `boot.img`：

```text
fastboot flash boot boot_a.img
fastboot reboot
```

SukiSU Ultra 使用的 LKM / `init_boot` 不在本镜像内，本次只替换 `boot` 分区。

## 源码与构建记录

- GKI common 基线：`b2a876903b495c444a94b16f50d1463ffe953957`
- stock build number：`14541642`
- `patches/`：按编号记录完整 001–012 修改序列。
- `scripts/server/`：实际 Linux 构建、审计、打包与验证脚本。
- `config/`：Droidspaces 请求配置和 stock KMI/security 基线。
- `validation/012/`：最终 ABI、模块 CRC、AVB、哈希和实机检查结果。

完整 Qualcomm/OnePlus/AOSP 源码树和 Bazel 缓存占用数十 GB，不提交到 GitHub；脚本会在
Linux 构建机上同步对应源码。旧的 GitHub Actions / OnePlus 源码实验不能复现当前 012
发布镜像，012 以精确 stock GKI r53 commit 为基线在持久 Linux 构建机完成。
