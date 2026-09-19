#!/usr/bin/env bash
set -euo pipefail
driver="$(cd "$(dirname "$0")/../.." && pwd)/driver/goodix51a0/goodix51a0.c"
grep -Fq '#define GX_GET_IMAGE_ATTEMPTS 2' "$driver"
grep -Fq 'GET_IMAGE had no ACK/TLS; retrying' "$driver"
grep -Fq 'gxfp_parse_ack (scratch, r, body[0], &ack_status)' "$driver"
python3 - "$driver" <<'PY2'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
a=s.index("gx_send_plain_drain (")
b=s.index("gx_bio_send", a)
f=s[a:b]
assert "gboolean *out_ack_seen" in f
assert "gboolean *out_tls_seen" in f
assert "*out_tls_seen = TRUE" in f
assert "*out_ack_seen = TRUE" in f
# Retry is centralized inside the drain transport, so it covers both the
# main capture GET_IMAGE and the cleanup GET_IMAGE.
assert "GX_GET_IMAGE_ATTEMPTS" in f
assert "body[0] == 0x20u" in f
assert "if (tls_seen || ack_seen)" in f
assert "GET_IMAGE had no ACK/TLS; retrying" in f
assert "attempts = body[0] == 0x20u ? GX_GET_IMAGE_ATTEMPTS : 1" in f
PY2
echo 'test_get_image_retry_source_safety: OK'
