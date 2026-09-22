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

assert "#define GX_PREPARE_ATTEMPTS 2" in s
wrapper=fn("gx_prepare_capture_context")
cold=fn("gx_cold_prepare")
probe=fn("gx_dev_probe")
open_=fn("gx_dev_open")
recover=fn("gx_recover_capture_context")

assert "gx_prepare_capture_context_once (self, FALSE)" in wrapper
assert "gx_recover_capture_context (self)" in wrapper
assert "gx_prepare_capture_context (self, FALSE)" in cold
assert "gx_prepare_capture_context_once (self, FALSE)" not in cold

# Enumeration must never start a sensor/TLS/capture session.
for forbidden in ("gx_gpio_reset", "gx_cold_prepare", "gx_tls_session",
                  "gx_prepare_capture_context"):
    assert forbidden not in probe, forbidden
assert "gx_transport_open" in probe and "gx_transport_close" in probe
assert "fpi_device_probe_complete (dev, NULL, NULL, NULL)" in probe

# A real Claim/open owns preparation and must propagate failure.
assert "if (!gx_cold_prepare (self))" in open_
assert "GXFP51A0 cold preparation failed" in open_
assert "fpi_device_open_complete (dev, NULL)" in open_
assert open_.index("if (!gx_cold_prepare (self))") < open_.rindex("fpi_device_open_complete (dev, NULL)")

assert "gx_tls_teardown (self)" in recover
assert "gx_gpio_reset (self)" in recover
assert "gx_read_fw_version_stage2e" in recover
assert "gx_pmk_clear" not in recover
PY2

echo 'test_prepare_soft_preclaim_source_safety: OK'
