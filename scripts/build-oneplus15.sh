#!/usr/bin/env bash
set -Eeuo pipefail

readonly WORKFLOW_ROOT="${GITHUB_WORKSPACE:?GITHUB_WORKSPACE is required}"
readonly BUILD_ROOT="${BUILD_ROOT:-/mnt/oneplus15-build}"
readonly SOURCE_ROOT="$BUILD_ROOT/source"
readonly LOG_ROOT="$WORKFLOW_ROOT/artifacts/logs"
readonly ARTIFACT_ROOT="$WORKFLOW_ROOT/artifacts/kernel"
readonly MANIFEST_URL="https://github.com/OnePlusOSS/kernel_manifest.git"
readonly MANIFEST_BRANCH="oneplus/sm8850"
readonly MANIFEST_FILE="oneplus_15.xml"
readonly CI_LOCAL_MANIFEST="$WORKFLOW_ROOT/manifest/ci-remove-unavailable-test-prebuilts.xml"
readonly COMMON="$SOURCE_ROOT/kernel_platform/common"
readonly DEFCONFIG="$COMMON/arch/arm64/configs/gki_defconfig"
readonly KERNEL_PLATFORM="$SOURCE_ROOT/kernel_platform"
readonly CONFIG_PATCH="$WORKFLOW_ROOT/patches/002.oneplus15-gki-droidspaces-config.patch"
readonly IPC_EXPORT_PATCH="$WORKFLOW_ROOT/patches/003.export-ipc-namespace-symbols-for-rust-binder.patch"
readonly DIST="$SOURCE_ROOT/kernel_platform/out/msm-kernel-canoe-perf/dist"
readonly SECURITY_BASELINE="$WORKFLOW_ROOT/config/stock-kmi-security-baseline.config"
readonly EXPECTED_RELEASE_PREFIX="6.12.23-android16-5-"

apply_patch_once() {
  local repository="$1"
  local patch_file="$2"

  if git -C "$repository" apply --check "$patch_file"; then
    git -C "$repository" apply "$patch_file"
    echo "Applied patch: $(basename "$patch_file")"
  elif git -C "$repository" apply --reverse --check "$patch_file"; then
    echo "Patch already applied: $(basename "$patch_file")"
  else
    echo "Patch conflicts with the current source tree: $patch_file" >&2
    exit 1
  fi
}

mkdir -p "$SOURCE_ROOT" "$LOG_ROOT" "$ARTIFACT_ROOT"

echo "Build root: $BUILD_ROOT"
echo "Parallel jobs: $(nproc)"
df -h "$WORKFLOW_ROOT" "$BUILD_ROOT" || true

cd "$SOURCE_ROOT"
repo init \
  -u "$MANIFEST_URL" \
  -b "$MANIFEST_BRANCH" \
  -m "$MANIFEST_FILE" \
  --depth=1 \
  --partial-clone \
  --clone-filter=blob:limit=10M \
  --no-clone-bundle

mkdir -p .repo/local_manifests
cp "$CI_LOCAL_MANIFEST" .repo/local_manifests/ci-fixes.xml

sync_ok=0
for attempt in 1 2 3; do
  echo "repo sync attempt $attempt"
  if repo sync -c -j"$(nproc)" --no-tags --no-clone-bundle --optimized-fetch --prune; then
    sync_ok=1
    break
  fi
  repo sync -l -j1 || true
done
if [[ "$sync_ok" -ne 1 ]]; then
  echo "repo sync failed after three attempts" >&2
  exit 1
fi

repo manifest -r -o "$LOG_ROOT/pinned-manifest.xml"
repo status > "$LOG_ROOT/repo-status-before-changes.txt"
df -h "$BUILD_ROOT"

apply_patch_once \
  "$COMMON" \
  "$WORKFLOW_ROOT/patches/001.GKI-6.12-or-above-fix_sysvipc_kabi.patch"
apply_patch_once "$COMMON" "$CONFIG_PATCH"
apply_patch_once "$COMMON" "$IPC_EXPORT_PATCH"

required=(SYSVIPC POSIX_MQUEUE IPC_NS PID_NS DEVTMPFS VIRTUALIZATION KVM)

# Generate and validate the expanded config through Kleaf's hermetic
# Clang/Rust environment. The source patch is already in savedefconfig order,
# so Kleaf's strict check also guards against applying it to a changed tree.
cd "$KERNEL_PLATFORM"
tools/bazel build //common:kernel_aarch64_config
readonly CONFIG_OUT_FILE="$(find -L bazel-bin/common/kernel_aarch64_config -type f -name .config -print -quit)"
if [[ -z "$CONFIG_OUT_FILE" ]]; then
  echo "Kleaf did not expose the generated GKI .config" >&2
  find -L bazel-bin/common/kernel_aarch64_config -maxdepth 5 -type f -print || true
  exit 1
