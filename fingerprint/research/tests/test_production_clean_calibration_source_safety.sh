#!/usr/bin/env bash
set -euo pipefail
driver="$(cd "$(dirname "$0")/../.." && pwd)/driver/goodix51a0/goodix51a0.c"
grep -Fq '#define GX_CLEAR_WAIT_MS 15000' "$driver"
grep -Fq 'gx_wait_clean_anchor' "$driver"
grep -Fq 'GXFP51A0 calibration waiting for sensor clear' "$driver"
grep -Fq 'background contaminated by touch' "$driver"
grep -Fq 'FDT baseline contaminated by touch' "$driver"
! grep -Fq 'taking the background anyway' "$driver"
python3 - "$driver" <<'PY2'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
a=s.index("gx_prepare_capture_context_once (")
b=s.index("gx_preprocess (", a)
f=s[a:b]
assert "gx_wait_clean_anchor (self, &off_anchor_mean)" in f
assert "gx_wait_sensor_clear (self, off_anchor_mean, &clear_mean)" in f
assert "off_anchor_mean - mean <= GX_DIAG_BASELINE_MAX_DRIFT" in f
assert "off_anchor_mean - baseline_mean > GX_DIAG_BASELINE_MAX_DRIFT" in f
assert "capture_diagnostic && off_anchor_mean" not in f
PY2
echo 'test_production_clean_calibration_source_safety: OK'
