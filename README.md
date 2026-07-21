# OnePlus 15 Droidspaces kernel build

Reproducible build inputs for an experimental OnePlus 15 (PLK110 / OP60FFL1)
Android 16 GKI 6.12 kernel with Droidspaces support.

## Compatibility status

The tested phone audit was captured from OxygenOS
`PLK110_16.0.9.400(CN01)`, security patch `2026-07-01`, with stock kernel
`6.12.23-android16-5-gb2a876903b49-ab14541642-4k`.

The newest available OnePlus manifest used here (`oneplus/sm8850`,
`oneplus_15.xml`) resolves the common kernel to
`d9053b907db4bb5da938e9cf947d0ae32302ceaf`, whose OnePlus commit message names
support for `16.0.7.207(CN01)`. The GKI/KMI family matches, but the source and
running firmware do not match exactly. No build from this repository should be
described as guaranteed safe to flash.

The Release boot image is deliberately marked **EXPERIMENTAL**. Prefer
temporary `fastboot boot` testing, only after live fastboot output confirms the
bootloader is unlocked. Never flash the generated `vendor_boot`, `init_boot`,
`dtbo`, or `vbmeta` images to the newer firmware.

## Kernel changes

- Enables `CONFIG_SYSVIPC`, `CONFIG_POSIX_MQUEUE`, `CONFIG_PID_NS`,
  `CONFIG_IPC_NS`, and `CONFIG_DEVTMPFS` for Droidspaces.
- Retains `CONFIG_VIRTUALIZATION=y` and `CONFIG_KVM=y` from the stock baseline.
- Retains `CONFIG_MODULE_SIG_ALL=y`, `CONFIG_MODULE_SIG_PROTECT=y`, 4 KiB pages,
  CFI, modversions, SELinux, Rust Binder, and other captured stock KMI/security
  settings.
- Keeps `CONFIG_USER_NS` disabled, matching the stock hardening policy.
- Adds selected ipset/netfilter and tmpfs ACL/xattr options for container
  networking and filesystems.
- Applies the Droidspaces GKI 6.12 `task_struct` kABI layout fix and exports the
  two IPC namespace symbols required by the Rust Binder module.

## Repository contents

- `patches/`: source and defconfig changes
- `config/`: requested features and captured stock security/KMI baseline
- `manifest/`: removes two unavailable, build-irrelevant test prebuilts
- `scripts/build-oneplus15.sh`: sync, patch, Kleaf build, embedded-config checks
- `.github/workflows/`: manual-only GitHub Actions workflow

The full OnePlus/Qualcomm source tree and Bazel cache are intentionally not
committed. They occupy tens of gigabytes and are reproducibly synchronized by
the pinned manifest.

## Verified experimental artifact

The locally built final kernel reports:

```text
6.12.23-android16-5-o-gd9053b907db4-4k
```

The final Image embedded config was checked for all Droidspaces, KVM, module
signature protection, and USER_NS hardening values. The packaged boot uses
Android boot header v4, contains no ramdisk, preserves the OnePlus 16 KiB
pre-AVB padding and 96 MiB partition size, and has an unsigned AVB footer with
Android 16 / `2026-07-01` metadata. OnePlus's production private key is not
available, so the image requires a genuinely unlocked bootloader.

See the Release notes and included `README.md` before testing.
