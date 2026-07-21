#!/usr/bin/env bash
set -euo pipefail

ROOT=/root/oneplus15boot
SRC="$ROOT/build/source"
ORIGINAL="$ROOT/inputs/droidspaces-kernel-audit/boot_a.img"
GENERATED="$SRC/kernel_platform/out/msm-kernel-canoe-perf/dist/boot.img"
UNPACK="$SRC/kernel_platform/tools/mkbootimg/unpack_bootimg.py"
OUT="$ROOT/artifacts/boot-audit"

mkdir -p "$OUT/original" "$OUT/generated"

for pair in "original:$ORIGINAL" "generated:$GENERATED"; do
    label="${pair%%:*}"
    image="${pair#*:}"
    target="$OUT/$label"

    echo "== $label =="
    stat -c '%n %s bytes' "$image"
    sha256sum "$image"
    python3 "$UNPACK" --boot_img "$image" --out "$target" --format=info | tee "$target/info.txt"
    python3 "$UNPACK" --boot_img "$image" --out "$target" --format=mkbootimg > "$target/mkbootimg-args.txt"
    find "$target" -maxdepth 1 -type f -printf '%s %f\n' | sort -n
    find "$target" -maxdepth 1 -type f ! -name 'info.txt' ! -name 'mkbootimg-args.txt' -exec sha256sum {} + | sort -k2
done

echo '== component comparison =='
for component in kernel ramdisk second dtb recovery_dtbo boot_signature; do
    if [[ -f "$OUT/original/$component" && -f "$OUT/generated/$component" ]]; then
        printf '%s: ' "$component"
        if cmp -s "$OUT/original/$component" "$OUT/generated/$component"; then
            echo identical
        else
            echo different
        fi
    fi
done

echo '== AVB tools and metadata =='
AVBTOOL="$(find "$SRC" -type f \( -name avbtool -o -name avbtool.py \) -print -quit 2>/dev/null || true)"
echo "avbtool=${AVBTOOL:-not-found}"
if [[ -n "$AVBTOOL" ]]; then
    for pair in "original:$ORIGINAL" "generated:$GENERATED"; do
        label="${pair%%:*}"
        image="${pair#*:}"
        echo "--- $label"
        python3 "$AVBTOOL" info_image --image "$image" || true
    done
fi
