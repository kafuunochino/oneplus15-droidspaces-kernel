#!/usr/bin/env bash
set -Eeuo pipefail

readonly ROOT=/root/oneplus15boot
readonly WORKFLOW_ROOT="$ROOT/github-ci"
readonly LOG_DIR="$ROOT/logs"

install -d -m 700 "$ROOT/build" "$LOG_DIR"

export PATH="/root/bin:$PATH"
export GITHUB_WORKSPACE="$WORKFLOW_ROOT"
export BUILD_ROOT="$ROOT/build"
export GITHUB_RUN_NUMBER=1

exec > >(tee "$LOG_DIR/build-oneplus15.log") 2>&1

echo "Started: $(date --iso-8601=seconds)"
echo "Host: $(hostname)"
echo "CPUs: $(nproc)"
echo "Workspace: $GITHUB_WORKSPACE"
echo "Build root: $BUILD_ROOT"

cd "$WORKFLOW_ROOT"
bash scripts/build-oneplus15.sh

echo "Finished: $(date --iso-8601=seconds)"
