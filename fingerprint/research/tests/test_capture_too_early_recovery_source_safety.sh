#!/usr/bin/env bash
set -euo pipefail
driver="$(cd "$(dirname "$0")/../.." && pwd)/driver/goodix51a0/goodix51a0.c"
grep -Fq '#define GX_CLEAR_WAIT_MS 15000' "$driver"
grep -Fq 'calibration waiting for sensor clear' "$driver"
grep -Fq 'sensor clear again' "$driver"
grep -Fq 'gx_wait_sensor_clear' "$driver"
python3 - "$driver" <<'PY2'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
a=s.index("gx_wait_sensor_clear (")
b=s.index("gx_session_start (", a)
f=s[a:b]
assert "GX_CLEAR_WAIT_MS" in f
assert "gx_fdt_probe (self, cur)" in f
assert "off_anchor_mean - mean <= GX_DIAG_BASELINE_MAX_DRIFT" in f
assert "calibration waiting for sensor clear" in f
assert "sensor clear again" in f
a=s.index("gx_prepare_capture_context_once (")
b=s.index("gx_preprocess (", a)
f=s[a:b]
assert "gx_wait_sensor_clear (self, off_anchor_mean, NULL)" in f
assert "FDT baseline contaminated by touch" in f
assert "gx_wait_sensor_clear (self, off_anchor_mean, NULL)" in f
PY2
echo 'test_capture_too_early_recovery_source_safety: OK'
