#!/usr/bin/env bash
set -euo pipefail
driver="$(cd "$(dirname "$0")/../.." && pwd)/driver/goodix51a0/goodix51a0.c"

! grep -Fq 'KDE UI:' "$driver"
! grep -Fq 'calibration_had_finger' "$driver"
grep -Fq 'FP_FINGER_STATUS_NEEDED' "$driver"
grep -Fq 'FP_FINGER_STATUS_PRESENT' "$driver"
grep -Fq 'fpi_device_enroll_progress (dev, t->stage, NULL, NULL)' "$driver"

python3 - "$driver" <<'PY2'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()

a=s.index("case GX_ST_WAIT_ON:")
b=s.index("case GX_ST_CAPTURE:", a)
f=s[a:b]
assert "fpi_device_report_finger_status" in f
assert "FP_FINGER_STATUS_NEEDED" in f

a=s.index("gx_poll_on (")
b=s.index("gx_poll_off (", a)
f=s[a:b]
assert "FP_FINGER_STATUS_NEEDED |" in f
assert "FP_FINGER_STATUS_PRESENT" in f

a=s.index("gx_capture_done (")
b=s.index("gx_run_state (", a)
f=s[a:b]
assert "fpi_device_enroll_progress (dev, t->stage, NULL, NULL)" in f
PY2

echo 'test_kde_enroll_ui_feedback_source_safety: OK (portable fprintd contract)'
