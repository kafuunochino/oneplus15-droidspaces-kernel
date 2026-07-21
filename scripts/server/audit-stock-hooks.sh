#!/usr/bin/env bash
set -u

root=/root/oneplus15boot
modules="$root/inputs/stock-modules"

echo '=== midas-hooks ==='
nm -u "$modules/vendor_dlkm/oplus_bsp_midas.ko" 2>/dev/null |
    grep -E '__tracepoint_android_|task|pid' || true

echo '=== zram-opt-hooks ==='
nm -u "$modules/vendor_dlkm/oplus_bsp_zram_opt.ko" 2>/dev/null |
    grep -E '__tracepoint_android_|task|pid|zram|hybrid' || true

echo '=== zram-opt-strings ==='
strings "$modules/vendor_dlkm/oplus_bsp_zram_opt.ko" |
    grep -E -i 'hybridswap|lru_del|invalid|trace_android|register_trace' || true

echo '=== all-taskish-hook-imports ==='
for module in "$modules"/*/*.ko; do
    nm -u "$module" 2>/dev/null |
        grep -E '__tracepoint_android_(v|r)h_.*(task|sched|fork|exit|exec|clone|pid|uid|cpu|freq|oom|binder|signal|mm)' |
        sed "s#^#$module #" || true
done | sort -u

echo '=== pid-lookup-importers ==='
for module in "$modules"/*/*.ko; do
    symbols=$(nm -u "$module" 2>/dev/null |
        grep -E '(^|[[:space:]])(find_task_by_vpid|find_get_task_by_vpid|find_task_by_pid_ns|pid_task|task_active_pid_ns|task_tgid_vnr|task_pid_vnr)$' || true)
    if [[ -n "$symbols" ]]; then
        echo "[$module]"
        printf '%s\n' "$symbols"
        nm -u "$module" 2>/dev/null | grep -E '__tracepoint_android_' || true
    fi
done
