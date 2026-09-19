#!/usr/bin/env bash
set -euo pipefail
transport="$(cd "$(dirname "$0")/../.." && pwd)/driver/goodix51a0/gx51_transport.c"
fail_block="$(sed -n '/^fail:/,/^}/p' "$transport")"
grep -q 'val.bits = 0' <<<"$fail_block"
grep -q 'GPIO_V2_LINE_SET_VALUES_IOCTL' <<<"$fail_block"
echo 'test_driver_reset_low_source_safety: OK'
