#!/bin/bash
set -euo pipefail

research_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
preflight="$research_dir/linux/pio_preflight.sh"

base_tmp=${TMPDIR:-/tmp}
case_dir="$base_tmp/gxfp-pio-preflight-test-$$"
trap 'rm -rf -- "$case_dir"' EXIT HUP INT TERM

make_case()
{
    local root=$1
    local controller="$root/platform/pxa2xx-spi.4"
    local drivers="$root/drivers"
    local target="$root/spi-GXFP51A0:00"

    mkdir -p \
        "$controller" \
        "$drivers/pxa2xx-spi" \
        "$root/platform/idma64.4" \
        "$root/platform/idma64.5" \
        "$root/spi-master/spi1" \
        "$target/statistics"

    ln -s "$drivers/pxa2xx-spi" "$controller/driver"
    ln -s "$controller" "$root/spi-master/spi1/device"

    : >"$target/driver_override"

    printf '0\n' >"$target/statistics/messages"
    printf '0\n' >"$target/statistics/transfers"
    printf '0\n' >"$target/statistics/bytes_tx"
    printf '0\n' >"$target/statistics/bytes_rx"

    printf '%s\n' \
        'quiet module_blacklist=idma64 modprobe.blacklist=idma64' \
        >"$root/cmdline"

    printf '%s\n' \
        'kernel: pxa2xx-spi pxa2xx-spi.4: no DMA channels available, using PIO' \
        >"$root/klog"
}

run_preflight()
{
    local root=$1

    GXFP_PIO_TEST_MODE=1 \
    GXFP_PIO_TEST_CMDLINE="$root/cmdline" \
    GXFP_PIO_TEST_IDMA_MODULE="$root/module/idma64" \
    GXFP_PIO_TEST_PLATFORM_ROOT="$root/platform" \
    GXFP_PIO_TEST_SPI_MASTER_DEVICE="$root/spi-master/spi1/device" \
    GXFP_PIO_TEST_TARGET="$root/spi-GXFP51A0:00" \
    GXFP_PIO_TEST_KLOG="$root/klog" \
    "$preflight"
}

mkdir -p "$case_dir"

root="$case_dir/pass"
make_case "$root"
run_preflight "$root" >"$root/out"
grep -Fxq 'PIO_PREFLIGHT=PASS' "$root/out"
grep -Fxq 'IDMA64_MODULE=ABSENT' "$root/out"
grep -Fxq 'IDMA64_BOUND_DEVICE_COUNT=0' "$root/out"
grep -Fxq 'PXA2XX_PIO_FALLBACK=CONFIRMED' "$root/out"

root="$case_dir/module_present"
make_case "$root"
mkdir -p "$root/module/idma64"
set +e
run_preflight "$root" >"$root/out" 2>&1
rc=$?
set -e
test "$rc" -ne 0
grep -Fq 'ABORT=IDMA64_MODULE_PRESENT' "$root/out"

root="$case_dir/idma_bound"
make_case "$root"
mkdir -p "$root/drivers/idma64"
ln -s "$root/drivers/idma64" "$root/platform/idma64.4/driver"
set +e
run_preflight "$root" >"$root/out" 2>&1
rc=$?
set -e
test "$rc" -ne 0
grep -Fq 'ABORT=IDMA64_PLATFORM_DEVICE_BOUND' "$root/out"

root="$case_dir/no_blacklist"
make_case "$root"
printf '%s\n' 'quiet splash' >"$root/cmdline"
set +e
run_preflight "$root" >"$root/out" 2>&1
rc=$?
set -e
test "$rc" -ne 0
grep -Fq 'ABORT=IDMA64_BOOT_BLACKLIST_NOT_PROVEN' "$root/out"

root="$case_dir/no_fallback"
make_case "$root"
: >"$root/klog"
set +e
run_preflight "$root" >"$root/out" 2>&1
rc=$?
set -e
test "$rc" -ne 0
grep -Fq 'ABORT=PXA2XX_PIO_FALLBACK_NOT_PROVEN' "$root/out"

root="$case_dir/activity"
make_case "$root"
printf '1\n' >"$root/spi-GXFP51A0:00/statistics/messages"
set +e
run_preflight "$root" >"$root/out" 2>&1
rc=$?
set -e
test "$rc" -ne 0
grep -Fq 'ABORT=TARGET_SPI_ACTIVITY_ALREADY_PRESENT' "$root/out"

echo 'test_pio_preflight: OK'
