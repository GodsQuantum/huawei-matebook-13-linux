#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
driver="$root/driver/goodix51a0/goodix51a0.c"
target="$root/driver/goodix51a0/gx51_target.c"
header="$root/driver/goodix51a0/gx51_target.h"

python3 - "$driver" "$target" "$header" <<'PY2'
from pathlib import Path
import sys

s=Path(sys.argv[1]).read_text()
t=Path(sys.argv[2]).read_text()
h=Path(sys.argv[3]).read_text()

def fn(src, name):
    pos = 0
    while True:
        start = src.find(name, pos)
        assert start >= 0, name
        line_start = src.rfind("\n", 0, start) + 1
        line_end = src.find("\n", start)
        line = src[line_start:line_end if line_end >= 0 else len(src)].lstrip()
        brace = src.find("{", start)
        semi = src.find(";", start)
        if name in line and not line.startswith("*") and not line.startswith("//"):
            if brace >= 0 and (semi < 0 or brace < semi):
                start = line_start
                break
        pos = start + len(name)
    depth = 0
    for i in range(brace, len(src)):
        if src[i] == "{":
            depth += 1
        elif src[i] == "}":
            depth -= 1
            if depth == 0:
                return src[start:i+1]
    raise AssertionError(name)

build=fn(t,"gxfp_build_sleep")
sleep=fn(s,"gx_sensor_sleep")
wake=fn(s,"gx_wakeup_mcu")
open_=fn(s,"gx_dev_open")
close=fn(s,"gx_dev_close")
suspend=fn(s,"gx_dev_suspend")
abandon=fn(s,"gx_warm_abandon")
init=fn(s,"fpi_device_goodix51a0_init")

assert "build_payload_command(0x60u, payload, sizeof payload, packet)" in build
assert "0x01u, 0x00u" in build
assert "gxfp_build_sleep" in h
assert "GOODIX_CMD_SLEEP" in s

assert "gxfp_build_sleep (&packet)" in sleep
assert "gx_target_send_ack (self, &packet, GOODIX_CMD_SLEEP, NULL)" in sleep
assert sleep.index("gx_target_send_ack") < sleep.index("sensor_sleeping = TRUE")

assert "gx_sensor_sleep (self)" in close
assert close.index("gx_sensor_sleep (self)") < close.index("gx_transport_close (self)")
assert "close sleep transition failed; discarding warm context" in close
assert "stashed native warm context with sensor in" in close

assert "self->sensor_sleeping && !gx_wakeup_mcu (self)" in open_
assert open_.index("gx_wakeup_mcu (self)") < open_.index("gx_warm_validate (self)")
assert "self->sensor_sleeping = FALSE" in wake

assert "gx_sensor_sleep (self)" in suspend
assert suspend.index("gx_sensor_sleep (self)") < suspend.index("self->force_cold_reset = TRUE")
assert "suspend sleep transition failed; cold resume " in suspend
assert "recovery remains armed" in suspend

assert "self->sensor_sleeping = FALSE" in abandon
assert "self->sensor_sleeping = FALSE" in init
PY2

echo 'test_sleep_lifecycle_source_safety: OK'
