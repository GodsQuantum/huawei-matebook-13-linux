#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
driver="$root/driver/goodix51a0/goodix51a0.c"
pkg="$root/packaging/arch/PKGBUILD"

python3 - "$driver" <<'PY'
from pathlib import Path
import re, sys
s=Path(sys.argv[1]).read_text()

def fn(name):
    m=re.search(r"\b"+re.escape(name)+r"\s*\([^;{}]*\)\s*\n\{", s)
    assert m, name
    b=s.find("{",m.end()-1); depth=0
    for i in range(b,len(s)):
        if s[i]=="{": depth+=1
        elif s[i]=="}":
            depth-=1
            if depth==0: return s[m.start():i+1]
    raise AssertionError(name)

cold=fn("gx_cold_prepare")
open_=fn("gx_dev_open")
session=fn("gx_session_start")
init=fn("fpi_device_goodix51a0_init")
abandon=fn("gx_warm_abandon")

# DriverState:Install is Windows first-initialization work, not every rebuild.
assert "driverstate_attempted" in s
assert "if (!self->driverstate_attempted)" in cold
assert cold.index("self->driverstate_attempted = TRUE") < cold.index("gx_driverstate_install_windows (self)")
assert "FAST_RESUME DriverState Install already attempted" in cold
assert "self->driverstate_attempted = FALSE" in init
assert "driverstate_attempted" not in abandon
assert "gx_sleep_delta_us (&self->warm_sleep_delta_us)" in init
assert "warm_sleep_clock_valid = FALSE" not in abandon

# rel56 five-minute quality bound remains: rel55 proved that hours-old awake
# imaging state can pass FDT/TLS validation while genuine scores collapse.
assert "#define GX_WARM_IDLE_TTL_US (5 * 60 * G_USEC_PER_SEC)" in s
assert "gx_warm_idle_expired" in s
assert "if (gx_warm_available (self))" in open_
assert "gx_warm_validate (self)" in open_

# Real S3 gets the proactive reset+A8 boundary; TTL expiry remains normal cold reset.
assert "lifecycle_boundary = slept || expired || self->force_cold_reset" in open_
assert "hard_lifecycle_boundary = slept || self->force_cold_reset" in open_
assert "FAST_RESUME establishing reset+A8 boundary before first post-lifecycle TLS" in open_
assert open_.index("gx_recover_capture_context (self)") < open_.index("gx_cold_prepare (self)")
assert "FAST_RESUME active operation: reset+A8 before first TLS" in session
assert session.index("gx_recover_capture_context (self)") < session.index("gx_cold_prepare (self)")

tls=fn("gx_tls_session")
assert "#define GX_TLS_SESSION_ATTEMPTS 3" in tls
assert "diagnostic ? 1 : GX_TLS_SESSION_ATTEMPTS" in tls
assert "max_attempts" in tls
PY

grep -Fq 'pkgrel=63' "$pkg"
echo 'test_fast_resume_source_safety: OK'
