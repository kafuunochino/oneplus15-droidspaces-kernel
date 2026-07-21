#!/usr/bin/env bash
set -Eeuo pipefail

readonly ROOT=/root/oneplus15boot
readonly INPUT="$ROOT/inputs/droidspaces-kernel-audit"
readonly VARIANT="${VARIANT:-kabi-pointer-state}"
readonly FLAVOR="${FLAVOR:-gki-r53-kabi-pointer-state}"
readonly FINAL_NAME="${FINAL_NAME:-final-gki-r53-kabi-pointer-state-test}"
readonly MIDAS_GUARD="${MIDAS_GUARD:-0}"
readonly KERNEL_OUT="$ROOT/artifacts/gki-r53-$VARIANT"
readonly BASE_OUT="$ROOT/artifacts/gki-r53-kabi-split"
readonly FINAL="$ROOT/artifacts/$FINAL_NAME"
readonly KP="$ROOT/build/source/kernel_platform"
readonly COMMON="$KP/common"
readonly UNPACK="$KP/tools/mkbootimg/unpack_bootimg.py"
readonly MKBOOTIMG="$KP/tools/mkbootimg/mkbootimg.py"
readonly AVBTOOL="$KP/prebuilts/kernel-build-tools/linux-x86/bin/avbtool"
readonly EXPECTED_RELEASE=6.12.23-android16-5-gb2a876903b49-ab14541642-4k
readonly STOCK_CERT_SHA256=F28DBCC60085B21A3CFF1342482897FA640B468847473147834F26C4FEB2DF43

mkdir -p "$FINAL"

grep -Fq "Linux version $EXPECTED_RELEASE " "$KERNEL_OUT/kernel-release.txt"
for symbol in SYSVIPC POSIX_MQUEUE IPC_NS PID_NS DEVTMPFS; do
	grep -qx "CONFIG_${symbol}=y" "$KERNEL_OUT/kernel.config"
done
grep -qx '# CONFIG_USER_NS is not set' "$KERNEL_OUT/kernel.config"
grep -qx 'CONFIG_MODULE_SIG_PROTECT=y' "$KERNEL_OUT/kernel.config"
grep -qx 'CONFIG_SYSTEM_TRUSTED_KEYS="certs/oneplus-stock-gki.pem"' "$KERNEL_OUT/kernel.config"

cert_sha256="$(openssl x509 -inform DER -in "$KERNEL_OUT/stock-module-signing.der" -noout -fingerprint -sha256 | sed 's/^.*=//; s/://g')"
test "$cert_sha256" = "$STOCK_CERT_SHA256"
openssl x509 -inform DER -in "$KERNEL_OUT/stock-module-signing.der" \
	-noout -subject -issuer -serial -fingerprint -sha256 \
	> "$FINAL/stock-module-signing-certificate.txt"

grep -qx 'base_task_struct_size=5184' "$KERNEL_OUT/abi-comparison.txt"
grep -qx 'new_task_struct_size=5184' "$KERNEL_OUT/abi-comparison.txt"
grep -qx 'top_level_layout_changes=0' "$KERNEL_OUT/abi-comparison.txt"
grep -qx 'crc_changes_non_rust=0' "$KERNEL_OUT/abi-comparison.txt"
grep -q '^\[pointer\]$' "$KERNEL_OUT/stock-module-crc-comparison.txt"
test "$(grep -c '^MISMATCH pointer ' "$KERNEL_OUT/stock-module-crc-comparison.txt")" -eq 4
if grep '^MISMATCH pointer ' "$KERNEL_OUT/stock-module-crc-comparison.txt" | grep -qv 'system_dlkm/rust_binder\.ko _R'; then
	echo 'A non-Rust or unexpected stock-module CRC mismatch was found' >&2
	exit 1
fi
cmp "$BASE_OUT/dist/abi_symbollist" "$KERNEL_OUT/dist/abi_symbollist"

pahole -C task_struct "$KERNEL_OUT/dist/vmlinux" > "$FINAL/task-struct-layout.txt"
python3 - "$FINAL/task-struct-layout.txt" <<'PY'
import pathlib
import re
import sys

text = pathlib.Path(sys.argv[1]).read_text()
required = {
    "sysvsem reserve slot 1": r"struct sysv_sem\s+sysvsem;\s+/\*\s+3424\s+8\s+\*/",
    "sysvshm pointer reserve slot 2": r"struct sysv_shm\s+\*\s*sysvshm;\s+/\*\s+3432\s+8\s+\*/",
    "untouched reserve slot 3": r"__kabi_reserved3;\s+/\*\s+3440\s+8\s+\*/",
    "sched_entity unchanged": r"struct sched_entity\s+se;\s+/\*\s+192\s+320\s+\*/",
    "task_struct size unchanged": r"/\* size: 5184,",
}
for label, pattern in required.items():
    if not re.search(pattern, text):
        raise SystemExit(f"layout validation failed: {label}")
    print(f"Verified: {label}")
