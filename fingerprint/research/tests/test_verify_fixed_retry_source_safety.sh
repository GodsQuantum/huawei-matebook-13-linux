#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
d="$root/driver/goodix51a0/goodix51a0.c"

grep -Fq '#define GX_VERIFY_MAX_ATTEMPTS 3' "$d"
grep -Fq 't->tries < GX_VERIFY_MAX_ATTEMPTS' "$d"
grep -Fq 't->tries >= GX_VERIFY_MAX_ATTEMPTS' "$d"
grep -Fq 'request another complete press' "$d"
grep -Fq 'finger released; waiting for retry press' "$d"
grep -Fq 'fixed attempts' "$d"
grep -Fq 'identify: no-match press %d/%d' "$d"
grep -Fq 'identify: no-match reported after %d fixed presses' "$d"

python3 - "$d" <<'PY'
from pathlib import Path
import re,sys
s=Path(sys.argv[1]).read_text()

assert re.search(r'^#define\s+GX_MATCH_THRESHOLD\s+7\s*$', s, re.M)
assert re.search(r'^#define\s+GX_VERIFY_MAX_ATTEMPTS\s+3\b', s, re.M)

# Retry policy must never lower threshold or fuse weak scores.
assert 'GX_MATCH_THRESHOLD -' not in s
assert 'score +=' not in s
assert 'best_score +=' not in s

# Verify and Identify may both consume the same fixed physical-press budget,
# but only while no terminal result has been reported.
poll=s[s.index('gx_poll_off ('):s.index('gx_score_probe_against_print',s.index('gx_poll_off ('))]
assert 't->verifying && !t->match_reported' in poll
assert 't->tries < GX_VERIFY_MAX_ATTEMPTS' in poll
assert '!t->identifying' not in poll

capture=s[s.index('gx_capture_done ('):s.index('gx_run_state (',s.index('gx_capture_done ('))]
assert 'attempt_score >= GX_MATCH_THRESHOLD' in capture
assert 'best_print && best >= GX_MATCH_THRESHOLD' in capture
assert 't->tries >= GX_VERIFY_MAX_ATTEMPTS' in capture
assert 'FPI_MATCH_SUCCESS' in capture
assert 'FPI_MATCH_FAIL' in capture
PY

echo 'test_verify_fixed_retry_source_safety: OK (bounded Verify+Identify pose budget)'
