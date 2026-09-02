#!/bin/bash
set -euo pipefail

TEST_MODE=${GXFP_PIO_TEST_MODE:-0}

if [ "$TEST_MODE" = 1 ]; then
    CMDLINE=${GXFP_PIO_TEST_CMDLINE:?}
    IDMA_MODULE=${GXFP_PIO_TEST_IDMA_MODULE:?}
    PLATFORM_ROOT=${GXFP_PIO_TEST_PLATFORM_ROOT:?}
    SPI_MASTER_DEVICE=${GXFP_PIO_TEST_SPI_MASTER_DEVICE:?}
    TARGET=${GXFP_PIO_TEST_TARGET:?}
    KLOG=${GXFP_PIO_TEST_KLOG:?}
else
    CMDLINE=/proc/cmdline
    IDMA_MODULE=/sys/module/idma64
    PLATFORM_ROOT=/sys/bus/platform/devices
    SPI_MASTER_DEVICE=/sys/class/spi_master/spi1/device
    TARGET=/sys/bus/spi/devices/spi-GXFP51A0:00

    if [ "${EUID:-$(id -u)}" -ne 0 ]; then
        echo 'ABORT=PIO_PREFLIGHT_REQUIRES_ROOT' >&2
        exit 66
    fi

    KLOG=$(mktemp)
    trap 'rm -f -- "$KLOG"' EXIT HUP INT TERM
    journalctl -k -b --no-pager >"$KLOG"
fi

abort()
{
    echo "ABORT=$1" >&2
    exit "${2:-70}"
}

[ -r "$CMDLINE" ] ||
    abort 'CMDLINE_UNREADABLE' 70

cmdline=$(cat -- "$CMDLINE")

case " $cmdline " in
    *" module_blacklist=idma64 "*|*" module_blacklist="*idma64*|\
    *" modprobe.blacklist=idma64 "*|*" modprobe.blacklist="*idma64*)
        ;;
    *)
        abort 'IDMA64_BOOT_BLACKLIST_NOT_PROVEN' 71
        ;;
esac

if [ -e "$IDMA_MODULE" ]; then
    abort 'IDMA64_MODULE_PRESENT' 72
fi

[ -d "$PLATFORM_ROOT" ] ||
    abort 'PLATFORM_ROOT_MISSING' 73

idma_count=0
idma_bound=0

for dev in "$PLATFORM_ROOT"/idma64.*; do
    [ -e "$dev" ] || continue
    idma_count=$((idma_count + 1))

    if [ -L "$dev/driver" ] || [ -e "$dev/driver" ]; then
        idma_bound=$((idma_bound + 1))
    fi
done

[ "$idma_count" -gt 0 ] ||
    abort 'IDMA64_PLATFORM_DEVICES_MISSING' 74

[ "$idma_bound" -eq 0 ] ||
    abort 'IDMA64_PLATFORM_DEVICE_BOUND' 75

[ -e "$SPI_MASTER_DEVICE" ] ||
    abort 'SPI_MASTER_DEVICE_MISSING' 76

controller=$(readlink -f -- "$SPI_MASTER_DEVICE")
[ -n "$controller" ] &&
[ -d "$controller" ] ||
    abort 'PXA2XX_CONTROLLER_RESOLUTION_FAILED' 77

controller_name=$(basename -- "$controller")

[ -L "$controller/driver" ] ||
    abort 'PXA2XX_CONTROLLER_UNBOUND' 78

controller_driver=$(basename -- "$(readlink -f -- "$controller/driver")")

[ "$controller_driver" = 'pxa2xx-spi' ] ||
    abort 'UNEXPECTED_SPI_CONTROLLER_DRIVER' 79

grep -F "$controller_name" "$KLOG" |
    grep -Fq 'no DMA channels available, using PIO' ||
    abort 'PXA2XX_PIO_FALLBACK_NOT_PROVEN' 80

[ -d "$TARGET" ] ||
    abort 'GXFP_TARGET_MISSING' 81

if [ -e "$TARGET/driver" ]; then
    abort 'GXFP_TARGET_ALREADY_BOUND' 82
fi

override=$(cat -- "$TARGET/driver_override" 2>/dev/null || true)

[ -z "$override" ] ||
    abort 'GXFP_DRIVER_OVERRIDE_NOT_EMPTY' 83

for stat in messages transfers bytes_tx bytes_rx; do
    file="$TARGET/statistics/$stat"

    [ -r "$file" ] ||
        abort "TARGET_SPI_STAT_MISSING:$stat" 84

    value=$(cat -- "$file")

    [ "$value" = 0 ] ||
        abort "TARGET_SPI_ACTIVITY_ALREADY_PRESENT:$stat=$value" 85
done

echo "PIO_CONTROLLER=$controller_name"
echo "PIO_CONTROLLER_DRIVER=$controller_driver"
echo "IDMA64_PLATFORM_DEVICE_COUNT=$idma_count"
echo 'IDMA64_BOUND_DEVICE_COUNT=0'
echo 'IDMA64_MODULE=ABSENT'
echo 'IDMA64_BOOT_BLACKLIST=CONFIRMED'
echo 'PXA2XX_PIO_FALLBACK=CONFIRMED'
echo 'TARGET_SPI_ACTIVITY=ZERO'
echo 'PIO_PREFLIGHT=PASS'
