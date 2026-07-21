#!/usr/bin/env bash
set -Eeuo pipefail

readonly ROOT=/root/oneplus15boot
readonly INPUT="$ROOT/inputs/droidspaces-kernel-audit"
readonly KERNEL_OUT="$ROOT/artifacts/gki-r53"
readonly FINAL="$ROOT/artifacts/final-gki-r53-stock-cert-test"
readonly KP="$ROOT/build/source/kernel_platform"
readonly COMMON="$KP/common"
readonly UNPACK="$KP/tools/mkbootimg/unpack_bootimg.py"
readonly MKBOOTIMG="$KP/tools/mkbootimg/mkbootimg.py"
readonly AVBTOOL="$KP/prebuilts/kernel-build-tools/linux-x86/bin/avbtool"
readonly EXPECTED_RELEASE=6.12.23-android16-5-gb2a876903b49-ab14541642-4k

mkdir -p "$FINAL"

grep -Fq "Linux version $EXPECTED_RELEASE " "$KERNEL_OUT/kernel-version.txt"
for symbol in SYSVIPC POSIX_MQUEUE IPC_NS PID_NS DEVTMPFS; do
    grep -qx "CONFIG_${symbol}=y" "$KERNEL_OUT/kernel.config"
done
grep -qx '# CONFIG_USER_NS is not set' "$KERNEL_OUT/kernel.config"
grep -qx 'CONFIG_MODULE_SIG_PROTECT=y' "$KERNEL_OUT/kernel.config"
grep -qx 'CONFIG_SYSTEM_TRUSTED_KEYS="certs/oneplus-stock-gki.pem"' \
    "$KERNEL_OUT/kernel.config"

image_id="$(sha256sum "$KERNEL_OUT/Image" | cut -c1-12)"
work="$ROOT/artifacts/boot-pack-gki-r53-$image_id"
boot_name="boot-oneplus15-droidspaces-gki-r53-${image_id}-stockcert-TEST.img"
boot_out="$FINAL/$boot_name"
mkdir -p "$work/stock" "$work/final"

python3 "$UNPACK" --boot_img "$INPUT/boot_a.img" --out "$work/stock" \
    --format=info > "$FINAL/stock-boot-info.txt"
cmp "$work/stock/kernel" "$ROOT/artifacts/boot-audit/original/kernel"

python3 "$MKBOOTIMG" \
    --header_version 4 \
    --kernel "$KERNEL_OUT/Image" \
    --ramdisk "$work/stock/ramdisk" \
    --cmdline '' \
    --output "$work/boot-unsigned.img"

# Preserve the stock OnePlus 16 KiB gap before its 96 MiB AVB footer layout.
raw_size="$(stat -c %s "$work/boot-unsigned.img")"
truncate -s "$((raw_size + 16384))" "$work/boot-unsigned.img"

"$AVBTOOL" add_hash_footer \
    --image "$work/boot-unsigned.img" \
    --partition_name boot \
    --partition_size 100663296 \
    --hash_algorithm sha256 \
    --salt 1318efeaaf87fd4e734d3d5c0ca04758 \
    --algorithm NONE \
    --rollback_index 0 \
    --prop 'com.android.build.boot.os_version:16' \
    --prop 'com.android.build.boot.fingerprint:qti/canoe/canoe:16/BP2A.250605.015/1782230840837:user/release-keys' \
    --prop 'com.android.build.boot.security_patch:2026-07-01'

cp "$work/boot-unsigned.img" "$boot_out"
test "$(stat -c %s "$boot_out")" -eq 100663296

python3 "$UNPACK" --boot_img "$boot_out" --out "$work/final" \
    --format=info > "$FINAL/test-boot-info.txt"
cmp "$work/final/kernel" "$KERNEL_OUT/Image"
cmp "$work/final/ramdisk" "$work/stock/ramdisk"

"$AVBTOOL" info_image --image "$boot_out" > "$FINAL/test-avb-info.txt"
cp "$boot_out" "$work/boot.img"
"$AVBTOOL" verify_image --image "$work/boot.img"

"$COMMON/scripts/extract-ikconfig" "$work/final/kernel" \
    > "$work/final/kernel.config"
cmp "$work/final/kernel.config" "$KERNEL_OUT/kernel.config"

