#!/usr/bin/env bash
set -euo pipefail
driver="$(cd "$(dirname "$0")/../.." && pwd)/driver/goodix51a0/goodix51a0.c"

python3 - "$driver" <<'PY2'
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

drain=fn("gx_send_plain_drain")
late=fn("gx_fail_get_image_after_tls_timeout")
capture=fn("gx_capture_frame_ex")
cleanup=fn("gx_send_capture_cleanup")
same_press=fn("gx_capture_retry_same_press_frame")

# A provably swallowed GET_IMAGE (neither ACK nor TLS) may be replayed once.
assert "#define GX_GET_IMAGE_ATTEMPTS 2" in s
assert "if (tls_seen || ack_seen)" in drain
assert "GET_IMAGE had no ACK/TLS; retrying" in drain

# Once GET_IMAGE was accepted, never issue a second GET_IMAGE on the ambiguous
# late-record path.  A full MCU/TLS rebuild is the recovery boundary.
assert "gxfp_build_get_image" not in late
assert "gx_send_plain_drain (self" not in late
assert "gx_take_tls_frame" not in late
assert "not replaying accepted command; forcing full session recovery" in late
assert "gx_capture_transport_desync (self)" in late

# Both normal and cleanup image paths use the no-replay failure helper.
assert "gx_fail_get_image_after_tls_timeout (self)" in capture
assert "gx_fail_get_image_after_tls_timeout (self)" in cleanup
assert "gx_fail_get_image_after_tls_timeout (self)" in same_press

# An authenticated-record failure also poisons semantic/TLS state and must
# request the same bounded full-session recovery before another biometric press.
assert "cannot authenticate/decrypt the image record" in capture
assert "gx_capture_transport_desync (self)" in capture
assert "capture cleanup image record failed" in cleanup
assert "gx_capture_transport_desync (self)" in cleanup
assert "forcing full session recovery" in same_press
assert "gx_capture_transport_desync (self)" in same_press

assert "gx_retry_get_image_after_tls_timeout" not in s
assert "ACK arrived but TLS image timed out; retrying once" not in s
PY2
echo 'test_get_image_ack_tls_timeout_recovery_source_safety: OK'
