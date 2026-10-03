#!/usr/bin/env bash
set -euo pipefail
driver="$(cd "$(dirname "$0")/../.." && pwd)/driver/goodix51a0/goodix51a0.c"
grep -Fq '#define GX_TARGET_ACK_IRQ_TIMEOUT_MS 1000' "$driver"
grep -Fq '#define GX_FDT_IRQ_TIMEOUT_MS 1000' "$driver"
grep -Fq '#define GX_DRAIN_NO_REPLY_TIMEOUT_MS 1000' "$driver"
grep -Fq 'official-policy whole-command retry' "$driver"
python3 - "$driver" <<'PY2'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
d=s[s.index("gx_send_plain_drain ("):s.index("gx_bio_send", s.index("gx_send_plain_drain ("))]
assert "expected_plain_replies > 0" in d
assert "attempts = 2" in d
assert "required response count" in d
assert "GX_DRAIN_NO_REPLY_TIMEOUT_MS / GX_DRAIN_IRQ_POLL_MS" in d
a=s[s.index("gx_target_send_ack ("):s.index("gx_sensor_sleep", s.index("gx_target_send_ack ("))]
assert "GX_TARGET_ACK_IRQ_TIMEOUT_MS" in a
assert "g_usleep (1000);" in a
PY2
echo 'test_windows_transport_parity_source_safety: OK'
