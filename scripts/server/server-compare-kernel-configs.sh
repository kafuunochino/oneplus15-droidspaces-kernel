#!/usr/bin/env bash
set -euo pipefail

ROOT=/root/oneplus15boot
STOCK_GZ="$ROOT/inputs/droidspaces-kernel-audit/config.gz"
BUILT="$ROOT/artifacts/validation/Image.config"
OUT="$ROOT/artifacts/validation/config-diff"

mkdir -p "$OUT"
gzip -dc "$STOCK_GZ" > "$OUT/stock.config"
cp "$BUILT" "$OUT/built.config"

grep -E '^(CONFIG_[A-Z0-9_]+=|# CONFIG_[A-Z0-9_]+ is not set$)' "$OUT/stock.config" | sort -u > "$OUT/stock.normalized"
grep -E '^(CONFIG_[A-Z0-9_]+=|# CONFIG_[A-Z0-9_]+ is not set$)' "$OUT/built.config" | sort -u > "$OUT/built.normalized"

comm -23 "$OUT/stock.normalized" "$OUT/built.normalized" > "$OUT/only-stock.txt"
comm -13 "$OUT/stock.normalized" "$OUT/built.normalized" > "$OUT/only-built.txt"
diff -u "$OUT/stock.normalized" "$OUT/built.normalized" > "$OUT/full.diff" || true

echo '== normalized config counts =='
wc -l "$OUT/stock.normalized" "$OUT/built.normalized" "$OUT/only-stock.txt" "$OUT/only-built.txt"

echo '== requested and safety settings =='
grep -E '^(CONFIG_(SYSVIPC|POSIX_MQUEUE|IPC_NS|PID_NS|DEVTMPFS|VIRTUALIZATION|KVM|MODULE_SIG_ALL|MODULE_SIG_PROTECT|MODULE_SIG_PROTECT_LIST)=|# CONFIG_(SYSVIPC|POSIX_MQUEUE|IPC_NS|PID_NS|DEVTMPFS|VIRTUALIZATION|KVM|MODULE_SIG_ALL|MODULE_SIG_PROTECT) is not set)' "$OUT/stock.config" || true
echo '-- built --'
grep -E '^(CONFIG_(SYSVIPC|POSIX_MQUEUE|IPC_NS|PID_NS|DEVTMPFS|VIRTUALIZATION|KVM|MODULE_SIG_ALL|MODULE_SIG_PROTECT|MODULE_SIG_PROTECT_LIST)=|# CONFIG_(SYSVIPC|POSIX_MQUEUE|IPC_NS|PID_NS|DEVTMPFS|VIRTUALIZATION|KVM|MODULE_SIG_ALL|MODULE_SIG_PROTECT) is not set)' "$OUT/built.config" || true

echo '== complete option-value changes =='
awk '
  function key(line, x) {
    x=line
    sub(/^# /, "", x)
    sub(/ is not set$/, "=n", x)
    sub(/=.*/, "", x)
    return x
  }
  NR==FNR { old[key($0)]=$0; next }
  { k=key($0); if (k in old && old[k] != $0) print old[k] "  ->  " $0 }
' "$OUT/stock.normalized" "$OUT/built.normalized" | tee "$OUT/value-changes.txt"

echo '== options unique to either tree (first 120 each) =='
echo '-- only stock --'
sed -n '1,120p' "$OUT/only-stock.txt"
echo '-- only built --'
sed -n '1,120p' "$OUT/only-built.txt"
