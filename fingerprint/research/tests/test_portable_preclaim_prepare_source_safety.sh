#!/usr/bin/env bash
set -euo pipefail
driver="$(cd "$(dirname "$0")/../.." && pwd)/driver/goodix51a0/goodix51a0.c"

python3 - "$driver" <<'PY2'
from pathlib import Path
import re, sys
s=Path(sys.argv[1]).read_text()

def fn(name):
    m=re.search(r"\b"+re.escape(name)+r"\s*\([^;{}]*\)\s*\n\{", s)
    assert m is not None, name
    b=s.find("{", m.end()-1); depth=0
    for i in range(b, len(s)):
        if s[i]=="{": depth+=1
        elif s[i]=="}":
            depth-=1
            if depth==0: return s[m.start():i+1]
    raise AssertionError(name)

cold=fn("gx_cold_prepare")
probe=fn("gx_dev_probe")
open_=fn("gx_dev_open")
session=fn("gx_session_start")
close=fn("gx_dev_close")

assert "production_ready" in s and "warm_valid" in s
assert "probe_prewarm" not in s

# rel26: probe is host-transport-only. No biometric/session I/O before Claim.
assert "gx_transport_open" in probe and "gx_transport_close" in probe
for forbidden in ("gx_cold_prepare", "gx_gpio_reset", "gx_tls_session",
                  "gx_prepare_capture_context"):
    assert forbidden not in probe

# Claim performs bounded preparation and never reports success after a failed prepare.
assert "gx_prepare_capture_context (self, FALSE)" in cold
assert "if (!gx_cold_prepare (self))" in open_
assert "fpi_device_error_new_msg" in open_
assert "gx_warm_validate (self)" in open_
assert "reusing native libfprint warm context" in open_

# Operations can still defensively rebuild if an external client bypasses normal lifecycle.
assert "gx_prepare_capture_context (self, FALSE)" in session
assert "capture_recovery_pending" in session

# A validated warm session is retained only across ordinary Claim/Release.
assert "self->production_ready = FALSE" in close
assert "self->warm_valid" in close
assert "self->force_cold_reset" in close
PY2

echo 'test_portable_preclaim_prepare_source_safety: OK'
