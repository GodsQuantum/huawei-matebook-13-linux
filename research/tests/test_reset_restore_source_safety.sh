#!/bin/sh
set -eu

research_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
restore="$research_dir/linux/reset_restore.c"

# Separate fail-safe helper may only touch the already-configured GPIO264 value.
grep -q 'gxfp_gpiod_reset_open_as_is' "$restore"
grep -q 'gxfp_probe_restore_reset' "$restore"
grep -q 'gxfp_gpiod_reset_get_level' "$restore"
grep -q 'GPIO264_RESTORE_AFTER=%d' "$restore"

if grep -Eqi 'linux_spi|spidev|SPI_IOC|GXFP51A0|A4|DriverState|UPFW|firmware|erase|bootloader' "$restore"; then
    echo 'safety violation: external reset helper contains protocol/SPI functionality' >&2
    exit 1
fi

echo 'test_reset_restore_source_safety: OK'
