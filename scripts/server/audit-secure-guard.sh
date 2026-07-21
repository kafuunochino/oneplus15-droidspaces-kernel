#!/usr/bin/env bash
set -u

root=/root/oneplus15boot
module="$root/inputs/stock-modules/vendor_dlkm/oplus_secure_guard_new.ko"
objdump="$root/build/source/kernel_platform/prebuilts/clang/host/linux-x86/clang-r536225/bin/llvm-objdump"

echo '=== imports ==='
nm -u "$module" | grep -E '__tracepoint_android_|find_task_by_vpid|task|pid|exec' || true

echo '=== symbols ==='
nm -n "$module" | grep -E 'execve|exec|handler|find_task' || true

echo '=== find-task-callsite ==='
"$objdump" -dr "$module" |
    grep -B 60 -A 80 -E 'R_AARCH64_CALL26[[:space:]]+find_task_by_vpid' || true

echo '=== registration-callsite ==='
"$objdump" -dr "$module" |
    grep -B 40 -A 50 -E 'register_trace_android_.*exec|__tracepoint_android_.*exec' || true
