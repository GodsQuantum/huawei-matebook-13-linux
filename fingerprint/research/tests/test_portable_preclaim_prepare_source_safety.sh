#!/usr/bin/env bash
set -euo pipefail
driver="$(cd "$(dirname "$0")/../.." && pwd)/driver/goodix51a0/goodix51a0.c"

grep -Fq 'production_ready' "$driver"
grep -Fq 'warm_valid' "$driver"
grep -Fq 'gx_prepare_capture_context' "$driver"
grep -Fq 'GXFP51A0 production capture context ready; native warm state armed' "$driver"
grep -Fq 'GXFP51A0 reusing native libfprint warm context' "$driver"
grep -Fq 'GXFP51A0 reusing capture context prepared during device open' "$driver"
! grep -Fq 'KDE UI:' "$driver"
! grep -Fq 'calibration_had_finger' "$driver"

python3 - "$driver" <<'PY2'
from pathlib import Path
import re, sys

s=Path(sys.argv[1]).read_text()

def fn(name):
    m=re.search(r"\b"+re.escape(name)+r"\s*\([^;{}]*\)\s*\n\{", s)
    assert m is not None, name
    brace=s.find("{", m.end()-1)
    depth=0
    for i in range(brace, len(s)):
        if s[i]=="{":
            depth+=1
        elif s[i]=="}":
            depth-=1
            if depth==0:
                return s[m.start():i+1]
    raise AssertionError(name)

cold=fn("gx_cold_prepare")
probe=fn("gx_dev_probe")
open_=fn("gx_dev_open")
session=fn("gx_session_start")
close=fn("gx_dev_close")

# rel24: enumeration performs one short opportunistic prewarm. A failed prewarm
# does not make the device disappear; open retains the full cold fallback.
assert "GX_PROBE_PREWARM_ATTEMPTS 1" in s
assert "gx_cold_prepare (self)" in probe
assert "probe prewarm attempt %d/%d failed" in probe
assert "fpi_device_probe_complete (dev, NULL, NULL, NULL)" in probe
assert "gx_warm_validate (self)" in open_
assert "reusing native libfprint warm context" in open_
assert "falling back to cold preparation" in open_
assert "gx_cold_prepare (self)" in open_

# Cold preparation itself performs exactly one context attempt; biometric
# operations retain the existing bounded whole-session recovery path.
assert "gx_prepare_capture_context_once (self, FALSE)" in cold
assert "deferring bounded recovery to the biometric action" in cold
assert "self->production_ready" in session
assert "gx_prepare_capture_context (self, capture_diagnostic)" in session
assert "gx_prepare_capture_context (self, FALSE)" in session

# Release closes hardware handles but preserves a complete validated warm
# context in the same libfprint object for the next Claim.
assert "self->production_ready = FALSE" in close
assert "self->warm_valid" in close
assert "gx_transport_close (self)" in close
assert "gx_warm_discard (self)" in close
PY2

echo 'test_portable_preclaim_prepare_source_safety: OK'
