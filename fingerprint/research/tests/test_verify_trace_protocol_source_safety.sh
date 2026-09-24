#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
driver="$root/driver/goodix51a0/goodix51a0.c"
tool="$root/tools/gxfp51a0-verify-diagnostic.py"

for marker in 'READY' 'DETECTED_HOLD' 'LIFT_NOW' 'RELEASED'; do
  grep -Fq "GXFP51A0 %s_TRACE physical press %d/%d $marker" "$driver"
done
grep -Fq 't->identifying ? "IDENTIFY" : "VERIFY"' "$driver"
grep -Fq 'GXFP51A0 AUTH_TRACE mode=%s same-press image %u/%u ' "$driver"
grep -Fq 'GXFP51A0 AUTH_TRACE mode=%s same-press completed ' "$driver"

grep -Fq 'TRACE_READY_RE' "$tool"
grep -Fq '(?:VERIFY|IDENTIFY)_TRACE physical press' "$tool"
grep -Fq 'AUTH_TRACE mode=(?:verify|identify) same-press image' "$tool"
grep -Fq 'TRACE_SCORE_RE' "$tool"
grep -Fq 'TRACE_LIFT_RE' "$tool"
! grep -Fq 'get_finger_state' "$tool"
! grep -Fq 'busctl' "$tool"
echo 'test_verify_trace_protocol_source_safety: OK (Verify + Identify)'
