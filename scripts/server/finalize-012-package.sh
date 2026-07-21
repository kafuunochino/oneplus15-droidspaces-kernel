#!/usr/bin/env bash
set -Eeuo pipefail

root=/root/oneplus15boot
new="$root/artifacts/gki-r53-kabi-pointer-state-vendor-guards"
final="$root/artifacts/final-gki-r53-kabi-pointer-state-vendor-guards-test"

cp "$new/kprobe-child-pidns-guard.disassembly.txt" "$final/"
cp "$new/oplus-secure-guard-null-deref-evidence.txt" "$final/"

cat >> "$final/TESTING.txt" <<'EOF'

Additional 012 child-PID-namespace guard:
- Static analysis of stock oplus_secure_guard_new.ko found an unchecked
  find_task_by_vpid() result in do_execveat_common_entry_handler.  A
  non-leader exec from a child PID namespace can produce NULL, followed by
  pointer arithmetic at offset 0x40.
- For child-PID-namespace tasks only, kprobe pre/post handlers at the exact
  do_execveat_common target are skipped while the original instruction still
  executes through the normal arm64 single-step path.
- Android initial-PID-namespace tasks and every other kprobe target are
  unchanged.
EOF

(
    cd "$final"
    find . -maxdepth 1 -type f ! -name SHA256SUMS.txt -printf '%f\n' |
        sort |
        xargs sha256sum > SHA256SUMS.txt
)

sha256sum "$final"/boot-*.img
cat "$final/SHA256SUMS.txt"
