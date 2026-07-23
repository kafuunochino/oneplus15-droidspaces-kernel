# 013 Gaming TEST — USER_NS + NTSYNC

这是 OnePlus 15 PLK110 / OP60FFL1、OxygenOS
`PLK110_16.0.9.400(CN01)` 的独立游戏兼容测试版。它基于已实机验证的
012 Droidspaces 内核，额外启用 Steam Runtime、Wine/Proton 可能需要的
user namespace 与 NTSYNC。

> 这是 **prerelease / TEST**，已经完成离线构建、ABI、原厂模块、BOOT 结构、
> AVB 和来源审计，但发布时尚未完成手机实机测试。日常使用应继续保留 012
> 稳定测试版和匹配系统版本的原版 `boot.img`。

## 新增功能

| 配置 | 作用 |
| --- | --- |
| `CONFIG_USER_NS=y` | 允许进程创建用户命名空间并映射 UID/GID。Steam Runtime 的 pressure-vessel、bubblewrap 和部分沙箱依赖它。它也会扩大内核攻击面，因此本版单独发布，不替代 012 日常版。 |
| `CONFIG_NTSYNC=y` | 提供 Windows NT 事件、互斥量和信号量的内核同步接口，供 Wine/Proton 减少用户态同步开销并改善部分游戏兼容性。 |
| `CONFIG_VIRTUALIZATION=y` | 保留 Linux 通用虚拟化框架。 |
| `CONFIG_KVM=y` | 保留 ARM64 KVM 支持；Android 当前没有 `/dev/kvm` 时仍不能直接使用虚拟机。 |

012 已有的 Droidspaces 配置继续保留：

- `CONFIG_SYSVIPC=y`
- `CONFIG_POSIX_MQUEUE=y`
- `CONFIG_PID_NS=y`
- `CONFIG_IPC_NS=y`
- `CONFIG_DEVTMPFS=y`
- mount、UTS、network、cgroup namespace
- CFI、modversions、SELinux 和原厂模块签名保护
- SysV IPC 的 Android kABI reserve 布局
- OnePlus Midas 与 Secure Guard 的子 PID namespace 兼容保护

## 来源与后门审计

- 精确 GKI common 基线：
  `b2a876903b495c444a94b16f50d1463ffe953957`
- 013 补丁只启用 `USER_NS`、`NTSYNC`，并移除 NTSYNC 的 `depends on BROKEN`。
- 没有修改或替换原版 `drivers/misc/ntsync.c` 与
  `include/uapi/linux/ntsync.h`。
- 没有加入第三方二进制、内核模块、守护进程、启动联网脚本或 ramdisk 载荷。
- 未采用第三方 `ntsync_base.patch` 中延迟修改 `/dev/ntsync` 权限及直接重写
  SELinux 标签的内核 worker。
- 完整说明见
  [`validation/013-gaming/SOURCE-AUDIT.md`](validation/013-gaming/SOURCE-AUDIT.md)。

## 离线验证结果

- 内核版本：
  `6.12.23-android16-5-gb2a876903b49-ab14541642-4k`
- `task_struct` 仍为 5184 bytes。
- 211 个共同顶层字段的偏移没有变化。
- 8900 个共同导出符号中，非 Rust CRC 变化为 0。
- 538 个正常原厂模块没有新增 CRC 或缺失符号问题。
- 未使用的 `system_dlkm/rust_binder.ko` 保留原有 4 个 Rust CRC 不匹配；
  启用 USER_NS 后它还缺少 `rust_helper_from_kuid`。该例外不影响其余 538 个模块。
- BOOT header v4、空 ramdisk、96 MiB 分区大小及 AVB hash footer 已验证。
- AVB 算法为 `NONE`，只能用于真正解锁的 Bootloader。

详细记录见
[`validation/013-gaming/BUILD-VALIDATION.md`](validation/013-gaming/BUILD-VALIDATION.md)。

## 镜像与校验

镜像：

`boot-oneplus15-droidspaces-gki-r53-gaming-userns-ntsync-12f7cb678af1-stockcert-TEST.img`

SHA-256：

`763e7f8f92b037e0c31f444d1249408e996197645e1b712ac3d9b99604da4ed0`

完整审计包：

`final-gki-r53-gaming-userns-ntsync-test.tar.gz`

SHA-256：

`6fee25ae94e31686366691f363f28b0fb5c721cae1f0b5a5d70a394b530e4a4b`

## 刷入与回滚

先保留当前系统版本对应的原版 boot，并确认当前槽位：

```text
fastboot getvar current-slot
fastboot getvar unlocked
```

优先尝试临时启动：

```text
fastboot boot boot-oneplus15-droidspaces-gki-r53-gaming-userns-ntsync-12f7cb678af1-stockcert-TEST.img
```

如果设备不支持临时启动，再只刷写当前槽位的 boot：

```text
fastboot flash boot boot-oneplus15-droidspaces-gki-r53-gaming-userns-ntsync-12f7cb678af1-stockcert-TEST.img
fastboot reboot
```

不要为本测试刷写 `vendor_boot`、`init_boot`、`dtbo` 或 `vbmeta`。出现开机或
硬件异常时，立即进入 fastboot 刷回匹配当前槽位和系统版本的原版 boot。
