#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
d="$root/driver/goodix51a0/goodix51a0.c"

grep -Fq 'rearm_mcu_before_retry' "$d"
grep -Fq 'request another complete press with MCU rearm' "$d"
grep -Fq 'MCU rearmed after failed usable' "$d"
grep -Fq 'press before retry %d/%d' "$d"

python3 - "$d" <<'PY2'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()

poll=s[s.index("gx_poll_off (gpointer user_data)"):s.index("gx_score_probe_against_print", s.index("gx_poll_off (gpointer user_data)"))]
assert "if (t->rearm_mcu_before_retry)" in poll
assert poll.index("gx_wakeup_mcu (self)") < poll.index("fpi_ssm_jump_to_state (ssm, GX_ST_WAIT_ON)")
assert "t->rearm_mcu_before_retry = FALSE" in poll
assert "MCU rearm failed before retry press" in poll

capture=s[s.index("gx_capture_done ("):s.index("gx_run_state (", s.index("gx_capture_done ("))]
assert capture.count("t->rearm_mcu_before_retry = TRUE") == 2
# The flag must only be set in no-match branches that still have retry budget.
assert capture.index("t->rearm_mcu_before_retry = TRUE") > capture.index("t->tries++")
assert "GX_MATCH_THRESHOLD" in capture

# No matcher/threshold/re-enrollment shortcuts are part of this release.
assert "#define GX_MATCH_THRESHOLD" in s and "7" in s[s.index("#define GX_MATCH_THRESHOLD"):s.index("#define GX_MATCH_THRESHOLD")+64]
assert "#define GX_VERIFY_MAX_ATTEMPTS 3" in s
assert "#define GX_SAME_PRESS_CAPTURE_ATTEMPTS 3" in s
PY2

echo 'test_retry_pose_mcu_rearm_source_safety: OK'
