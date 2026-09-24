#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
driver="$root/driver/goodix51a0/goodix51a0.c"
helper="$root/integration/resume-prewarm/gxfp51a0-resume-prewarm"
hook="$root/integration/resume-prewarm/gxfp51a0-system-sleep"
pkg="$root/packaging/arch/PKGBUILD"

grep -Fq 'GetDefaultDevice' "$helper"
grep -Fq 'Claim s ""' "$helper"
grep -Fq 'timeout 50s busctl --system --timeout=45s call' "$helper"
! grep -Eq 'restart.*fprintd|try-restart.*fprintd|VerifyStart|EnrollStart' "$helper"

grep -Fq 'phase="${1:-}"' "$hook"
grep -Fq '[[ "$phase" == "post" ]]' "$hook"
grep -Fq 'suspend|hibernate|hybrid-sleep|suspend-then-hibernate' "$hook"
grep -Fq 'timeout 55s "$helper"' "$hook"
! grep -Fq 'systemctl' "$hook"

grep -Fq 'systemd/system-sleep/gxfp51a0-resume-prewarm' "$pkg"
! grep -Fq 'gxfp51a0-resume-prewarm-worker.service' "$pkg"
! grep -Fq 'sleep.target.wants/gxfp51a0-resume-prewarm.service' "$pkg"

python3 - "$driver" <<'PY'
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
frame=fn("gx_capture_frame_ex")
open_=fn("gx_dev_open")

assert "#define GX_CAPTURE_CLEAN_DECAY_STREAK 8" in s
assert "capture_pacing_suppressed" in desync
assert "lifecycle recovery desync: pacing remains" in desync
assert "capture_clean_streak = 0" in desync
assert "capture_retry_seen" in success
assert "capture_clean_streak++" in success
assert "previous - GX_CAPTURE_SCALE_STEP" in success
assert "gx_capture_timing_save" not in success
assert "protocol_floor" in success
assert "session capture pacing calibrated by retry-assisted" in success
assert "session capture pacing decayed after %d clean" in success
assert "self->capture_retry_seen = FALSE" in frame
assert "self->capture_pacing_suppressed = TRUE" in open_
PY

echo 'test_resume_prewarm_source_safety: OK'
