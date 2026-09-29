#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
driver="$root/driver/goodix51a0/goodix51a0.c"

grep -Fq '#define GX_SAME_PRESS_CAPTURE_ATTEMPTS 3' "$driver"
grep -Fq 'Windows OnRetryCaptureIMG keeps the current physical press alive' "$driver"
grep -Fq 'gx_capture_retry_same_press_frame' "$driver"
grep -Fq 'gxfp_build_get_image (&packet)' "$driver"
grep -Fq 'GXFP51A0 AUTH_TRACE mode=%s same-press image %u/%u ' "$driver"
grep -Fq 'GXFP51A0 AUTH_TRACE mode=%s same-press completed ' "$driver"

block="$(sed -n '/^gx_capture_auth_same_press (/,/^}/p' "$driver")"
grep -Fq 'score >= GX_MATCH_THRESHOLD' <<<"$block"
grep -Fq 'score > best_score' <<<"$block"
grep -Fq 'gx_score_probe_against_gallery (gallery, probe' <<<"$block"
grep -Fq 'gx_score_probe_against_print (tmpl, probe' <<<"$block"
! grep -Eq 'best_score[[:space:]]*\+=' <<<"$block"
! grep -Eq 'score[[:space:]]*\+=' <<<"$block"
! grep -Eq 'GX_MATCH_THRESHOLD[[:space:]]*[-+*/]' <<<"$block"
echo 'test_same_press_verify_source_safety: OK (Verify + Identify)'

# rel59: RetryCaptureIMG must not fire immediately after FDT-manual.  Use the
# bounded session-local capture gap, and consume any successful no-evidence
# retry before requesting the next image of the SAME physical press.
grep -Fq 'RetryCaptureIMG pacing barrier=%u us' "$driver"
python3 - "$driver" <<'PY2'
from pathlib import Path
import re, sys
s=Path(sys.argv[1]).read_text()
a=s.index("gx_capture_retry_same_press_frame")
b=s.index("#ifdef GXFP51A0_DEVELOPER", a)
fn=s[a:b]
assert fn.index("g_usleep (gx_capture_gap_us (self))") < fn.index("gxfp_build_get_image (&packet)")
auth=s[s.index("gx_capture_auth_same_press"):s.index("gx_capture_done", s.index("gx_capture_auth_same_press"))]
assert "if (self->capture_retry_seen)" in auth
assert auth.index("gx_capture_pacing_success (self)") < auth.index("images++")
assert "press_retry_seen" not in auth
PY2
