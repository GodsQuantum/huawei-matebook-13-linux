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
idle=fn("gx_warm_idle_expired")
abandon=fn("gx_warm_abandon")
warm=fn("gx_warm_validate")
open_=fn("gx_dev_open")
close=fn("gx_dev_close")
suspend=fn("gx_dev_suspend")
resume=fn("gx_dev_resume")
klass=fn("fpi_device_goodix51a0_class_init")

assert "CLOCK_BOOTTIME" in sleep and "CLOCK_MONOTONIC" in sleep
assert "gint64 *out" in sleep
assert "warm_sleep_clock_valid" in s
assert "GX_SLEEP_DELTA_STALE_US" in s

# A valid pre-first-suspend baseline may be zero or slightly negative because
# BOOTTIME and MONOTONIC are sampled sequentially. Never use sign as validity.
assert "warm_sleep_delta_us <= 0" not in cross
assert "now > 0" not in cross
assert "!self->warm_sleep_clock_valid" in cross
assert "now - self->warm_sleep_delta_us > GX_SLEEP_DELTA_STALE_US" in cross
assert "sleep boundary detected" in cross

# A warm session is an optimization, never a permanent trust boundary. A
# context left unused for five minutes is rebuilt before any sensor traffic.
assert "GX_WARM_IDLE_TTL_US" in s
assert "5 * 60 * G_USEC_PER_SEC" in s
assert "warm_last_activity_us" in idle
assert "warm context idle for %d s; forcing cold rebuild" in idle
assert "gx_warm_idle_expired (self)" in open_
assert open_.index("gx_warm_idle_expired (self)") < open_.index("gx_transport_open")
assert "slept || expired || self->force_cold_reset" in open_

# Stale sensor-side TLS must be abandoned host-side, not close-notified.
assert "gx_tls_teardown" not in abandon
assert "g_clear_pointer (&self->tls, gx_tls_free)" in abandon
assert "self->warm_sleep_clock_valid = FALSE" in abandon

# A retained context refreshes the exact encrypted image path and adopts that
# proven no-finger frame as the new background/FDT baseline. If the user is
# already touching the sensor, never contaminate the background; lifecycle
# boundaries were rejected before this function, so defer the rebase and let
# the real Verify frame exercise TLS.
assert "gx_fdt_probe (self, cur)" in warm
assert "before_mean < GOODIX_FDT_ABS" in warm
assert warm.index("before_mean < GOODIX_FDT_ABS") < warm.index("gx_capture_frame (self, fresh_bg, TRUE)")
assert "gx_capture_frame (self, fresh_bg, TRUE)" in warm
assert "memcpy (self->bg_frame, fresh_bg" in warm
assert "memcpy (self->fdt_base, after, sizeof self->fdt_base)" in warm
assert "WARM_REBASE refreshed background+FDT" in warm
assert "capture_pacing_suppressed = TRUE" in warm
assert "capture_pacing_suppressed = previous_pacing_suppression" in warm
assert "warm context failed full readiness validation" in open_
failed=open_.split("warm context failed full readiness validation",1)[1]
assert "gx_warm_abandon (self)" in failed
assert "gx_warm_discard (self)" not in failed.split("else if",1)[0]

# Idle-suspend detection runs before opening hardware handles and resets any
# unpersisted pacing escalation caused by the dead S3 session.
assert "gx_warm_crossed_sleep (self)" in open_
assert open_.index("gx_warm_crossed_sleep (self)") < open_.index("gx_transport_open")
assert "gx_gpio_reset (self)" in open_
assert "self->capture_gap_scale = 0" in open_
assert "self->capture_gap_saved = 0" in open_

# For an active action, upstream libfprint requires an error when the action
# cannot safely continue across suspend; NOT_SUPPORTED triggers cancellation.
assert "FP_DEVICE_ERROR_NOT_SUPPORTED" in suspend
assert "fpi_device_suspend_complete" in suspend
assert "self->force_cold_reset = TRUE" in suspend
assert "fpi_device_resume_complete (dev, NULL)" in resume
assert "g_cancellable_cancel" not in resume

assert "dev_class->suspend = gx_dev_suspend" in klass
assert "dev_class->resume = gx_dev_resume" in klass
assert "if (self->force_cold_reset)" in close
assert "gx_warm_abandon (self)" in close
PY2

echo 'test_lifecycle_recovery_source_safety: OK'
