#!/usr/bin/env bash
set -Eeuo pipefail

readonly ROOT=/root/oneplus15boot
readonly INPUT="$ROOT/inputs/droidspaces-kernel-audit"
readonly KERNEL_OUT="$ROOT/artifacts/gki-r53-aligned"
readonly PACKED_OUT="$ROOT/artifacts/gki-r53"
readonly FINAL="$ROOT/artifacts/final-gki-r53-aligned-test"
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

# The C/vendor-facing exported ABI must remain unchanged. Rust exports encode
# generated bindgen layout details in their CRCs, so record those separately
# and reject any changed non-Rust symbol.
python3 - \
    "$PACKED_OUT/dist/kernel_aarch64_Module.symvers" \
    "$KERNEL_OUT/dist/kernel_aarch64_Module.symvers" \
    "$FINAL/rust-symbol-crc-diff.txt" <<'PY'
import pathlib
import sys

def read_symvers(path):
    result = {}
    for line in pathlib.Path(path).read_text().splitlines():
        fields = line.split("\t")
        if len(fields) >= 2:
            result[fields[1]] = fields[0]
    return result

old = read_symvers(sys.argv[1])
new = read_symvers(sys.argv[2])
changed = []
for symbol in sorted(set(old) | set(new)):
    if old.get(symbol) != new.get(symbol):
        changed.append((symbol, old.get(symbol, "<missing>"),
                        new.get(symbol, "<missing>")))

unsafe = [item for item in changed if not item[0].startswith("_R")]
if unsafe:
    for item in unsafe:
        print("Unexpected non-Rust CRC change:", *item)
    raise SystemExit("non-Rust Module.symvers changed")

lines = [
    "Only Rust-mangled export CRCs changed between packed and aligned builds.",
    "No C/vendor-facing Module.symvers entry changed.",
    f"Changed Rust exports: {len(changed)}",
    "",
]
lines += [f"{symbol}\t{before}\t{after}"
          for symbol, before, after in changed]
pathlib.Path(sys.argv[3]).write_text("\n".join(lines) + "\n")
print(f"Verified: {len(changed)} Rust CRC changes, 0 non-Rust CRC changes")
PY
cmp "$PACKED_OUT/dist/abi_symbollist" "$KERNEL_OUT/dist/abi_symbollist"

pahole -C task_struct "$KERNEL_OUT/dist/vmlinux" \
    > "$FINAL/task-struct-layout.txt"
python3 - "$FINAL/task-struct-layout.txt" <<'PY'
import pathlib
import re
import sys

text = pathlib.Path(sys.argv[1]).read_text()
required = {
    "sysvsem aligned at 168": r"struct sysv_sem\s+sysvsem;\s+/\*\s+168\s+8\s+\*/",
    "sysvshm aligned at 176": r"struct sysv_shm\s+sysvshm;\s+/\*\s+176\s+16\s+\*/",
    "sched_entity unchanged at 192": r"struct sched_entity\s+se;\s+/\*\s+192\s+320\s+\*/",
    "task_struct size unchanged": r"/\* size: 5184,",
}
for label, pattern in required.items():
    if not re.search(pattern, text):
        raise SystemExit(f"layout validation failed: {label}")
    print(f"Verified: {label}")
PY

image_id="$(sha256sum "$KERNEL_OUT/Image" | cut -c1-12)"
work="$ROOT/artifacts/boot-pack-gki-r53-aligned-$image_id"
boot_name="boot-oneplus15-droidspaces-gki-r53-aligned-${image_id}-stockcert-TEST.img"
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

cp "$KERNEL_OUT/kernel.config" "$FINAL/kernel.config"
cp "$KERNEL_OUT/kernel-version.txt" "$FINAL/kernel-version.txt"
cp "$KERNEL_OUT/config-diff-final/value-changes.txt" \
    "$FINAL/config-value-changes.txt"
cp "$KERNEL_OUT/source-changes.patch" "$FINAL/source-changes.patch"
cp "$KERNEL_OUT/stock-module-signing-certificate.txt" \
    "$FINAL/stock-module-signing-certificate.txt"
cp "$ROOT/logs/abi-gki-r53-aligned.log" "$FINAL/abi-check.log"
cp "$KP/bazel-bin/common/kernel_aarch64_abi_diff/git_message.txt" \
    "$FINAL/abi-diff-summary.txt"
cp "$ROOT/GKI-R53-ALIGNED-TEST-README.md" "$FINAL/README.md"

cat > "$FINAL/TESTING.txt" <<EOF
TEST ONLY - OnePlus 15 PLK110 / OxygenOS PLK110_16.0.9.400(CN01)

Kernel release: $EXPECTED_RELEASE
Image SHA-256: $(sha256sum "$KERNEL_OUT/Image" | cut -d' ' -f1)
SysV task fields: naturally aligned at 168 and 176; sched_entity remains 192.

This candidate is intended to diagnose the hard reboot during the first
container fork after the rootfs image is mounted. It is not proven safe.
Do not flash or start Droidspaces without an explicit test plan and a stock
boot image ready for rollback.
EOF

(cd "$FINAL" && sha256sum "$boot_name" kernel.config kernel-version.txt \
    config-value-changes.txt source-changes.patch abi-check.log \
    abi-diff-summary.txt stock-module-signing-certificate.txt README.md \
    TESTING.txt task-struct-layout.txt test-avb-info.txt \
    rust-symbol-crc-diff.txt \
    > SHA256SUMS.txt)

find "$FINAL" -maxdepth 1 -type f -printf '%s %f\n' | sort -n
cat "$FINAL/SHA256SUMS.txt"
