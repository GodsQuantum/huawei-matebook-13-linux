#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
driver="$root/driver/goodix51a0/goodix51a0.c"

block="$(sed -n '/^gx_prepare_capture_context (/,/^}/p' "$driver")"

grep -Fq 'previous_pacing_suppression = self->capture_pacing_suppressed;' <<<"$block"
grep -Fq 'self->capture_pacing_suppressed = TRUE;' <<<"$block"
grep -Fq 'self->capture_pacing_suppressed = previous_pacing_suppression;' <<<"$block"
grep -Fq 'gx_prepare_capture_context_once (self, FALSE)' <<<"$block"
grep -Fq 'gx_recover_capture_context (self)' <<<"$block"
grep -Fq 'goto out;' <<<"$block"

# Preparation must not rewrite the current adaptive scale. It only suppresses
# additional learning while background/TLS/FDT are being rebuilt.
! grep -Fq 'self->capture_gap_scale =' <<<"$block"

echo 'test_prepare_pacing_neutral_source_safety: OK'
