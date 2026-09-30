#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
driver="$root/driver/goodix51a0/goodix51a0.c"
defs="$root/driver/goodix51a0/goodix51a0.h"
target="$root/driver/goodix51a0/gx51_target.c"
header="$root/driver/goodix51a0/gx51_target.h"

# rel67 preserves rel66's Windows ReqOnActivate(false) lifecycle and adds only
# a bounded IRQ-low quiesce before command 0x60, matching Windows' pending-request settle.
grep -Fq '#define GOODIX_CMD_SLEEP       0x60' "$defs"
grep -Fq 'gxfp_build_sleep' "$target"
grep -Fq 'static const uint8_t payload[] = {0x01u, 0x00u};' "$target"
grep -Fq 'gxfp_build_sleep' "$header"
grep -Fq 'gx_sensor_sleep' "$driver"
grep -Fq 'Windows deactivate SLEEP 0x60/01 00 acknowledged' "$driver"

python3 - "$driver" <<'PY'
from pathlib import Path
import re,sys
s=Path(sys.argv[1]).read_text()
def fn(n):
 m=re.search(r"\b"+re.escape(n)+r"\s*\([^;{}]*\)\s*\n\{",s); assert m,n
 b=s.find("{",m.end()-1); d=0
 for i in range(b,len(s)):
  d += (s[i]=="{")-(s[i]=="}")
  if d==0: return s[m.start():i+1]
 raise AssertionError(n)
close=fn("gx_dev_close")
open_=fn("gx_dev_open")
sleep=fn("gx_sensor_sleep")
suspend=fn("gx_dev_suspend")
abandon=fn("gx_warm_abandon")
wake=fn("gx_wakeup_mcu")

assert "gxfp_build_sleep (&packet)" in sleep
assert "gx51_wait_irq_gpio48_low (self->irq_fd, GX_SLEEP_QUIESCE_MS)" in sleep
assert "GX_SLEEP_QUIESCE_MS          400" in s
assert sleep.index("gx51_wait_irq_gpio48_low") < sleep.index("gx_target_send_ack (self, &packet, GOODIX_CMD_SLEEP, NULL)")
assert "REL67_TRACE deactivate SLEEP skipped" in sleep
assert "gx_target_send_ack (self, &packet, GOODIX_CMD_SLEEP, NULL)" in sleep
assert "self->sensor_sleeping = TRUE" in sleep
assert "gx_sensor_sleep (self)" in close
assert close.index("gx_sensor_sleep (self)") < close.index("gx_transport_close (self)")
assert "refusing to stash active MCU context" in close
assert "self->sensor_sleeping && !gx_wakeup_mcu (self)" in open_
assert open_.index("gx_wakeup_mcu (self)") < open_.index("gx_warm_validate (self)")
assert "self->sensor_sleeping = FALSE" in wake
assert "self->sensor_sleeping = FALSE" in abandon

# Do not turn this into an external S3 hook or an in-suspend protocol experiment.
assert "gx_sensor_sleep (self)" not in suspend
assert "system-sleep" not in s
PY

echo 'test_sleep_lifecycle_source_safety: OK (Windows deactivate sleep + wake)'
