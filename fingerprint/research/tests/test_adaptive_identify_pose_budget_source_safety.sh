#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
d="$root/driver/goodix51a0/goodix51a0.c"

grep -Fq '#define GX_REPOSE_SCORE_CUTOFF 4' "$d"
grep -Fq 'attempt == 1 && score <= GX_REPOSE_SCORE_CUTOFF' "$d"
grep -Fq 'requesting reposition instead of same-press recapture' "$d"
grep -Fq 'identify: match reported on press %d/%d' "$d"
grep -Fq 'identify: no-match reported after %d fixed presses' "$d"
grep -Fq 'identify: no-match press %d/%d' "$d"
grep -Fq 't->best = MAX (t->best, best);' "$d"
grep -Fq 'capture pacing seeded from protocol calibration' "$d"
grep -Fq 'self->timing_scale - GX_CAPTURE_SCALE_STEP' "$d"
grep -Fq 'not persisted' "$d"

python3 - "$d" <<'PY2'
from pathlib import Path
import re,sys
s=Path(sys.argv[1]).read_text()
assert re.search(r'^#define\s+GX_MATCH_THRESHOLD\s+7\s*$', s, re.M)
assert re.search(r'^#define\s+GX_VERIFY_MAX_ATTEMPTS\s+3\b', s, re.M)
assert "score >=" + " GX_MATCH_THRESHOLD" in s
# No cross-image score fusion: each image still needs its own threshold decision.
assert "score +=" not in s
assert "best_score +=" not in s
# Identify retries may continue internally, but only while no verdict was reported.
assert "t->verifying && !t->match_reported" in s
assert "t->tries < GX_VERIFY_MAX_ATTEMPTS" in s
# Security boundary: success remains threshold-gated and failure remains bounded.
assert "best_print && best >= GX_MATCH_THRESHOLD" in s
assert "t->tries >= GX_VERIFY_MAX_ATTEMPTS" in s
PY2

echo 'test_adaptive_identify_pose_budget_source_safety: OK'
