#!/usr/bin/env bash
set -euo pipefail

RUNTIME_SRC="${1:-linux/active_runtime.c}"
RUNTIME_HDR="${2:-linux/active_runtime.h}"
BACKEND_SRC="${3:-linux/active_backend.c}"
BACKEND_HDR="${4:-linux/active_backend.h}"

for f in "$RUNTIME_SRC" "$RUNTIME_HDR" "$BACKEND_SRC" "$BACKEND_HDR"; do
    test -f "$f"
done

grep -q 'gxfp_gpiod_irq_get_value' "$RUNTIME_SRC"
grep -q 'CLOCK_MONOTONIC' "$RUNTIME_SRC"
grep -q 'nanosleep' "$RUNTIME_SRC"
grep -q 'GXFP_IRQ_POLL_SLICE_MS 5u' "$BACKEND_SRC"
grep -q 'get_value' "$BACKEND_HDR"

if grep -Eqi 'EDGE_|wait_edge|read_edge|wait_rising|consume_event|GPIO264|GPIOD_LINE_DIRECTION_OUTPUT|gpiod_line_request_set_value|gpiod_line_request_set_values|gpiod_line_settings_set_edge_detection' \
    "$RUNTIME_SRC" "$RUNTIME_HDR" "$BACKEND_SRC" "$BACKEND_HDR"; then
    echo 'forbidden edge/output/reset primitive in active backend/runtime' >&2
    exit 1
fi

echo 'test_active_runtime_source_safety: OK'
