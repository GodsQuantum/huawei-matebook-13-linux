#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
e="$root/research/eval"
adapter="$e/gq_sigfm_fpeval.c"
builder="$e/build-gq-sigfm-fpeval.sh"
smoke="$e/test-gq-sigfm-fpeval.py"

grep -Fq 'return "gq-sigfm";' "$adapter"
grep -Fq 'gx_sift_extract' "$adapter"
grep -Fq 'gx_sift_match' "$adapter"
grep -Fq 'gx_sift_free' "$adapter"
grep -Fq 'goodix_sift.c' "$builder"
grep -Fq 'fastbrief/sigfm.c' "$builder"
grep -Fq 'GQ_SIGFM_FPEVAL_PLUGIN_TEST=PASS' "$smoke"

python3 - "$adapter" <<'PY'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
for symbol in ("fpeval_extract", "fpeval_score", "fpeval_free", "fpeval_name"):
    assert symbol in s, symbol
for forbidden in (
    "socket(", "connect(", "curl", "wget", "http://", "https://",
    "fopen(", "open(", "write(", "g_file_set_contents", "GX_DUMP_DIR",
):
    assert forbidden not in s, forbidden
PY

python3 "$smoke"
test ! -e "$e/gq_sigfm.so"

echo 'test_gq_sigfm_fpeval_source_safety: OK (real matcher ABI, synthetic smoke only)'
