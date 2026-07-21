# OnePlus 15 Droidspaces kernel — experimental test build

This package is for the OnePlus 15 (PLK110 / OP60FFL1) only.

## Important compatibility warning

The phone audit reports OxygenOS `PLK110_16.0.9.400(CN01)` with the
`2026-07-01` security patch. The newest available OnePlus source manifest used
for this build identifies support for `16.0.7.207(CN01)`. The GKI/KMI release
family matches (`6.12.23-android16-5`), but exact vendor-module compatibility
cannot be guaranteed. Treat this as an experimental build, not a safe permanent
flash.

The audit also recorded `flash_locked=1`, `vbmeta_state=locked`, and verified
boot `green`, while the owner reports that the bootloader is unlocked. Resolve
that conflict before testing. In bootloader/fastboot mode, `fastboot getvar
unlocked` must report `yes` or `true`. If it does not, stop.

## What is enabled

- Droidspaces: SYSVIPC, POSIX_MQUEUE, PID_NS, IPC_NS, DEVTMPFS
- ARM64 virtualization: VIRTUALIZATION and KVM
- Stock module-signing protection: MODULE_SIG_ALL and MODULE_SIG_PROTECT
- USER_NS remains disabled to preserve the stock hardening policy

The boot image has Android boot header v4, no ramdisk, and an unsigned AVB
footer with the original Android 16 / 2026-07-01 metadata. It cannot reproduce
OnePlus's private production signature and is only for a genuinely unlocked
bootloader.

## Safer first test

Keep `boot_a-stock-backup.img` and its SHA-256 hash on the computer. Prefer a
temporary boot, if the device's fastboot implementation supports it:

```text
fastboot boot boot-oneplus15-droidspaces-*-EXPERIMENTAL.img
```

Temporary boot does not replace the active boot partition; a normal reboot
returns to the installed kernel. Do not flash `vendor_boot`, `init_boot`,
`dtbo`, or `vbmeta` from this build.

After Android starts, test camera, fingerprint, Wi-Fi, mobile data, Bluetooth,
GPU/games, DRM/TEE-dependent apps, charging, audio, and SukiSU Ultra before
starting Droidspaces. Then check:

```text
su -c uname -a
su -c /data/local/Droidspaces/bin/droidspaces check
su -c "zcat /proc/config.gz | grep -E 'CONFIG_(SYSVIPC|POSIX_MQUEUE|PID_NS|IPC_NS|DEVTMPFS|VIRTUALIZATION|KVM)='"
```

If temporary boot is unsupported, do not permanently flash until the exact
unlock state and rollback command have been confirmed from live fastboot
output.
