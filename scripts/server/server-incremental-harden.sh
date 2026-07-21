#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=/root/oneplus15boot
SRC="$ROOT/build/source"
KP="$SRC/kernel_platform"
COMMON="$KP/common"
CACHE="$SRC/bazel-cache"
DIST="$KP/out/msm-kernel-canoe-perf/dist"
PATCH="$ROOT/scripts/current-disable-userns.patch"
LOG="$ROOT/logs/incremental-harden.log"
ARTIFACT="$ROOT/github-ci/artifacts/kernel"

exec > >(tee "$LOG") 2>&1

echo '== apply stock-hardening adjustment =='
DEFCONFIG="$COMMON/arch/arm64/configs/gki_defconfig"
if grep -qx 'CONFIG_PID_NS=y' "$DEFCONFIG"; then
    # Normalize the interrupted prior attempt. PID_NS defaults to y, so this
    # explicit line must be absent for Kleaf's savedefconfig check.
    sed -i '/^CONFIG_PID_NS=y$/d' "$DEFCONFIG"
elif git -C "$COMMON" apply --check "$PATCH"; then
    git -C "$COMMON" apply "$PATCH"
elif git -C "$COMMON" apply --reverse --check "$PATCH"; then
    echo 'Adjustment already applied'
else
    echo 'Unable to apply USER_NS hardening adjustment cleanly' >&2
    exit 1
fi

cd "$KP"
BAZEL_START=(
  tools/bazel
  "--output_user_root=$CACHE"
)
BAZEL_FLAGS=(
  --//soc-repo:skip_abl=true
  --incompatible_sandbox_hermetic_tmp=false
  --noenable_workspace
  "--override_module=rules_kotlin=%workspace%/build/kernel/kleaf/bzlmod/fake_modules/rules_kotlin"
  "--override_module=protobuf=%workspace%/build/kernel/kleaf/bzlmod/fake_modules/protobuf"
  "--override_module=rules_java=%workspace%/build/kernel/kleaf/bzlmod/fake_modules/rules_java"
)

echo '== validate expanded GKI config =='
"${BAZEL_START[@]}" build "${BAZEL_FLAGS[@]}" //common:kernel_aarch64_config
CONFIG_OUT="$(find -L bazel-bin/common/kernel_aarch64_config -type f -name .config -print -quit)"
test -n "$CONFIG_OUT"
for symbol in SYSVIPC POSIX_MQUEUE IPC_NS PID_NS DEVTMPFS VIRTUALIZATION KVM MODULE_SIG_ALL MODULE_SIG_PROTECT; do
    grep -qx "CONFIG_${symbol}=y" "$CONFIG_OUT"
done
grep -qx '# CONFIG_USER_NS is not set' "$CONFIG_OUT"

echo '== incremental kernel and boot build =='
"${BAZEL_START[@]}" build "${BAZEL_FLAGS[@]}" //soc-repo:canoe_perf_dist
"${BAZEL_START[@]}" run "${BAZEL_FLAGS[@]}" //soc-repo:canoe_perf_dist -- --dist_dir "$DIST"

echo '== validate final Image =='
mkdir -p "$ARTIFACT"
"$COMMON/scripts/extract-ikconfig" "$DIST/Image" > "$ARTIFACT/config"
for symbol in SYSVIPC POSIX_MQUEUE IPC_NS PID_NS DEVTMPFS VIRTUALIZATION KVM MODULE_SIG_ALL MODULE_SIG_PROTECT; do
    grep -qx "CONFIG_${symbol}=y" "$ARTIFACT/config"
done
grep -qx '# CONFIG_USER_NS is not set' "$ARTIFACT/config"

cp "$DIST/Image" "$ARTIFACT/Image"
for name in Image.lz4 Image.gz System.map Module.symvers vmlinux.symvers abi_symbollist; do
    [[ -f "$DIST/$name" ]] && cp "$DIST/$name" "$ARTIFACT/$name"
done

kernel_version="$({ strings "$ARTIFACT/Image" | grep -m1 '^Linux version 6\.12\.23-android16-5-'; } || true)"
if [[ -z "$kernel_version" ]]; then
    echo 'Expected kernel release string was not found in the final Image' >&2
    exit 1
fi
printf '%s\n' "$kernel_version" > "$ARTIFACT/kernel-version.txt"
(cd "$ROOT/github-ci/artifacts" && sha256sum kernel/* > SHA256SUMS.txt)

echo '== completed =='
cat "$ARTIFACT/kernel-version.txt"
sha256sum "$ARTIFACT/Image" "$ARTIFACT/config"
