#!/usr/bin/env bash
set -euo pipefail
driver="$(cd "$(dirname "$0")/../.." && pwd)/driver/goodix51a0/goodix51a0.c"
grep -Fq '#define GX_DIAG_CLEAR_GRACE_SEC 3' "$driver"
grep -Fq '#define GX_DIAG_BASELINE_MAX_DRIFT 20' "$driver"
grep -Fq 'CAPTURE_DIAGNOSTIC_CLEAR_SENSOR: REMOVE_FINGER_NOW' "$driver"
grep -Fq 'CAPTURE_DIAGNOSTIC_CALIBRATION_STARTS_IN_%d' "$driver"
grep -Fq 'FDT baseline contaminated by touch' "$driver"
grep -Fq 'CAPTURE_DIAGNOSTIC_BASELINE_STABLE' "$driver"
python3 - "$driver" <<'PY2'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
a=s.index("gx_prepare_capture_context_once (")
b=s.index("gx_preprocess (", a)
f=s[a:b]
assert "capture_diagnostic" in f
assert "off_anchor_mean" in f
assert "GX_DIAG_CLEAR_GRACE_SEC" in f
assert "off_anchor_mean - baseline_mean > GX_DIAG_BASELINE_MAX_DRIFT" in f
# READY must still happen outside session_start, after this calibration completes.
assert "self->have_fdt = TRUE" in f
PY2
echo 'test_capture_clear_sensor_gate_source_safety: OK'
