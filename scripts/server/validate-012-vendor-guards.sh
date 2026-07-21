#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "Validation failed at line $LINENO: $BASH_COMMAND" >&2' ERR

root=/root/oneplus15boot
old="$root/artifacts/gki-r53-kabi-pointer-state-midas-guard"
new="$root/artifacts/gki-r53-kabi-pointer-state-vendor-guards"
common="$root/build/source/kernel_platform/common"
objdump="$root/build/source/kernel_platform/prebuilts/clang/host/linux-x86/clang-r536225/bin/llvm-objdump"
secure_guard="$root/inputs/stock-modules/vendor_dlkm/oplus_secure_guard_new.ko"
report="$new/kprobe-child-pidns-guard.disassembly.txt"
evidence="$new/oplus-secure-guard-null-deref-evidence.txt"
cpufreq_report="$new/cpufreq_acct_update_power.disassembly.txt"

for file in kernel.config kernel-release.txt; do
    cmp "$old/$file" "$new/$file"
done
for file in abi_symbollist vmlinux.symvers; do
    cmp "$old/dist/$file" "$new/dist/$file"
done

grep -qx 'CONFIG_KPROBES=y' "$new/kernel.config"
grep -qx 'CONFIG_KRETPROBES=y' "$new/kernel.config"
if grep -qx 'CONFIG_KPROBES_ON_FTRACE=y' "$new/kernel.config"; then
    echo 'Unexpected CONFIG_KPROBES_ON_FTRACE=y' >&2
    exit 1
fi
grep -q 'kprobe_skip_handlers_in_child_pidns' "$new/source-changes.patch"
grep -q 'do_execveat_common' "$new/source-changes.patch"
grep -q 'task_is_in_init_pid_ns(current)' "$new/source-changes.patch"
grep -q 'task_is_in_init_pid_ns(p)' "$new/source-changes.patch"

nm -n "$new/dist/vmlinux" > "$new/vmlinux-symbols.txt"

disassemble_range() {
    local symbol="$1"
    local size="$2"
    local start stop
    start=$(awk -v symbol="$symbol" '$3 == symbol { print "0x" $1; exit }' \
        "$new/vmlinux-symbols.txt")
    test -n "$start"
    stop=$(python3 -c "print(hex(int('$start', 16) + $size))")
    "$objdump" -d --start-address="$start" --stop-address="$stop" \
        "$new/dist/vmlinux"
}

: > "$report"
for symbol in \
    kprobe_skip_handlers_in_child_pidns \
    kprobe_breakpoint_handler \
    kprobe_breakpoint_ss_handler; do
    disassemble_range "$symbol" 1024 >> "$report"
done

grep -q '<kprobe_skip_handlers_in_child_pidns>:' "$report"
grep -q 'task_active_pid_ns' "$report"
grep -q ' D init_pid_ns$' "$new/vmlinux-symbols.txt"
test "$(grep -c 'kprobe_skip_handlers_in_child_pidns' "$report")" -ge 3

disassemble_range cpufreq_acct_update_power 768 > "$cpufreq_report"
grep -q 'task_active_pid_ns' "$cpufreq_report"
grep -q '__traceiter_android_vh_cpufreq_acct_update_power' "$cpufreq_report"

"$objdump" -dr "$secure_guard" |
    grep -B 24 -A 18 -E 'R_AARCH64_CALL26[[:space:]]+find_task_by_vpid' > "$evidence"
grep -q '<do_execveat_common_entry_handler' "$evidence"
grep -q 'R_AARCH64_CALL26[[:space:]]*find_task_by_vpid' "$evidence"
grep -q 'add[[:space:]]*x0, x0, #0x40' "$evidence"

echo 'Verified: 012 kernel config and release are byte-identical to 011'
echo 'Verified: abi_symbollist and vmlinux.symvers are byte-identical to 011'
echo 'Verified: Midas guard remains present'
echo 'Verified: child-PID-namespace exec kprobe pre/post guard is present in machine code'
echo 'Verified: closed-source Secure Guard evidence shows unchecked NULL + 0x40 path'
