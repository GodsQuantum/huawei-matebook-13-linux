#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
d="$root/driver/goodix51a0/goodix51a0.c"

grep -Fq 'gboolean press_retry_seen = FALSE;' "$d"
grep -Fq 'press_retry_seen = press_retry_seen || self->capture_retry_seen;' "$d"
grep -Fq 'self->capture_retry_seen = press_retry_seen;' "$d"
grep -Fq 'protocol_floor =' "$d"
grep -Fq 'self->timing_scale - GX_CAPTURE_SCALE_STEP' "$d"
grep -Fq 'MAX (previous + GX_CAPTURE_SCALE_STEP, protocol_floor)' "$d"
grep -Fq 'session capture pacing calibrated by retry-assisted' "$d"
grep -Fq 'not persisted' "$d"
! grep -Fq 'GX_CAPTURE_RETRY_ESCALATE_STREAK' "$d"
! grep -Fq '.goodix51a0-capture-timing' "$d"
echo 'test_retry_assisted_capture_calibration_source_safety: OK'
