#!/usr/bin/env bash
set -euo pipefail
driver="$(cd "$(dirname "$0")/../.." && pwd)/driver/goodix51a0/goodix51a0.c"

grep -Fq 'production_ready' "$driver"
grep -Fq 'gx_prepare_capture_context' "$driver"
grep -Fq 'GXFP51A0 production capture context ready before EnrollStart/VerifyStart' "$driver"
grep -Fq 'GXFP51A0 reusing capture context prepared during device open' "$driver"
! grep -Fq 'KDE UI:' "$driver"
! grep -Fq 'calibration_had_finger' "$driver"

python3 - "$driver" <<'PY2'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()

a=s.index("gx_dev_open (")
b=s.index("gx_dev_close (", a)
f=s[a:b]
assert "gx_prepare_capture_context_once (self, FALSE)" in f
assert "deferring clean preparation to the biometric action" in f
assert "GXFP51A0 could not prepare a clean capture context" not in f
assert f.index("gx_prepare_capture_context_once (self, FALSE)") < f.rindex("fpi_device_open_complete (dev, NULL)")
assert "GXFP_DIAGNOSTIC_CAPTURE_ONCE" in f
assert "GXFP_DIAGNOSTIC_ONESHOT" in f

a=s.index("gx_session_start (")
b=s.index("gx_preprocess (", a)
f=s[a:b]
assert "self->production_ready" in f
assert "gx_prepare_capture_context (self, capture_diagnostic)" in f
assert "gx_prepare_capture_context (self, FALSE)" in f

a=s.index("gx_dev_close (")
b=s.index("gx_verify_done (", a)
f=s[a:b]
assert "self->production_ready = FALSE" in f
PY2

echo 'test_portable_preclaim_prepare_source_safety: OK'
