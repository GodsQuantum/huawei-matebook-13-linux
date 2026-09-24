#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
d="$root/driver/goodix51a0/goodix51a0.c"

grep -Fq '#define GX_TIMING_SCALE_MIN 100' "$d"
grep -Fq '#define GX_TIMING_SCALE_MAX 300' "$d"
grep -Fq '#define GX_TIMING_SCALE_STEP 50' "$d"
grep -Fq 'self->timing_scale = GX_TIMING_SCALE_MIN;' "$d"
grep -Fq 'session protocol timing settled at %d%%; not persisted' "$d"

! grep -Fq 'GX_TIMING_FILE' "$d"
! grep -Fq 'gx_timing_load' "$d"
! grep -Fq 'gx_timing_save' "$d"
! grep -Fq 'timing_saved' "$d"
! grep -Fq '.goodix51a0-timing' "$d"
! grep -Fq '.goodix51a0-capture-timing' "$d"

echo 'test_session_local_timing_source_safety: OK'
