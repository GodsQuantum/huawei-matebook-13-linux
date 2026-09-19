#!/usr/bin/env bash
set -euo pipefail
driver="$(cd "$(dirname "$0")/../.." && pwd)/driver/goodix51a0/goodix51a0.c"
grep -q '^gx_target_read_response ' "$driver"
helper="$(sed -n '/^gx_target_read_response (/,/^}/p' "$driver")"
grep -q 'g_usleep (8000' <<<"$helper"
for stage in soft-reset-1 chip-id otp soft-reset-2 idle dac-main dac1 dac2 dac3 config-response; do
  grep -Fq "target init failed: $stage" "$driver"
done
for stage in otp-ack otp-response-read otp-response-parse otp-validation; do
  grep -Fq "target init failed: $stage" "$driver"
done
grep -Fq 'GXFP_DIAGNOSTIC_ONESHOT' "$driver"
grep -Fq 'GX_TLS_OK' "$driver"
grep -Fq 'TLS established ACK D4' "$driver"
echo 'test_target_response_timing_source_safety: OK'
