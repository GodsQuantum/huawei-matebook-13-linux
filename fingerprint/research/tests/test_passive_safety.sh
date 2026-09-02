#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
GPIOD="$ROOT/linux/gpiod_irq.c"
PREFLIGHT="$ROOT/linux/passive_preflight.c"

for forbidden in \
    gpiod_line_settings_set_edge_detection \
    gpiod_line_settings_set_event_clock \
    gpiod_line_request_wait_edge_events \
    gpiod_line_request_read_edge_events \
    gpiod_line_request_set_value \
    gpiod_line_request_set_values \
    gpiod_line_settings_set_output_value; do
    if grep -q "$forbidden" "$GPIOD"; then
        echo "FAIL: passive GPIO adapter contains forbidden API: $forbidden" >&2
        exit 1
    fi
done

for forbidden in gxfp_spi_write_exact gxfp_spi_read_exact SPI_IOC_MESSAGE; do
    if grep -q "$forbidden" "$PREFLIGHT"; then
        echo "FAIL: passive preflight contains forbidden SPI transfer path: $forbidden" >&2
        exit 1
    fi
done

if ! grep -q 'GPIO264_REQUESTED=NO' "$PREFLIGHT"; then
    echo "FAIL: passive preflight does not explicitly report GPIO264 untouched" >&2
    exit 1
fi

echo "test_passive_safety: OK"
