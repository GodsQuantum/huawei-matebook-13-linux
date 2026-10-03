#!/usr/bin/env bash
set -euo pipefail
driver="$(cd "$(dirname "$0")/../.." && pwd)/driver/goodix51a0/goodix51a0.c"
grep -Fq "#define GX_MCU_STATE_NO_REPLY_TIMEOUT_MS 120" "$driver"
grep -Fq "expected_plain_replies > 0 && body[0] != 0xaeu" "$driver"
grep -Fq "advisory response incomplete" "$driver"
grep -Fq "continuing without replay before image" "$driver"
python3 - "$driver" <<'PY2'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
d=s[s.index("gx_send_plain_drain ("):s.index("gx_bio_send", s.index("gx_send_plain_drain ("))]
assert "GX_MCU_STATE_NO_REPLY_TIMEOUT_MS / GX_DRAIN_IRQ_POLL_MS" in d
assert "expected_plain_replies > 0 && body[0] != 0xaeu" in d
ae=d.index("if (body[0] == 0xaeu)")
ret=d.index("return TRUE;", ae)
retry=d.index("if (attempt < attempts)", ret)
assert ae < ret < retry
PY2
echo "test_mcu_state_advisory_source_safety: OK"
