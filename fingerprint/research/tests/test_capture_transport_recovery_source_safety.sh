#!/usr/bin/env bash
set -euo pipefail
driver="$(cd "$(dirname "$0")/../.." && pwd)/driver/goodix51a0/goodix51a0.c"

python3 - "$driver" <<'PY'
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

capture_done=fn("gx_capture_done")
poll_off=fn("gx_poll_off")
session=fn("gx_session_start")
recover=fn("gx_recover_capture_context")
open_=fn("gx_dev_open")
avg=fn("gx_capture_avg")

assert "capture_recovery_pending" in s
assert "#define GX_RECOVERY_OFF_POLLS 2" in s

# A missing image is transport recovery. It does not increment t->tries or
# advance enrollment stage; it requests release and waits for session rebuild.
branch=capture_done.index("if (!f && self->capture_recovery_pending)")
normal=capture_done.index("if (!f || gx_sift_keypoints")
assert branch < normal
snippet=capture_done[branch:normal]
assert "t->tries++" not in snippet
assert "t->stage++" not in snippet
assert "gx_poll_off" in snippet

# Release/recovery is bounded even if FDT itself is unhealthy, and then returns
# through GX_ST_SESSION so background/finger-off invariants are rebuilt.
assert "GX_RECOVERY_OFF_POLLS" in poll_off
assert "if (self->capture_recovery_pending)" in poll_off
assert "GX_ST_SESSION" in poll_off

# Session/open both honor pending recovery before reusing warm state.
assert "gx_recover_capture_context (self)" in session
assert session.index("gx_recover_capture_context (self)") < session.index("self->production_ready")
assert "pending capture recovery found at open" in open_
assert "gx_recover_capture_context (self)" in open_

# Recovery remains the validated full MCU reset/A8 boundary.
assert "gx_tls_teardown (self)" in recover
assert "gx_gpio_reset (self)" in recover
assert "gx_read_fw_version_stage2e" in recover

# Background averaging stops immediately on transport loss instead of producing
# a minute-long no-ACK storm on the same broken context.
assert "if (self->capture_recovery_pending)" in avg
assert "return FALSE" in avg
PY

echo 'test_capture_transport_recovery_source_safety: OK'
