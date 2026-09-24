#!/usr/bin/env bash
set -euo pipefail
driver="$(cd "$(dirname "$0")/../.." && pwd)/driver/goodix51a0/goodix51a0.c"
grep -Fq 'CAPTURE_DIAGNOSTIC_PRESS_IN_%d' "$driver"
grep -Fq 'CAPTURE_DIAGNOSTIC_PRESS_NOW: PRESS_AND_HOLD_NOW' "$driver"
grep -Fq 'CAPTURE_DIAGNOSTIC_COUNTDOWN_RESTART: REMOVE_FINGER' "$driver"
grep -Fq 'gx_diag_press_countdown' "$driver"
python3 - "$driver" <<'PY2'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
a=s.index("gx_diag_press_countdown (")
b=s.index("gx_session_start (", a)
f=s[a:b]
assert "for (q = 3; q > 0; q--)" in f
assert "gx_fdt_probe_ex (self, cur, &touchflag)" in f
assert "gx_fdt_touch_is_finger (touchflag)" in f
assert "off_anchor_mean - mean > GX_DIAG_BASELINE_MAX_DRIFT" in f
assert "gx_wait_sensor_clear (self, off_anchor_mean, NULL)" in f
assert "restart = TRUE" in f
a=s.index("gx_prepare_capture_context_once (")
b=s.index("gx_session_start (", a)
f=s[a:b]
assert "gx_diag_press_countdown (self, off_anchor_mean)" in f
PY2
echo 'test_capture_press_countdown_source_safety: OK'
