#!/usr/bin/env bash
set -euo pipefail

ROOT=/root/oneplus15boot
SRC="$ROOT/build/source"
DIST="$SRC/kernel_platform/out/msm-kernel-canoe-perf/dist"
IMAGE="$DIST/Image"
OUT="$ROOT/artifacts/validation"
EXTRACT="$SRC/kernel_platform/common/scripts/extract-ikconfig"

mkdir -p "$OUT"

echo "== artifact identity =="
stat -c '%n %s bytes' "$IMAGE" "$DIST/.config" "$DIST/boot.img"
sha256sum "$IMAGE" "$DIST/.config" "$DIST/boot.img"
strings "$IMAGE" | grep -m1 -E '^Linux version 6\.12\.' || true

echo "== embedded kernel config =="
if "$EXTRACT" "$IMAGE" > "$OUT/Image.config"; then
    test -s "$OUT/Image.config"
    grep -E '^(CONFIG_(SYSVIPC|POSIX_MQUEUE|PID_NS|IPC_NS|DEVTMPFS|VIRTUALIZATION|KVM|MODULE_SIG_ALL|MODULE_SIG_PROTECT|MODULE_SIG_PROTECT_LIST)=|# CONFIG_(SYSVIPC|POSIX_MQUEUE|PID_NS|IPC_NS|DEVTMPFS|VIRTUALIZATION|KVM|MODULE_SIG_ALL|MODULE_SIG_PROTECT) is not set)' "$OUT/Image.config" || true
else
    echo "IKCONFIG extraction failed"
fi

echo "== dist config =="
grep -E '^(CONFIG_(SYSVIPC|POSIX_MQUEUE|PID_NS|IPC_NS|DEVTMPFS|VIRTUALIZATION|KVM|MODULE_SIG_ALL|MODULE_SIG_PROTECT|MODULE_SIG_PROTECT_LIST)=|# CONFIG_(SYSVIPC|POSIX_MQUEUE|PID_NS|IPC_NS|DEVTMPFS|VIRTUALIZATION|KVM|MODULE_SIG_ALL|MODULE_SIG_PROTECT) is not set)' "$DIST/.config" || true

echo "== staged pure GKI config =="
GKI_CFG="$ROOT/artifacts/logs/gki_config.expanded"
if [[ -f "$GKI_CFG" ]]; then
    sha256sum "$GKI_CFG"
    grep -E '^(CONFIG_(SYSVIPC|POSIX_MQUEUE|PID_NS|IPC_NS|DEVTMPFS|VIRTUALIZATION|KVM|MODULE_SIG_ALL|MODULE_SIG_PROTECT|MODULE_SIG_PROTECT_LIST)=|# CONFIG_(SYSVIPC|POSIX_MQUEUE|PID_NS|IPC_NS|DEVTMPFS|VIRTUALIZATION|KVM|MODULE_SIG_ALL|MODULE_SIG_PROTECT) is not set)' "$GKI_CFG" || true
fi

echo "== likely Image/config paths =="
find "$SRC/kernel_platform/out" -maxdepth 6 -type f \( -name Image -o -name '.config' \) -printf '%s %p\n' 2>/dev/null | sort -n | tail -n 30
