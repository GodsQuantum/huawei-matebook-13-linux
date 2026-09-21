#!/usr/bin/env bash
set -euo pipefail
driver="$(cd "$(dirname "$0")/../.." && pwd)/driver/goodix51a0/goodix51a0.c"

python3 - "$driver" <<'PY'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
assert "#define GX_VERIFY_MAX_ATTEMPTS 3" in s
a=s.index("gx_capture_done (")
b=s.index("gx_run_state (",a)
capture=s[a:b]
assert "FPI_MATCH_SUCCESS" in capture
assert "t->tries >= GX_VERIFY_MAX_ATTEMPTS" in capture
assert "FPI_MATCH_FAIL" in capture
assert "verify: match reported on attempt" in capture
assert "verify: no-match reported after %d fixed attempts" in capture

# The transport-recovery branch may schedule gx_poll_off before any image
# exists; it must not emit a biometric verdict. A real captured-image verdict
# still happens before the normal release poll at the end of capture_done.
recovery=capture[capture.index("if (!f && self->capture_recovery_pending)"):
                 capture.index("if (!f || gx_sift_keypoints")]
assert "FPI_MATCH_SUCCESS" not in recovery and "FPI_MATCH_FAIL" not in recovery
assert capture.index("FPI_MATCH_SUCCESS") < capture.rindex("gx_poll_off, ssm")

a=s.index("gx_verify_done (")
b=s.index("gx_identify_done (",a)
done=s[a:b]
assert "g_error_matches (error, G_IO_ERROR, G_IO_ERROR_CANCELLED)" in done
assert "if (!t->match_reported)" in done
PY

echo 'test_verify_early_report_source_safety: OK (success early, failure after fixed budget)'
