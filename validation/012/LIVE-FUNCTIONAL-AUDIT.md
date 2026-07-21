# OnePlus 15 Droidspaces 012 live functional audit

Date: 2026-07-21 (Asia/Shanghai)

## Result

The 012 kernel boots Android and starts Ubuntu 24.04.4 LTS successfully. Droidspaces reports every required, recommended, and optional kernel capability as available. The container is operational, but the full optional stack is not yet complete.

## Verified working

- Kernel release remains `6.12.23-android16-5-gb2a876903b49-ab14541642-4k`.
- Ubuntu systemd is host PID 20979 and container PID 1 (`NSpid: 20979 1`).
- PID, IPC, mount, UTS, network, and cgroup namespaces differ from Android.
- systemd, journald, udevd, networkd, resolved, logind, D-Bus, and containerd are running.
- NAT DHCP assigned `172.28.180.158/16`; default route and DNS are installed.
- ICMP to `1.1.1.1` succeeded and HTTPS to GitHub returned HTTP 200.
- Android internal storage is mounted read/write at `/storage/emulated/0` and was read successfully.
- GPU device nodes `/dev/kgsl-3d0` and `/dev/dri/renderD128` are visible in the container.
- SysV IPC and POSIX mqueue kernel support are enabled; `/dev/mqueue` is mounted.
- Five non-leader-thread `execve` tests completed without reboot, panic, Oops, or boot-ID change.
- Android Wi-Fi, Bluetooth, LTE registration, audio server, biometric services, and USB charging are healthy.
- Android SELinux remains globally enforcing.

## Incomplete or unverified

### Docker

`systemctl is-system-running` returns `degraded` only because `docker.service` and `docker.socket` failed. The immediate failure is the missing iptables `addrtype` match. Docker's bundled kernel checker also reports:

- cgroup v2 exposes no cpu, cpuset, io, memory, or pids controllers in the container.
- `CONFIG_CGROUP_DEVICE` missing.
- `CONFIG_CGROUP_PIDS` missing.
- `CONFIG_BRIDGE_NETFILTER` missing.
- `CONFIG_NETFILTER_XT_MATCH_ADDRTYPE` missing.
- IPv6 NAT/MASQUERADE and several optional overlay/IPVS/NFT features missing.

### Graphics and audio

- Termux:X11 Android app is installed, but the Termux `termux-x11-nightly` package/loader and X11 socket are absent.
- `virglrenderer-android` and the VirGL socket are absent.
- Termux PulseAudio and its socket are absent.
- Ubuntu has no Mesa DRI directory, Vulkan ICDs, or EGL/GL/Vulkan libraries detected, so device-node visibility alone does not prove usable acceleration.
- Termux curl is still broken because its installed libssh2 lacks `libssh2_session_callback_set2`.

### Hardware access and virtualization

- `enable_hw_access=0`; `/dev/snd` is therefore not exposed and hardware-access mode was not tested.
- `CONFIG_KVM=y` and the platform advertises VM support, but `/dev/kvm` is absent on Android and in the container, so KVM is not currently usable.

## Stability and security notes

- pstore is empty and the current fatal-error scan is clean.
- Kernel taint value 4608 corresponds to out-of-tree modules plus an earlier warning. Prior captures show routine OnePlus boot/vendor warnings and hung-task diagnostic stack dumps; no new Droidspaces panic was observed in this run.
- The `droidspacesd` SELinux domain is permissive even though global SELinux is enforcing. This permits operation but produces heavy AVC audit noise and is not a fully hardened policy.

## Overall classification

- Android daily use: pass in the inspected state.
- Droidspaces base container and systemd: pass.
- NAT networking and Android storage: pass.
- 012 crash-path regression test: pass.
- Docker: fail/incomplete.
- X11/VirGL/PulseAudio: fail until Termux packages are repaired and installed.
- Direct GPU acceleration: device mapping passes; userspace stack is incomplete.
- Hardware-access mode and KVM: unavailable or not tested.
