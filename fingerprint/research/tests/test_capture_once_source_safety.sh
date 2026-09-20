#!/usr/bin/env bash
set -euo pipefail
driver="$(cd "$(dirname "$0")/../.." && pwd)/driver/goodix51a0/goodix51a0.c"
grep -Fq 'GXFP_DIAGNOSTIC_CAPTURE_ONCE' "$driver"
grep -Fq 'capture-only diagnostic complete' "$driver"
grep -Fq 'CAPTURE_DIAGNOSTIC_PREPARING_BACKGROUND: KEEP_FINGER_OFF_SENSOR' "$driver"
grep -Fq 'CAPTURE_DIAGNOSTIC_READY: PRESS_AND_HOLD_FINGER' "$driver"
grep -Fq 'CAPTURE_DIAGNOSTIC_DONE: REMOVE_FINGER' "$driver"
grep -Fq 'g_file_set_contents_full' "$driver"
grep -Fq 'G_FILE_SET_CONTENTS_CONSISTENT' "$driver"
grep -Fq '0600' "$driver"
python3 - "$driver" <<'PY2'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
a=s.index("gx_capture_thread (")
b=s.index("gx_session_done (", a)
f=s[a:b]
assert f.count("gx_capture_features (self)") == 1
assert "GX_VIEWS_PER_STAGE" not in f
a=s.index("gx_capture_done (")
b=s.index("gx_run_state (", a)
f=s[a:b]
assert 'g_getenv ("GXFP_DIAGNOSTIC_CAPTURE_ONCE")' in f
assert 'fpi_ssm_mark_failed' in f
PY2
echo 'test_capture_once_source_safety: OK'
