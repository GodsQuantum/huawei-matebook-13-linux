#!/usr/bin/env bash
set -euo pipefail
base="$(cd "$(dirname "$0")/../.." && pwd)/driver/goodix51a0"
h="$base/gx51_transport.h"
c="$base/gx51_transport.c"
d="$base/goodix51a0.c"
grep -Fq 'gx51_wait_irq_gpio48_low' "$h"
grep -Fq 'gx51_wait_irq_gpio48_low' "$c"
grep -Fq 'gx51_wait_irq_gpio48_low (self->irq_fd, 50)' "$d"
grep -Fq 'target ACK diagnostic: pre-write-irq-high' "$d"
grep -Fq 'target ACK diagnostic: ack-read-failed' "$d"
grep -Fq 'target ACK diagnostic: ack-parse-failed' "$d"
grep -Fq 'target ACK diagnostic: status-failed' "$d"
echo 'test_target_irq_quiesce_source_safety: OK'
