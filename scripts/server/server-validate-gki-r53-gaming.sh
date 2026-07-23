#!/usr/bin/env bash
# Validate kABI and stock-module compatibility for the gaming test kernel.
set -Eeuo pipefail

readonly ROOT=/root/oneplus15boot
readonly BASE="$ROOT/artifacts/gki-r53-kabi-split"
readonly NEW_VARIANT="${NEW_VARIANT:-kabi-pointer-state-gaming-userns-ntsync}"
readonly NEW="$ROOT/artifacts/gki-r53-$NEW_VARIANT"
readonly ABI_VALIDATOR="$ROOT/scripts/validate-gki-r53-kabi-reserve.py"
readonly MODULE_VALIDATOR="$ROOT/scripts/validate-stock-module-crcs.py"
readonly STOCK_MODULES="$ROOT/inputs/stock-modules"

for path in \
	"$BASE/dist/vmlinux" \
	"$BASE/dist/vmlinux.symvers" \
	"$BASE/dist/abi_symbollist" \
	"$NEW/dist/vmlinux" \
	"$NEW/dist/vmlinux.symvers" \
	"$NEW/dist/abi_symbollist"; do
	test -s "$path"
done

python3 "$ABI_VALIDATOR" \
	"$BASE/dist/vmlinux" \
	"$NEW/dist/vmlinux" \
	"$BASE/dist/vmlinux.symvers" \
	"$NEW/dist/vmlinux.symvers" \
	| tee "$NEW/abi-comparison.txt"

cmp "$BASE/dist/abi_symbollist" "$NEW/dist/abi_symbollist"
grep -qx 'top_level_layout_changes=0' "$NEW/abi-comparison.txt"
grep -qx 'crc_changes_non_rust=0' "$NEW/abi-comparison.txt"

set +e
python3 "$MODULE_VALIDATOR" "$STOCK_MODULES" \
	pointer="$NEW/dist/vmlinux.symvers" \
	split="$BASE/dist/vmlinux.symvers" \
	> "$NEW/stock-module-crc-comparison.txt"
module_status=$?
set -e

# The validator returns 1 for the four known Rust Binder mismatches. Validate
# that there are no additional or changed mismatches in the new candidate.
test "$module_status" -eq 1

python3 - "$NEW/stock-module-crc-comparison.txt" <<'PY'
import pathlib
import re
import sys

text = pathlib.Path(sys.argv[1]).read_text()

def section(name: str) -> str:
    match = re.search(rf"^\[{re.escape(name)}\]\n(.*?)(?=^\[|\Z)", text, re.M | re.S)
    if not match:
        raise SystemExit(f"missing CRC section: {name}")
    return match.group(1)

def counter(body: str, key: str) -> int:
    match = re.search(rf"^{re.escape(key)}=(\d+)$", body, re.M)
    if not match:
        raise SystemExit(f"missing counter {key}")
    return int(match.group(1))

pointer = section("pointer")
split = section("split")
if counter(pointer, "mismatched") != 4:
    raise SystemExit("expected exactly four known Rust Binder mismatches")
if counter(pointer, "modules_with_mismatch") != 1:
    raise SystemExit("expected mismatches in exactly one module")
if counter(pointer, "matched") != counter(split, "matched") - 1:
    raise SystemExit("expected exactly one fewer matched Rust Binder symbol")
if counter(pointer, "missing_from_gki") != counter(split, "missing_from_gki") + 1:
    raise SystemExit("expected exactly one additional missing Rust Binder symbol")

lines = [line for line in pointer.splitlines() if line.startswith("MISMATCH pointer ")]
if len(lines) != 4:
    raise SystemExit("unexpected mismatch-line count")
for line in lines:
    parts = line.split()
    if len(parts) < 5 or parts[2] != "system_dlkm/rust_binder.ko" or not parts[3].startswith("_R"):
        raise SystemExit(f"unexpected stock-module mismatch: {line}")

print("Verified: all shared non-Rust export CRCs match the split baseline")
print("Verified: only four known unused rust_binder.ko mismatches remain")
PY

# CONFIG_USER_NS removes this conditional Rust helper export. The only stock
# module which requires it is the already-unusable, unused rust_binder.ko.
grep -q '[[:space:]]rust_helper_from_kuid[[:space:]]' \
        "$BASE/dist/vmlinux.symvers"
if grep -q '[[:space:]]rust_helper_from_kuid[[:space:]]' \
        "$NEW/dist/vmlinux.symvers"; then
        echo 'Unexpected rust_helper_from_kuid export in USER_NS build' >&2
        exit 1
fi
modprobe --dump-modversions \
        "$STOCK_MODULES/system_dlkm/rust_binder.ko" |
        grep '[[:space:]]rust_helper_from_kuid$' >/dev/null

pahole -C task_struct "$NEW/dist/vmlinux" > "$NEW/task_struct.full-layout.txt"
grep -Eq 'struct sysv_sem[[:space:]]+sysvsem;[[:space:]]+/\*[[:space:]]+3424[[:space:]]+8[[:space:]]+\*/' "$NEW/task_struct.full-layout.txt"
grep -Eq 'struct sysv_shm[[:space:]]+\*[[:space:]]*sysvshm;[[:space:]]+/\*[[:space:]]+3432[[:space:]]+8[[:space:]]+\*/' "$NEW/task_struct.full-layout.txt"
grep -Eq '__kabi_reserved2;[[:space:]]+/\*[[:space:]]+3432[[:space:]]+8[[:space:]]+\*/' "$NEW/task_struct.full-layout.txt"
grep -Eq '__kabi_reserved3;[[:space:]]+/\*[[:space:]]+3440[[:space:]]+8[[:space:]]+\*/' "$NEW/task_struct.full-layout.txt"
grep -Eq '/\* size: 5184,' "$NEW/task_struct.full-layout.txt"

for symbol in SYSVIPC POSIX_MQUEUE IPC_NS PID_NS USER_NS DEVTMPFS NTSYNC; do
	grep -qx "CONFIG_${symbol}=y" "$NEW/kernel.config"
done

echo 'Verified: USER_NS removes only rust_helper_from_kuid required by unused rust_binder.ko'
echo 'All gaming USER_NS/NTSYNC pointer-state offline ABI gates passed.'