fi

while IFS= read -r line; do
  [[ "$line" =~ ^CONFIG_([A-Z0-9_]+)=y$ ]] || continue
  grep -qx "$line" "$CONFIG_OUT_FILE" || \
    echo "Optional CONFIG_${BASH_REMATCH[1]} is unavailable or constrained by this kernel tree"
done < "$WORKFLOW_ROOT/config/droidspaces-gki.config"

for symbol in "${required[@]}"; do
  grep -qx "CONFIG_${symbol}=y" "$CONFIG_OUT_FILE" || {
    echo "Required CONFIG_${symbol} could not be enabled" >&2
    exit 1
  }
done
grep -qx '# CONFIG_USER_NS is not set' "$CONFIG_OUT_FILE" || {
  echo "CONFIG_USER_NS must remain disabled to preserve stock hardening" >&2
  exit 1
}

git -C "$COMMON" diff --check
git -C "$COMMON" diff > "$LOG_ROOT/kernel-source-changes.patch"
cp "$DEFCONFIG" "$LOG_ROOT/gki_defconfig.modified"
cp "$CONFIG_OUT_FILE" "$LOG_ROOT/gki_config.expanded"

for symbol in "${required[@]}"; do
  grep -qx "CONFIG_${symbol}=y" "$CONFIG_OUT_FILE" || {
    echo "Required CONFIG_${symbol} was not enabled" >&2
    exit 1
  }
done
export MAKEFLAGS="-j$(nproc)"
export LLVM_PARALLEL_LINK_JOBS="$(nproc)"
export KBUILD_BUILD_USER="github-actions"
export KBUILD_BUILD_HOST="oneplus15-droidspaces"
export BUILD_NUMBER="${GITHUB_RUN_NUMBER:-1}"

cd "$SOURCE_ROOT"
bash -o pipefail ./kernel_platform/oplus/build/oplus_build_kernel.sh canoe perf

if [[ ! -f "$DIST/Image" ]]; then
  echo "Expected kernel image not found: $DIST/Image" >&2
  find "$SOURCE_ROOT/kernel_platform/out" -maxdepth 6 -type f \
    \( -name Image -o -name 'Image.*' -o -name boot.img \) -print || true
  exit 1
fi

cp "$DIST/Image" "$ARTIFACT_ROOT/Image"
for name in Image.lz4 Image.gz System.map Module.symvers vmlinux.symvers abi_symbollist; do
  [[ -f "$DIST/$name" ]] && cp "$DIST/$name" "$ARTIFACT_ROOT/$name"
done

readonly BUILT_CONFIG="$ARTIFACT_ROOT/config"
if ! "$COMMON/scripts/extract-ikconfig" "$DIST/Image" > "$BUILT_CONFIG"; then
  echo "Unable to extract the configuration embedded in the final Image" >&2
  exit 1
fi
if [[ ! -s "$BUILT_CONFIG" ]]; then
  echo "The final Image does not contain a readable embedded configuration" >&2
  exit 1
fi
for symbol in "${required[@]}"; do
  grep -qx "CONFIG_${symbol}=y" "$BUILT_CONFIG" || {
    echo "Final CONFIG_${symbol} check failed" >&2
    exit 1
  }
done
grep -qx '# CONFIG_USER_NS is not set' "$BUILT_CONFIG" || {
  echo "Final Image unexpectedly enables CONFIG_USER_NS" >&2
  exit 1
}

while IFS= read -r expected; do
  [[ -z "$expected" ]] && continue
  [[ "$expected" == \#* && "$expected" != "# CONFIG_"* ]] && continue
  grep -Fqx -- "$expected" "$BUILT_CONFIG" || {
    echo "Stock KMI/security baseline changed or missing: $expected" >&2
    exit 1
  }
done < "$SECURITY_BASELINE"
cp "$SECURITY_BASELINE" "$ARTIFACT_ROOT/stock-kmi-security-baseline.config"

kernel_version="$({ strings "$ARTIFACT_ROOT/Image" | grep -m1 'Linux version 6\.12\.23-android16-5-'; } || true)"
if [[ "$kernel_version" != *"Linux version ${EXPECTED_RELEASE_PREFIX}"* ]]; then
  echo "Unexpected kernel/KMI release string: ${kernel_version:-not found}" >&2
  exit 1
fi
printf '%s\n' "$kernel_version" > "$ARTIFACT_ROOT/kernel-version.txt"
(cd "$WORKFLOW_ROOT/artifacts" && sha256sum kernel/* > SHA256SUMS.txt)
df -h "$BUILD_ROOT"
