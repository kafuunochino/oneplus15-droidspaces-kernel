# 012 TEST — Droidspaces vendor PID namespace guards

这是 OnePlus 15 PLK110 / OP60FFL1、OxygenOS
`PLK110_16.0.9.400(CN01)` 的测试 boot 镜像。

## 实机结果

- Android 正常开机，Wi-Fi、蓝牙、LTE、音频、指纹和充电正常。
- Droidspaces v6.4.5 所有必需、推荐和可选内核检查通过。
- Ubuntu 24.04.4 LTS、systemd PID 1、NAT、DNS、HTTPS 和 Android 存储正常。
- 011 Midas guard 与 012 Secure Guard exec-kprobe guard 均已包含。
- 连续 5 次子 PID namespace 非主线程 exec 回归测试通过，没有重启、panic 或 Oops。

## 镜像

`boot-oneplus15-droidspaces-gki-r53-kabi-pointer-state-vendor-guards-e0a6769ae18f-stockcert-TEST.img`

SHA-256：

`7337a199f709720be7a82560c0bc7df8d5d41f59c4b528d155b65501f45db517`

内核版本：

`6.12.23-android16-5-gb2a876903b49-ab14541642-4k`

## 重要限制

- 这是 TEST / prerelease，不保证其他系统版本或其他 OnePlus 15 变体兼容。
- Docker 仍因 netfilter/cgroup 功能不完整而失败。
- X11、VirGL、PulseAudio 和完整 GPU 用户态依赖不随 boot 镜像提供。
- `CONFIG_KVM=y`，但当前系统没有 `/dev/kvm`。
- 只刷 `boot`，不要刷 `vendor_boot`、`init_boot`、`dtbo` 或 `vbmeta`。
- 必须保留自己的原版 boot 回滚镜像；原版 boot 不会发布。

下载后请使用随附的 `SHA256SUMS.txt` 校验。完整验证结果见仓库
[`validation/012/`](validation/012/)。
