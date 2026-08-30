#!/bin/sh
set -eu

research_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
reset="$research_dir/linux/gpiod_reset.c"
runtime="$research_dir/linux/probe_runtime.c"
core="$research_dir/probe_harness.c"
packet="$research_dir/milan_packet.c"

# GPIO264 must be requested without direction/pin configuration changes.
grep -q 'GPIOD_LINE_DIRECTION_AS_IS' "$reset"
grep -q 'gpiod_line_info_get_direction(info) != GPIOD_LINE_DIRECTION_OUTPUT' "$reset"
if tr '\n' ' ' < "$reset" | grep -Eq 'gpiod_line_settings_set_direction[^;]*GPIOD_LINE_DIRECTION_OUTPUT'; then
    echo 'safety violation: reset adapter requests OUTPUT direction' >&2
    exit 1
fi
if grep -Eq 'set_edge_detection|GPIOD_LINE_EDGE_(RISING|FALLING|BOTH)|reconfigure' "$reset"; then
    echo 'safety violation: reset adapter changes edge/configuration' >&2
    exit 1
fi

# The only mutable reset operation is the already-output line value.
grep -q 'gpiod_line_request_set_value' "$reset"

# Experiment payload remains the explicitly labelled deterministic fixture.
grep -q 'static const uint8_t a4_payload\[2\] = {0x00, 0x00}' "$runtime"
grep -q 'A4_PAYLOAD_FIXTURE=00 00' "$runtime"
grep -q 'INITIAL_RESET=NO' "$runtime"
grep -q 'DRIVERSTATE_ACK_TARGET=96' "$runtime"
grep -q 'DRIVERSTATE_RESULT=' "$runtime"
grep -q 'DRIVERSTATE_RESET_PERFORMED=' "$runtime"

# DriverState uses ACK(9,3) at the effective 1000 ms minimum; old fixed 100 ms sleeps are forbidden.
grep -q 'GXFP_DRIVERSTATE_ACK_TIMEOUT_MS 1000u' "$core"
if grep -q 'GXFP_PREAMBLE_INSTALL_WAIT_MS' "$core"; then
    echo 'safety violation: obsolete fixed DriverState wait remains' >&2
    exit 1
fi

# Fixed DriverState vector only; no generic command encoder or firmware flow.
grep -q '0x96, 0x03, 0x00, 0x01, 0x00, 0x10' "$packet"
if grep -Eqi 'UPFW|erase_firmware|update_firmware|firmware_write|bootloader|ProductionErase|ProductionUpdate' \
    "$reset" "$runtime" "$core" "$packet"; then
    echo 'safety violation: firmware-management primitive found' >&2
    exit 1
fi

# Signal handler must only request cancellation; cleanup happens in normal flow.
grep -q 'g_cancelled = 1' "$runtime"
grep -q 'cleanup = gxfp_probe_restore_reset(reset)' "$core"
if grep -q 'GXFP_PROBE_INITIAL_RESET_ERROR' "$core"; then
    echo 'safety violation: initial reset path remains in probe core' >&2
    exit 1
fi

echo 'test_probe_runtime_source_safety: OK'
