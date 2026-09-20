#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
d="$root/driver/goodix51a0/goodix51a0.c"
grep -Fq '#define GX_SEQ_GAP_US 30000' "$d"
count=$(grep -Fc 'g_usleep (GX_SEQ_GAP_US);' "$d")
[[ "$count" -eq 2 ]]
! grep -Fq 'GX_SEQ_GAP_US * self->timing_scale' "$d"
grep -Fq 'The learned timing scale belongs to target/TLS recovery' "$d"
echo 'test_capture_gap_nominal_source_safety: OK'
