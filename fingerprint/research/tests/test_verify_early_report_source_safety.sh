#!/usr/bin/env bash
set -euo pipefail
driver="$(cd "$(dirname "$0")/../.." && pwd)/driver/goodix51a0/goodix51a0.c"

python3 - "$driver" <<'PY2'
from pathlib import Path
import sys
s = Path(sys.argv[1]).read_text()

assert "match_reported" in s
a = s.index("gx_capture_done (")
b = s.index("gx_run_state (", a)
capture = s[a:b]
assert "fpi_device_verify_report (dev," in capture
assert "verify: early result reported" in capture
assert capture.index("fpi_device_verify_report (dev,") < capture.index("gx_poll_off, ssm")

a = s.index("gx_verify_done (")
b = s.index("gx_identify_done (", a)
done = s[a:b]
assert "g_error_matches (error, G_IO_ERROR, G_IO_ERROR_CANCELLED)" in done
assert "if (!t->match_reported)" in done
assert "verify: caller stopped operation after early result" in done
PY2

echo 'test_verify_early_report_source_safety: OK'
