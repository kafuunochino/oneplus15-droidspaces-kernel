# 013 Gaming TEST offline validation

## Build identity

- Device: OnePlus 15 PLK110 / OP60FFL1
- OS: `PLK110_16.0.9.400(CN01)`
- Exact GKI source commit:
  `b2a876903b495c444a94b16f50d1463ffe953957`
- Kernel release:
  `6.12.23-android16-5-gb2a876903b49-ab14541642-4k`
- Kernel Image SHA-256:
  `12f7cb678af107c81e72a9021e688dd48d24f2d4b7f70243291477a05681a19d`

## Configuration gates

The embedded kernel configuration was extracted from the built Image and
checked for:

```text
CONFIG_SYSVIPC=y
CONFIG_POSIX_MQUEUE=y
CONFIG_IPC_NS=y
CONFIG_PID_NS=y
CONFIG_USER_NS=y
CONFIG_DEVTMPFS=y
CONFIG_NTSYNC=y
CONFIG_VIRTUALIZATION=y
CONFIG_KVM=y
CONFIG_MODULE_SIG_PROTECT=y
CONFIG_SYSTEM_TRUSTED_KEYS="certs/oneplus-stock-gki.pem"
CONFIG_RANDSTRUCT_NONE=y
```

## kABI and stock-module gates

```text
base_task_struct_size=5184
new_task_struct_size=5184
common_top_level_fields=211
top_level_layout_changes=0
common_symbols=8900
crc_changes_total=23
crc_changes_rust=23
crc_changes_non_rust=0
```

- SysV semaphore state uses Android kABI reserve slot 1.
- The separately allocated SysV shared-memory state pointer uses slot 2.
- Slot 3 remains untouched.
- All shared non-Rust export CRCs match the split baseline.
- 538 normal stock modules have no new CRC or missing-symbol incompatibility.
- The only accepted exception is the already unused
  `system_dlkm/rust_binder.ko`: four known Rust CRC mismatches plus
  `rust_helper_from_kuid` being unavailable when USER_NS is enabled.

## BOOT gates

- Android boot header: v4
- Partition image size: 100663296 bytes
- Ramdisk size: 0 bytes, matching stock
- Embedded kernel config: byte-identical to the checked build config
- Stock public module-signing certificate SHA-256:
  `F28DBCC60085B21A3CFF1342482897FA640B468847473147834F26C4FEB2DF43`
- AVB hash footer verification: PASS
- AVB algorithm: `NONE`

## Unexpected-payload audit

- Added-source-line matches for permission-changing, SELinux-relabeling,
  usermode-helper, network downloader, or delayed permission worker primitives:
  0
- Diffs to `drivers/misc/ntsync.c` or
  `include/uapi/linux/ntsync.h`: 0
- Third-party executable/module/daemon payloads: 0
- BOOT ramdisk payload bytes: 0

Result: all offline gaming USER_NS/NTSYNC pointer-state build gates passed.
This result does not replace live phone testing.
