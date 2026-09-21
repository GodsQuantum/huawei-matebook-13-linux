#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
d="$root/driver/goodix51a0/goodix51a0.c"

grep -Fq '#define GX_SEQ_GAP_US 30000' "$d"
grep -Fq '#define GX_CAPTURE_SCALE_MIN 100' "$d"
grep -Fq '#define GX_CAPTURE_SCALE_MAX 300' "$d"
grep -Fq '#define GX_CAPTURE_SCALE_STEP 50' "$d"
grep -Fq 'g_usleep (gx_capture_gap_us (self));' "$d"
! grep -Fq 'GX_SEQ_GAP_US * self->timing_scale' "$d"
grep -Fq 'actual GET_IMAGE transport loss' "$d"
! grep -Fq 'capture pacing follows' "$d"
! grep -Fq 'gx_capture_sync_to_protocol_timing' "$d"
grep -Fq 'successful finger capture' "$d"

python3 - "$d" <<'PY'
from pathlib import Path
import re, sys
s=Path(sys.argv[1]).read_text()

def fn(name):
    m=re.search(r"\b"+re.escape(name)+r"\s*\([^;{}]*\)\s*\n\{", s)
    assert m, name
    b=s.find("{", m.end()-1)
    depth=0
    for i in range(b,len(s)):
        if s[i]=="{": depth+=1
        elif s[i]=="}":
            depth-=1
            if depth==0: return s[m.start():i+1]
    raise AssertionError(name)

gap=fn("gx_capture_gap_us")
desync=fn("gx_capture_transport_desync")
success=fn("gx_capture_pacing_success")
recipe=fn("gx_send_capture_recipe")
cleanup=fn("gx_send_capture_cleanup")

assert "GX_SEQ_GAP_US" in gap
assert "GX_CAPTURE_SCALE_MIN" in gap and "GX_CAPTURE_SCALE_MAX" in gap
assert "GX_CAPTURE_SCALE_STEP" in desync
assert "capture_recovery_pending = TRUE" in desync
assert "gx_capture_timing_save" in success
assert "capture_gap_scale > self->capture_gap_saved" in success
assert "gx_capture_gap_us (self)" in recipe
assert "gx_capture_gap_us (self)" in cleanup

# Default remains exactly 30 ms; adaptive pacing is capture-specific and never
# weakens matcher policy or directly multiplies the gap by timing_scale.
assert "#define GX_SEQ_GAP_US 30000" in s
assert "GX_SEQ_GAP_US * self->timing_scale" not in s
assert re.search(r"^#define\s+GX_MATCH_THRESHOLD\s+7\s*$", s, re.M)
assert re.search(r"^#define\s+GX_VERIFY_MAX_ATTEMPTS\s+3\b", s, re.M)
PY

echo 'test_capture_gap_nominal_source_safety: OK'
