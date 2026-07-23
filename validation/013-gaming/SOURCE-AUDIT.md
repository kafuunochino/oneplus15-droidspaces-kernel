# OnePlus 15 gaming-kernel source audit

This audit belongs to the separate 013 gaming TEST build.

Target:

- OnePlus 15 PLK110 / Android 16
- Exact stock GKI r53 base commit:
  `b2a876903b495c444a94b16f50d1463ffe953957`
- Known-good Droidspaces pointer-state/vendor-guard patch stack

Requested additions:

- `CONFIG_USER_NS=y`
- `CONFIG_NTSYNC=y`

## Tutorial patch review

The tutorial points to:

`Goldzxcbug/Droidspaces_Kernel_patch/NTsync`

For Android 16 / kernel 6.12, the repository's compatibility patch has Git
blob SHA:

`a1c3ab3f14606659c28f4cb8d8e497bd7de94e55`

That patch only removes `depends on BROKEN` from `drivers/misc/Kconfig` and
changes the NTSYNC default. No executable code is added by that 6.12
compatibility patch.

The repository's separate `ntsync_base.patch` (Git blob SHA
`1eef4ac205e06cc0d62eabb14d54d4f48c4b2f8f`) was rejected. It contains an
additional delayed in-kernel worker which changes `/dev/ntsync` permissions and
directly rewrites its SELinux label with `__vfs_setxattr_noperm()`. Those changes
are not part of the normal upstream NTSYNC implementation and are unnecessary
for building the kernel feature.

## Applied implementation

`013.enable-gaming-userns-ntsync.patch` only:

1. enables `CONFIG_USER_NS=y`;
2. enables `CONFIG_NTSYNC=y`;
3. removes the `depends on BROKEN` gate from NTSYNC's Kconfig entry.

The existing `drivers/misc/ntsync.c` and
`include/uapi/linux/ntsync.h` from the exact stock GKI commit are not replaced
or modified. No downloaded executable, prebuilt kernel module, boot-time
network client, permission-changing worker, SELinux-label rewrite, telemetry,
or additional daemon is included.

Runtime access to `/dev/ntsync`, if needed later by an unprivileged Ubuntu
user, must be configured visibly in the Android/Droidspaces integration layer
after the gaming boot has passed basic phone testing. It is deliberately not
hidden inside this boot image.
