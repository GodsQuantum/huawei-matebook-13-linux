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
    brace=s.find("{", m.end()-1)
    depth=0
    for i in range(brace, len(s)):
        if s[i]=="{": depth+=1
        elif s[i]=="}":
            depth-=1
            if depth==0: return s[m.start():i+1]
    raise AssertionError(name)

assert "#define GX_PREPARE_ATTEMPTS 2" in s
assert "gx_prepare_capture_context_once (" in s
assert "gx_recover_capture_context (" in s

wrapper=fn("gx_prepare_capture_context")
assert "GX_PREPARE_ATTEMPTS" in wrapper
assert "gx_prepare_capture_context_once (self, FALSE)" in wrapper
assert "gx_recover_capture_context (self)" in wrapper

probe=fn("gx_dev_probe")
cold=fn("gx_cold_prepare")
open_=fn("gx_dev_open")

# rel23 moves opportunistic preparation to probe(). It is explicitly soft:
# exhausting the two prewarm attempts still completes enumeration successfully.
assert "#define GX_PROBE_PREWARM_ATTEMPTS 2" in s
assert "gx_cold_prepare (self)" in probe
assert "probe prewarm unavailable; device remains usable through the cold open path" in probe
assert "fpi_device_probe_complete (dev, NULL, NULL, NULL)" in probe

# A prewarm miss may clear only process-local transient state. Durable PMK cache
# remains trusted; the real biometric operation/open still has its cold fallback.
assert "deferring bounded recovery to the biometric action" in cold
assert "gx_pmk_cache" not in cold or "unlink" not in cold
assert "gx_cold_prepare (self)" in open_
assert "fpi_device_open_complete (dev, NULL)" in open_

recovery=fn("gx_recover_capture_context")
assert "gx_tls_teardown (self)" in recovery
assert "gx_gpio_reset (self)" in recovery
assert "gx_read_fw_version_stage2e" in recovery
assert "gx_pmk_clear" not in recovery
PY2

echo 'test_prepare_soft_preclaim_source_safety: OK'
