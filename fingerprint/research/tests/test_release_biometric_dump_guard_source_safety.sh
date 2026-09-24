#!/usr/bin/env bash
set -euo pipefail
driver="$(cd "$(dirname "$0")/../.." && pwd)/driver/goodix51a0/goodix51a0.c"

python3 - "$driver" <<'PY2'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()

assert '#define GX_DUMP_DIR "/run/goodix51a0/dump"' in s
start=s.index("/* Dumps captures for offline evaluation.")
guard=s.rfind("#ifdef GXFP51A0_DEVELOPER", 0, start)
end=s.index("#endif", start)
assert guard >= 0 and end > start

a=s.index("gx_capture_frame_ex (")
b=s.index("gx_cmp_dbl", a)
capture=s[a:b]
call=capture.index("gx_dump_capture (self, px);")
guard=capture.rfind("#ifdef GXFP51A0_DEVELOPER", 0, call)
end=capture.find("#endif", call)
assert guard >= 0 and end > call
PY2

echo 'test_release_biometric_dump_guard_source_safety: OK'
