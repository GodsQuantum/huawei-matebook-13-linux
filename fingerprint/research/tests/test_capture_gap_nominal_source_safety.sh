#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
d="$root/driver/goodix51a0/goodix51a0.c"

grep -Fq '#define GX_SEQ_GAP_US 30000' "$d"
grep -Fq '#define GX_CAPTURE_SCALE_MIN 100' "$d"
grep -Fq '#define GX_CAPTURE_SCALE_MAX 300' "$d"
grep -Fq '#define GX_CAPTURE_SCALE_STEP 50' "$d"
grep -Fq '#define GX_CAPTURE_RETRY_ESCALATE_STREAK 3' "$d"
grep -Fq '#define GX_CAPTURE_CLEAN_DECAY_STREAK 8' "$d"
grep -Fq 'g_usleep (gx_capture_gap_us (self));' "$d"
grep -Fq 'session capture pacing raised after %d' "$d"
grep -Fq 'session capture pacing decayed after %d clean' "$d"
grep -Fq 'not persisted' "$d"

! grep -Fq 'GX_CAPTURE_TIMING_FILE' "$d"
! grep -Fq 'gx_capture_timing_save' "$d"
! grep -Fq 'gx_capture_timing_load' "$d"
! grep -Fq 'capture_gap_saved' "$d"
! grep -Fq 'GX_SEQ_GAP_US * self->timing_scale' "$d"

python3 - "$d" <<'PY'
from pathlib import Path
import re, sys
s=Path(sys.argv[1]).read_text()

def fn(name):
    m=re.search(r"\b"+re.escape(name)+r"\s*\([^;{}]*\)\s*\n\{", s)
    assert m, name
    b=s.find("{", m.end()-1); depth=0
    for i in range(b,len(s)):
        if s[i]=="{": depth+=1
        elif s[i]=="}":
            depth-=1
            if depth==0: return s[m.start():i+1]
    raise AssertionError(name)

desync=fn("gx_capture_transport_desync")
success=fn("gx_capture_pacing_success")
cold=fn("gx_cold_prepare")

assert "capture_recovery_pending = TRUE" in desync
assert "capture_pacing_suppressed" in desync
assert "GX_CAPTURE_SCALE_STEP" in desync
assert "not persisted" in desync
assert "capture_retry_streak++" in success
assert "GX_CAPTURE_RETRY_ESCALATE_STREAK" in success
assert "previous - GX_CAPTURE_SCALE_STEP" in success
assert "GX_CAPTURE_CLEAN_DECAY_STREAK" in success
assert "self->capture_gap_scale = GX_CAPTURE_SCALE_MIN" in cold

assert "GX_CAPTURE_TIMING_FILE" not in s
assert "gx_capture_timing_save" not in s
assert "gx_capture_timing_load" not in s
assert re.search(r"^#define\s+GX_MATCH_THRESHOLD\s+7\s*$", s, re.M)
assert re.search(r"^#define\s+GX_VERIFY_MAX_ATTEMPTS\s+3\b", s, re.M)
PY

echo 'test_capture_gap_nominal_source_safety: OK (session-local adaptive pacing)'
