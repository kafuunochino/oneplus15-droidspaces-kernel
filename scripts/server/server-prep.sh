#!/usr/bin/env bash
set -Eeuo pipefail

readonly ROOT=/root/oneplus15boot
readonly SWAP_FILE="$ROOT/build.swap"

install -d -m 700 "$ROOT"

if [[ ! -f "$SWAP_FILE" ]]; then
  fallocate -l 16G "$SWAP_FILE"
  chmod 600 "$SWAP_FILE"
fi
if ! blkid -p -s TYPE -o value "$SWAP_FILE" 2>/dev/null | grep -qx swap; then
  mkswap "$SWAP_FILE"
fi
if ! swapon --show=NAME --noheadings | tr -d ' ' | grep -Fxq "$SWAP_FILE"; then
  swapon "$SWAP_FILE"
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y \
  bc bison build-essential ca-certificates cpio curl flex git git-lfs \
  libelf-dev libssl-dev lz4 python3 rsync unzip zip zstd

install -d -m 755 /root/bin
curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo \
  -o /root/bin/repo
chmod 0755 /root/bin/repo

/root/bin/repo version
swapon --show
free -h
df -h "$ROOT"
