#!/usr/bin/env bash
set -euo pipefail
driver="$(cd "$(dirname "$0")/../.." && pwd)/driver/goodix51a0/goodix51a0.c"
grep -Fq '#define GX_IMAGE_READOUT_SETTLE_US 80000' "$driver"
grep -Fq '#define GX_IRQ_HIGH_EMPTY_BACKOFF_US 3000' "$driver"
grep -Fq 'GET_IMAGE ACK; SPI quiet' "$driver"
python3 - "$driver" <<'PY2'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
d=s[s.index("gx_send_plain_drain ("):s.index("gx_bio_send", s.index("gx_send_plain_drain ("))]
assert "body[0] == 0x20u && ack_seen" in d
quiet=d.index("GX_IMAGE_READOUT_SETTLE_US")
assert quiet < d.index("if (body[0] != 0x20u)")
assert "GX_IRQ_HIGH_EMPTY_BACKOFF_US" in d
recv=s[s.index("gx_bio_recv ("):s.index("gx_target_read_body", s.index("gx_bio_recv ("))]
assert "GX_IRQ_HIGH_EMPTY_BACKOFF_US" in recv
take=s[s.index("gx_take_tls_frame ("):s.index("gx_fail_get_image_after_tls_timeout", s.index("gx_take_tls_frame ("))]
assert "GX_IRQ_HIGH_EMPTY_BACKOFF_US" in take
# Accepted-command safety remains mandatory.
assert "not replaying accepted command" in s
PY2
echo 'test_image_readout_quiet_source_safety: OK'
