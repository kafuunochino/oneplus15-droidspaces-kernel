#!/usr/bin/env bash
set -Eeuo pipefail

readonly ROOT=/root/oneplus15boot
readonly SOURCE="$ROOT/build/source"
readonly DIST="$SOURCE/kernel_platform/out/msm-kernel-canoe-perf/dist"
readonly COMMON="$SOURCE/kernel_platform/common"
readonly DEVICE_KIT="$SOURCE/device/qcom/canoe-kernel"

required=(SYSVIPC POSIX_MQUEUE IPC_NS PID_NS DEVTMPFS VIRTUALIZATION KVM MODULE_SIG_ALL MODULE_SIG_PROTECT)

mkdir -p "$ROOT/artifacts/validation"
IMAGE_CONFIG="$ROOT/artifacts/validation/Image.config"
"$COMMON/scripts/extract-ikconfig" "$DIST/Image" > "$IMAGE_CONFIG"
test -s "$IMAGE_CONFIG"

echo '=== dist files ==='
find "$DIST" -maxdepth 2 -type f \
  \( -name Image -o -name boot.img -o -name init_boot.img -o -name vendor_boot.img \
     -o -name dtbo.img -o -name .config -o -name Module.symvers -o -name vmlinux.symvers \) \
  -printf '%s %p\n' | sort -n

echo '=== candidate configs ==='
candidates=(
  "$IMAGE_CONFIG"
  "$DIST/out_dir/.config"
  "$DEVICE_KIT/.config"
)
while IFS= read -r candidate; do
  candidates+=("$candidate")
done < <(find "$SOURCE/kernel_platform/out" -type f -name .config -print)

declare -A seen=()
for candidate in "${candidates[@]}"; do
  [[ -f "$candidate" ]] || continue
  real="$(readlink -f "$candidate")"
  [[ -z "${seen[$real]:-}" ]] || continue
  seen[$real]=1
  echo "--- $candidate"
  for symbol in "${required[@]}"; do
    grep -m1 -E "^(CONFIG_${symbol}=|# CONFIG_${symbol} is not set)" "$candidate" || \
      echo "CONFIG_${symbol}=<absent>"
  done
done

echo '=== exported IPC symbols ==='
for table in "$DIST/Module.symvers" "$DIST/vmlinux.symvers" "$DEVICE_KIT/Module.symvers"; do
  [[ -f "$table" ]] || continue
  echo "--- $table"
  grep -E '[[:space:]](init_ipc_ns|put_ipc_ns)[[:space:]]' "$table" || true
done

echo '=== source and output versions ==='
git -C "$COMMON" rev-parse HEAD
git -C "$COMMON" describe --always --dirty 2>/dev/null || true
strings "$DIST/Image" | grep -m1 'Linux version 6\.12\.23-android16-5-' || true

echo '=== stock security baseline differences ==='
baseline="$ROOT/github-ci/config/stock-kmi-security-baseline.config"
final_config="$IMAGE_CONFIG"
while IFS= read -r expected; do
  [[ -z "$expected" ]] && continue
  [[ "$expected" == \#* && "$expected" != "# CONFIG_"* ]] && continue
  if ! grep -Fqx -- "$expected" "$final_config"; then
    symbol="${expected#\# }"
    symbol="${symbol%%[= ]*}"
    echo "MISSING: $expected"
    grep -m1 -E "^${symbol}=|^# ${symbol} is not set" "$final_config" || \
      echo "ACTUAL: ${symbol}=<absent>"
  fi
done < "$baseline"

echo '=== artifact staging ==='
find "$ROOT/github-ci/artifacts" -maxdepth 3 -type f -printf '%s %p\n' | sort -n || true

echo '=== disk and cache ==='
du -sh "$SOURCE/kernel_platform/out" "$SOURCE/bazel-cache" "$SOURCE/.repo" 2>/dev/null || true
df -h "$ROOT"
