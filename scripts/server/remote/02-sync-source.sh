#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT=/root/oneplus15boot/source
LOG_ROOT=/root/oneplus15boot/logs
RESERVE_FILE=/root/oneplus15boot/.disk-reserve

mkdir -p "$SOURCE_ROOT" "$LOG_ROOT"
if [[ ! -e "$RESERVE_FILE" ]]; then
  fallocate -l 5G "$RESERVE_FILE"
fi
cd "$SOURCE_ROOT"

repo init \
  -u https://github.com/OnePlusOSS/kernel_manifest.git \
  -b oneplus/sm8850 \
  -m oneplus_15.xml \
  --depth=1 \
  --no-clone-bundle

repo sync \
  -c \
  -j"$(nproc)" \
  --no-tags \
  --no-clone-bundle \
  --optimized-fetch \
  --prune

repo manifest -r -o "$LOG_ROOT/pinned-manifest.xml"
repo status > "$LOG_ROOT/repo-status-before-changes.txt"

echo "Source synchronization complete: $SOURCE_ROOT"
