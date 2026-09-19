#!/usr/bin/env bash
set -euo pipefail
base="$(cd "$(dirname "$0")/../.." && pwd)/driver/goodix51a0"
transport="$base/gx51_transport.c"
header="$base/gx51_transport.h"
driver="$base/goodix51a0.c"
grep -Fq 'gx51_open_irq_gpio48' "$header"
grep -Fq 'gx51_wait_irq_gpio48' "$header"
grep -Fq 'GPIO_V2_LINE_FLAG_INPUT' "$transport"
grep -Fq 'GX51_EXPECTED_HWIRQ' "$transport"
grep -Fq 'GPIO_V2_LINE_GET_VALUES_IOCTL' "$transport"
grep -Fq 'gx51_sleep_us(1000)' "$transport"
grep -Fq 'gx51_open_irq_gpio48 ()' "$driver"
grep -Fq 'gx51_wait_irq_gpio48 (self->irq_fd, 1200)' "$driver"
! grep -Fq 'GX51_IRQ_DEV' "$driver"
! grep -Fq 'GX51_IRQ_WAIT' "$driver"
echo 'test_runtime_gpio48_poll_source_safety: OK'
