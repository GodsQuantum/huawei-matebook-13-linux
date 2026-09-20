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

python3 - "$d" <<'PY'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
# Fixed-budget retry must not inspect score distance or use a lower accept threshold.
assert '#define GX_MATCH_THRESHOLD            7' in s
assert 'GX_VERIFY_MAX_ATTEMPTS 3' in s
retry=s[s.index('verify: no-match attempt'):s.index('verify: no-match attempt')+300]
assert 'GX_MATCH_THRESHOLD -' not in retry
assert 'attempt_score >=' not in retry
# Identify remains one-shot; only verification loops.
poll=s[s.index('gx_poll_off ('):s.index('gx_score_probe_against_print',s.index('gx_poll_off ('))]
assert '!t->identifying' in poll
PY

echo 'test_verify_fixed_retry_source_safety: OK'