cat > "$FINAL/TESTING.txt" <<EOF
TEST ONLY - OnePlus 15 PLK110 / OxygenOS PLK110_16.0.9.400(CN01)

Kernel release: $EXPECTED_RELEASE
Exact GKI source: b2a876903b495c444a94b16f50d1463ffe953957
Stock boot is not included. Keep the original boot_a.img available for rollback.

First test with temporary boot only when the device supports it:
  fastboot boot $boot_name

Do not use fastboot flash boot until Wi-Fi, Bluetooth, cellular, audio,
cameras, fingerprint, charging, suspend/resume and Droidspaces are verified.

The GKI ABI report contains only the intentional IPC namespace changes: two
new GPL exports and the Droidspaces SysV IPC task_struct union fields. This is
not a zero-difference stock ABI and remains a test kernel.

MODULE_SIG_PROTECT remains enabled. The public module-signing certificate from
the matching stock boot kernel is additionally embedded so the prebuilt
OnePlus system_dlkm/vendor_dlkm modules can still be authenticated.
EOF

cat > "$FINAL/测试说明.txt" <<EOF
一加 15 PLK110 / PLK110_16.0.9.400(CN01) 测试镜像

本镜像仍是测试版，不能保证一定开机。它只替换 boot；不会改写 init_boot、
vendor_boot、dtbo、vbmeta 或 TEE。SukiSU Ultra LKM 所在的 init_boot 保持不变。

修复点：
1. 使用与原厂 uname 完全匹配的 GKI r53 源码和 release 字符串。
2. 保留 CONFIG_MODULE_SIG_PROTECT，并把匹配原版 boot 内核中的公开模块签名
   证书加入信任链，以便认证原厂 system_dlkm/vendor_dlkm 模块。
3. 仅开启 Droidspaces 必需的 IPC/PID namespace、SysV IPC、POSIX mqueue 和
   devtmpfs；保留原厂 KVM/虚拟化配置。

推荐测试顺序：
1. 保留原版 boot_a.img，并确认能进入 bootloader/fastboot。
2. 若设备支持，优先临时启动：fastboot boot $boot_name
3. 开机后不要先启动 Droidspaces；先测试 Wi-Fi、蓝牙、移动数据、通话、音频、
   相机、指纹、充电和息屏唤醒。
4. 确认 uname -r 为：$EXPECTED_RELEASE
5. 再运行 /data/local/Droidspaces/bin/droidspaces check。
6. 首次启动容器时关闭 Android 存储、GPU/VirGL、Termux:X11、PulseAudio、
   硬件访问和容器网络；基础容器稳定后一次只启用一项。

若开机后 Wi-Fi/蓝牙仍立即不可用，不要启动 Droidspaces，直接回到 fastboot
刷回对应槽位的原版 boot，并收集 dmesg 中的 signature、protected symbol、
version magic、Unknown symbol、wlan、cnss、bluetooth 相关行。
EOF

cp "$KERNEL_OUT/kernel.config" "$FINAL/kernel.config"
cp "$KERNEL_OUT/kernel-version.txt" "$FINAL/kernel-version.txt"
cp "$KERNEL_OUT/config-diff-final/value-changes.txt" \
    "$FINAL/config-value-changes.txt"
cp "$KERNEL_OUT/source-changes.patch" "$FINAL/source-changes.patch"
cp "$KERNEL_OUT/stock-module-signing-certificate.txt" \
    "$FINAL/stock-module-signing-certificate.txt"
cp "$ROOT/GKI-R53-TEST-README.md" "$FINAL/README.md"
cp "$ROOT/logs/abi-gki-r53.log" "$FINAL/abi-check.log"
cp "$KP/bazel-bin/common/kernel_aarch64_abi_diff/git_message.txt" \
    "$FINAL/abi-diff-summary.txt"

(cd "$FINAL" && sha256sum "$boot_name" kernel.config kernel-version.txt \
    config-value-changes.txt source-changes.patch abi-check.log \
    abi-diff-summary.txt stock-module-signing-certificate.txt README.md TESTING.txt \
    测试说明.txt \
    > SHA256SUMS.txt)

find "$FINAL" -maxdepth 1 -type f -printf '%s %f\n' | sort -n
cat "$FINAL/SHA256SUMS.txt"
