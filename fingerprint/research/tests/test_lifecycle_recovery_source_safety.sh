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

sleep=fn("gx_sleep_delta_us")
cross=fn("gx_warm_crossed_sleep")
abandon=fn("gx_warm_abandon")
open_=fn("gx_dev_open")
close=fn("gx_dev_close")
suspend=fn("gx_dev_suspend")
resume=fn("gx_dev_resume")
klass=fn("fpi_device_goodix51a0_class_init")

assert "CLOCK_BOOTTIME" in sleep and "CLOCK_MONOTONIC" in sleep
assert "GX_SLEEP_DELTA_STALE_US" in s
assert "warm_sleep_delta_us" in cross

# Stale sensor-side TLS must be abandoned host-side, not close-notified.
assert "gx_tls_teardown" not in abandon
assert "g_clear_pointer (&self->tls, gx_tls_free)" in abandon

# Idle-suspend detection runs before opening hardware handles.
assert "gx_warm_crossed_sleep (self)" in open_
assert open_.index("gx_warm_crossed_sleep (self)") < open_.index("gx_transport_open")
assert "gx_gpio_reset (self)" in open_
assert "force_cold_reset" in open_

# Active suspend uses native libfprint lifecycle and defers cancellation until resume.
assert "fpi_device_suspend_complete (dev, NULL)" in suspend
assert "self->force_cold_reset = TRUE" in suspend
assert "fpi_device_resume_complete (dev, NULL)" in resume
assert "g_cancellable_cancel" in resume
assert resume.index("fpi_device_resume_complete") < resume.index("g_cancellable_cancel")

assert "dev_class->suspend = gx_dev_suspend" in klass
assert "dev_class->resume = gx_dev_resume" in klass

# Close after a suspend must abandon stale TLS without sensor traffic.
assert "if (self->force_cold_reset)" in close
assert "gx_warm_abandon (self)" in close
PY2

echo 'test_lifecycle_recovery_source_safety: OK'
