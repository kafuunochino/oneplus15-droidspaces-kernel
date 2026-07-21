#!/usr/bin/env bash
set -u

modules=/root/oneplus15boot/inputs/stock-modules/vendor_dlkm
objdump=/root/oneplus15boot/build/source/kernel_platform/prebuilts/clang/host/linux-x86/clang-r536225/bin/llvm-objdump
targets=(
    oplus_bsp_midas.ko
    oplus_bsp_sched_ext.ko
    oplus_bsp_schedinfo.ko
    oplus_bsp_game_opt.ko
    oplus_bsp_waker_identify.ko
    oplus_locking_strategy.ko
    oplus_binder_strategy.ko
    oplus_sys_hans.ko
    oplus_sys_stability_helper.ko
    cpu_mpam.ko
)

for name in "${targets[@]}"; do
    module="$modules/$name"
    echo "=== $name ==="
    "$objdump" -dr "$module" 2>/dev/null |
        grep -B 18 -A 18 -E '<find_task_by_vpid>|R_AARCH64_CALL26[[:space:]]+find_task_by_vpid' || true
done
