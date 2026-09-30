#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
driver="$root/driver/goodix51a0/goodix51a0.c"
defs="$root/driver/goodix51a0/goodix51a0.h"
target="$root/driver/goodix51a0/gx51_target.c"
header="$root/driver/goodix51a0/gx51_target.h"

# rel66 mirrors the same-device Windows ReqOnActivate(false) lifecycle:
# command 0x60, payload 01 00, ACK required before an idle close.
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
assert "gx_target_send_ack (self, &packet, GOODIX_CMD_SLEEP, NULL)" in sleep
assert "self->sensor_sleeping = TRUE" in sleep
assert "gx_sensor_sleep (self)" in close
assert close.index("gx_sensor_sleep (self)") < close.index("gx_transport_close (self)")
assert "refusing to stash active MCU context" in close
assert "self->sensor_sleeping && !gx_wakeup_mcu (self)" in open_
assert open_.index("gx_wakeup_mcu (self)") < open_.index("gx_warm_validate (self)")
assert "self->sensor_sleeping = FALSE" in wake
assert "self->sensor_sleeping = FALSE" in abandon

# Do not add a legacy system-sleep script: systemd's sleep.target ordering is the supported boundary.
assert "system-sleep" not in s
PY

# The daemon boundary is deliberate: stop fprintd before sleep, start it after resume.
sleep_unit="$root/integration/systemd/gxfp51a0-fprintd-suspend.service"
test -f "$sleep_unit"
grep -Fq 'Before=sleep.target' "$sleep_unit"
grep -Fq 'StopWhenUnneeded=yes' "$sleep_unit"
grep -Fq 'RemainAfterExit=yes' "$sleep_unit"
grep -Fq 'ExecStart=/usr/bin/systemctl stop fprintd.service' "$sleep_unit"
grep -Fq 'ExecStop=/usr/bin/systemctl start fprintd.service' "$sleep_unit"

echo 'test_sleep_lifecycle_source_safety: OK (Windows deactivate sleep + daemon boundary)'
