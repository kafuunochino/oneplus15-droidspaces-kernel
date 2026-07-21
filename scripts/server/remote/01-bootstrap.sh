#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run this script as root." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y \
  bc bison build-essential ca-certificates ccache cpio curl dwarves flex \
  device-tree-compiler g++-multilib gcc-multilib git git-lfs gnupg gperf imagemagick \
  lib32readline-dev lib32z1-dev libdw-dev libelf-dev \
  libncurses-dev libssl-dev libxml2-utils lz4 make patch python3 \
  python-is-python3 rsync schedtool unzip xz-utils zip zlib1g-dev zstd ninja-build

curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo \
  -o /usr/local/bin/repo
chmod 0755 /usr/local/bin/repo

install -d -m 0755 \
  /root/oneplus15boot/source \
  /root/oneplus15boot/cache \
  /root/oneplus15boot/logs \
  /root/oneplus15boot/outputs \
  /root/oneplus15boot/scripts \
  /root/oneplus15boot/patches

git lfs install --system
repo version
echo "Bootstrap complete. Source root: /root/oneplus15boot/source"
