#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=/root/oneplus15boot
SRC="$ROOT/build/source"
KP="$SRC/kernel_platform"
COMMON="$KP/common"
DIST="$KP/out/msm-kernel-canoe-perf/dist"
INPUT="$ROOT/inputs/droidspaces-kernel-audit"
ARTIFACT="$ROOT/github-ci/artifacts/kernel"
FINAL="$ROOT/artifacts/final"
UNPACK="$KP/tools/mkbootimg/unpack_bootimg.py"
MKBOOTIMG="$KP/tools/mkbootimg/mkbootimg.py"
AVBTOOL="$KP/prebuilts/kernel-build-tools/linux-x86/bin/avbtool"

mkdir -p "$ARTIFACT" "$FINAL"

echo '== finalize kernel artifacts =='
"$COMMON/scripts/extract-ikconfig" "$DIST/Image" > "$ARTIFACT/config"
for symbol in SYSVIPC POSIX_MQUEUE IPC_NS PID_NS DEVTMPFS VIRTUALIZATION KVM MODULE_SIG_ALL MODULE_SIG_PROTECT; do
    grep -qx "CONFIG_${symbol}=y" "$ARTIFACT/config"
done
grep -qx '# CONFIG_USER_NS is not set' "$ARTIFACT/config"

cp "$DIST/Image" "$ARTIFACT/Image"
for name in Image.lz4 Image.gz System.map Module.symvers vmlinux.symvers abi_symbollist; do
    [[ -f "$DIST/$name" ]] && cp "$DIST/$name" "$ARTIFACT/$name"
done

kernel_version="$({ strings "$ARTIFACT/Image" | grep -m1 '^Linux version 6\.12\.23-android16-5-'; } || true)"
test -n "$kernel_version"
printf '%s\n' "$kernel_version" > "$ARTIFACT/kernel-version.txt"

image_id="$(sha256sum "$ARTIFACT/Image" | cut -c1-8)"
work="$ROOT/artifacts/boot-pack-$image_id"
boot_name="boot-oneplus15-droidspaces-${image_id}-EXPERIMENTAL.img"
boot_out="$FINAL/$boot_name"
mkdir -p "$work/unpacked"

echo '== create boot v4 from final Image and stock structure =='
python3 "$MKBOOTIMG" \
    --header_version 4 \
    --kernel "$ARTIFACT/Image" \
    --ramdisk "$ROOT/artifacts/boot-audit/original/ramdisk" \
    --cmdline '' \
    --output "$work/boot-unsigned.img"

# OnePlus's stock and generated boot images both reserve an additional 16 KiB
# between the standard boot-v4 payload and the AVB footer. Preserve that exact
# layout before adding the new footer.
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

echo '== validate packaged boot =='
test "$(stat -c %s "$boot_out")" -eq 100663296
python3 "$UNPACK" --boot_img "$boot_out" --out "$work/unpacked" --format=info | tee "$FINAL/boot-info.txt"
cmp "$work/unpacked/kernel" "$ARTIFACT/Image"
test ! -s "$work/unpacked/ramdisk"
"$AVBTOOL" info_image --image "$boot_out" | tee "$FINAL/avb-info.txt"
cp "$boot_out" "$work/boot.img"
"$AVBTOOL" verify_image --image "$work/boot.img"
"$COMMON/scripts/extract-ikconfig" "$work/unpacked/kernel" > "$work/unpacked/config"
cmp "$work/unpacked/config" "$ARTIFACT/config"

cp "$INPUT/boot_a.img" "$FINAL/boot_a-stock-backup.img"
cp "$ROOT/scripts/EXPERIMENTAL-README.md" "$FINAL/README.md"
cp "$ROOT/artifacts/validation/config-diff/value-changes.txt" "$FINAL/config-value-changes.txt"
cp "$ARTIFACT/config" "$FINAL/kernel.config"
cp "$ARTIFACT/kernel-version.txt" "$FINAL/kernel-version.txt"

(cd "$FINAL" && sha256sum "$boot_name" boot_a-stock-backup.img kernel.config kernel-version.txt README.md config-value-changes.txt > SHA256SUMS.txt)
(cd "$ROOT/github-ci/artifacts" && sha256sum kernel/* > SHA256SUMS.txt)

echo '== final files =='
find "$FINAL" -maxdepth 1 -type f -printf '%s %f\n' | sort -n
cat "$FINAL/SHA256SUMS.txt"
