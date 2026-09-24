#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
d="$root/driver/goodix51a0/goodix51a0.c"

grep -Fq '#define GX_TIMING_SCALE_MIN 100' "$d"
grep -Fq '#define GX_TIMING_SCALE_MAX 300' "$d"
grep -Fq '#define GX_TIMING_SCALE_STEP 50' "$d"
grep -Fq 'gx_protocol_timing_miss' "$d"
grep -Fq 'protocol timing auto-calibration: %d%% -> %d%%' "$d"
grep -Fq 'after %s miss; session-local only' "$d"
grep -Fq 'gx_protocol_timing_miss (self, "target-ack")' "$d"
grep -Fq 'gx_protocol_timing_miss (self, "tls-handshake")' "$d"
grep -Fq 'gx_protocol_timing_miss (self, stage)' "$d"

cold="$(sed -n '/^gx_cold_prepare (/,/^}/p' "$d")"
grep -Fq 'if (self->timing_scale < GX_TIMING_SCALE_MIN)' <<<"$cold"
grep -Fq 'self->timing_scale = GX_TIMING_SCALE_MIN;' <<<"$cold"

# Same-process cold recovery must preserve a calibrated value above nominal.
! grep -Eq '^[[:space:]]*self->timing_scale = GX_TIMING_SCALE_MIN;' <<<"$cold"

# rel43 must never restore disk timing persistence.
! grep -Fq 'GX_TIMING_FILE' "$d"
! grep -Fq 'gx_timing_load' "$d"
! grep -Fq 'gx_timing_save' "$d"
! grep -Fq 'timing_saved' "$d"
! grep -Fq '.goodix51a0-timing' "$d"
! grep -Fq '.goodix51a0-capture-timing' "$d"

echo 'test_session_local_timing_source_safety: OK (RAM auto-calibration)'
