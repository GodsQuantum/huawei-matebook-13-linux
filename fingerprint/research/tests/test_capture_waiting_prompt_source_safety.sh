#!/usr/bin/env bash
set -euo pipefail
driver="$(cd "$(dirname "$0")/../.." && pwd)/driver/goodix51a0/goodix51a0.c"
grep -Fq 'CAPTURE_DIAGNOSTIC_WAITING_FOR_FINGER: PRESS_AND_HOLD_NOW' "$driver"
python3 - "$driver" <<'PY2'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
a=s.index("gx_poll_on (")
b=s.index("gx_poll_off (", a)
f=s[a:b]
assert 'g_getenv ("GXFP_DIAGNOSTIC_CAPTURE_ONCE")' in f
assert "t->polls % 5 == 0" in f
assert "CAPTURE_DIAGNOSTIC_WAITING_FOR_FINGER: PRESS_AND_HOLD_NOW" in f
PY2
echo 'test_capture_waiting_prompt_source_safety: OK'
