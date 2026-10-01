#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
driver="$root/driver/goodix51a0/goodix51a0.c"
defs="$root/driver/goodix51a0/goodix51a0.h"
target="$root/driver/goodix51a0/gx51_target.c"
header="$root/driver/goodix51a0/gx51_target.h"

# The functional rel61 driver deliberately has no in-driver 0x60 sleep command.
# The S3 boundary is handled above libfprint: stop fprintd before sleep and start
# a fresh daemon after resume. This is now the tested lifecycle contract.
! grep -Fq '#define GOODIX_CMD_SLEEP' "$defs"
! grep -Fq 'gxfp_build_sleep' "$target"
! grep -Fq 'gx_sensor_sleep' "$driver"

# Keep the rel61 driver semantics: suspend invalidates the context and asks
# libfprint to cancel the active action; resume completes the PM transition.
grep -Fq 'self->force_cold_reset = TRUE' "$driver"
grep -Fq 'fpi_device_suspend_complete (' "$driver"
grep -Fq 'FP_DEVICE_ERROR_NOT_SUPPORTED' "$driver"
grep -Fq 'fpi_device_resume_complete (dev, NULL)' "$driver"

# Do not add a legacy system-sleep script: systemd's sleep.target ordering is the
# userspace daemon boundary used by the rel70/71 reconstruction.

# The daemon boundary is deliberate: stop fprintd before sleep, start it after resume.
sleep_unit="$root/integration/systemd/gxfp51a0-fprintd-suspend.service"
test -f "$sleep_unit"
grep -Fq 'Before=sleep.target' "$sleep_unit"
grep -Fq 'StopWhenUnneeded=yes' "$sleep_unit"
grep -Fq 'RemainAfterExit=yes' "$sleep_unit"
grep -Fq 'ExecStart=/usr/bin/systemctl stop fprintd.service' "$sleep_unit"
grep -Fq 'ExecStop=/usr/bin/systemctl start fprintd.service' "$sleep_unit"

echo 'test_sleep_lifecycle_source_safety: OK (rel61 driver + fprintd sleep boundary)'