PY

image="$KERNEL_OUT/dist/Image"
image_id="$(sha256sum "$image" | cut -c1-12)"
work="$ROOT/artifacts/boot-pack-$FLAVOR-$image_id"
boot_name="boot-oneplus15-droidspaces-${FLAVOR}-${image_id}-stockcert-TEST.img"
boot_out="$FINAL/$boot_name"
mkdir -p "$work/stock" "$work/final"

python3 "$UNPACK" --boot_img "$INPUT/boot_a.img" --out "$work/stock" \
	--format=info > "$FINAL/stock-boot-info.txt"
cmp "$work/stock/kernel" "$ROOT/artifacts/boot-audit/original/kernel"

python3 "$MKBOOTIMG" \
	--header_version 4 \
	--kernel "$image" \
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
cmp "$work/final/kernel" "$image"
cmp "$work/final/ramdisk" "$work/stock/ramdisk"

"$AVBTOOL" info_image --image "$boot_out" > "$FINAL/test-avb-info.txt"
cp "$boot_out" "$work/boot.img"
"$AVBTOOL" verify_image --image "$work/boot.img"

"$COMMON/scripts/extract-ikconfig" "$work/final/kernel" > "$work/final/kernel.config"
cmp "$work/final/kernel.config" "$KERNEL_OUT/kernel.config"

cp "$KERNEL_OUT/kernel.config" "$FINAL/kernel.config"
cp "$KERNEL_OUT/kernel-release.txt" "$FINAL/kernel-release.txt"
cp "$KERNEL_OUT/source-changes.patch" "$FINAL/source-changes.patch"
cp "$KERNEL_OUT/abi-comparison.txt" "$FINAL/abi-comparison.txt"
cp "$KERNEL_OUT/stock-module-crc-comparison.txt" "$FINAL/stock-module-crc-comparison.txt"

if [[ "$MIDAS_GUARD" == 1 ]]; then
	grep -q 'task_is_in_init_pid_ns(p)' "$KERNEL_OUT/source-changes.patch"
	grep -q 'OnePlus Midas consumer' "$KERNEL_OUT/source-changes.patch"
	test -s "$KERNEL_OUT/cpufreq_acct_update_power.disassembly.txt"
	grep -q 'task_active_pid_ns' "$KERNEL_OUT/cpufreq_acct_update_power.disassembly.txt"
	grep -q '__traceiter_android_vh_cpufreq_acct_update_power' \
		"$KERNEL_OUT/cpufreq_acct_update_power.disassembly.txt"
	cp "$KERNEL_OUT/cpufreq_acct_update_power.disassembly.txt" \
		"$FINAL/cpufreq-acct-midas-guard.disassembly.txt"
	midas_note='- Child PID namespace tasks skip the incompatible OnePlus Midas cpufreq vendor hook; Android tasks are unchanged.'
else
	midas_note='- No child-PID-namespace guard is included in this build.'
fi

cat > "$FINAL/TESTING.txt" <<EOF
TEST ONLY - OnePlus 15 PLK110 / OxygenOS PLK110_16.0.9.400(CN01)

Kernel release: $EXPECTED_RELEASE
Kernel Image SHA-256: $(sha256sum "$image" | cut -d' ' -f1)
SysV task fields: official Android kABI reserve slots at offsets 3424-3447.
Slot 1 stores sysv_sem. Slot 2 stores a pointer to a separately allocated,
native sysv_shm list head. Slot 3 remains an untouched vendor reserve.

Validated before packaging:
- task_struct size remains 5184 bytes.
- 211 common top-level task_struct fields have zero offset changes.
- 8901 common exports have zero non-Rust CRC changes versus the split baseline.
- All changed export CRCs are Rust-only; zero non-Rust changes were found.
- 539 stock modules have zero non-Rust mismatches versus the split baseline.
- The only four stock-module mismatches are in unused system_dlkm/rust_binder.ko.
$midas_note

This remains a diagnostic TEST image. Boot success and offline ABI checks do not
prove that starting a Droidspaces container cannot trigger a reboot. Keep the
stock boot image and fastboot rollback command ready.
EOF

hash_files=(
	"$boot_name"
	kernel.config
	kernel-release.txt
	source-changes.patch
	abi-comparison.txt
	stock-module-crc-comparison.txt
	stock-module-signing-certificate.txt
	TESTING.txt
	task-struct-layout.txt
	test-avb-info.txt
)
if [[ "$MIDAS_GUARD" == 1 ]]; then
	hash_files+=(cpufreq-acct-midas-guard.disassembly.txt)
fi
(cd "$FINAL" && sha256sum "${hash_files[@]}" > SHA256SUMS.txt)

find "$FINAL" -maxdepth 1 -type f -printf '%s %f\n' | sort -n
cat "$FINAL/SHA256SUMS.txt"
