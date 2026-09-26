#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
driver="$root/driver/goodix51a0/goodix51a0.c"
pkg="$root/packaging/arch/PKGBUILD"
arch="$root/install-arch.sh"
portable="$root/install-linux.sh"

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

crossed=fn("gx_warm_crossed_sleep")
active=fn("gx_active_sleep_recovery")
session=fn("gx_session_start")
poll_on=fn("gx_poll_on")
poll_off=fn("gx_poll_off")
suspend=fn("gx_dev_suspend")
resume=fn("gx_dev_resume")

assert "CLOCK_BOOTTIME" in s and "CLOCK_MONOTONIC" in s
assert "#define GX_SLEEP_DELTA_STALE_US (250 * 1000)" in s
assert "warm_sleep_clock_valid" in crossed
assert "!self->warm_valid" not in crossed
assert "gx_warm_crossed_sleep (self)" in active
assert "active S3 boundary detected during authentication" in active
assert "self->force_cold_reset = TRUE" in active
assert "fpi_ssm_jump_to_state (ssm, GX_ST_SESSION)" in active
assert "gx_active_sleep_recovery (dev, ssm)" in poll_on
assert "gx_active_sleep_recovery (dev, ssm)" in poll_off

assert "if (self->force_cold_reset)" in session
assert "gx_warm_abandon (self)" in session
assert "gx_gpio_reset (self)" in session
assert "gx_cold_prepare (self)" in session
assert "return gx_wakeup_mcu (self)" in session
assert "self->capture_gap_scale = 0" in session
assert "self->capture_pacing_suppressed = TRUE" in session

assert "self->force_cold_reset = TRUE" in suspend
assert "fpi_device_suspend_complete" in suspend
assert "BOOTTIME-vs-MONOTONIC poll guard" in resume
PY2

grep -Fq 'pkgrel=52' "$pkg"
! grep -Fq 'integration/resume-prewarm' "$pkg"
! grep -Fq 'systemd/system-sleep/gxfp51a0-resume-prewarm' "$pkg"
! grep -Fq 'systemd/system-sleep/gxfp51a0-resume-prewarm' "$arch"
! grep -Fq 'RESUME_HELPER_FILE=' "$portable"
! grep -Fq 'RESUME_HOOK_FILE=' "$portable"
grep -Fq '/usr/local/libexec/gxfp51a0-resume-prewarm' "$portable"
grep -Fq '/etc/systemd/system-sleep/gxfp51a0-resume-prewarm' "$portable"

echo 'test_native_resume_recovery_source_safety: OK'
