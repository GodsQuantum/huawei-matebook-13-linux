#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
driver="$root/driver/goodix51a0/goodix51a0.c"
block="$(sed -n '/^fpi_device_goodix51a0_finalize (/,/^}/p' "$driver")"
grep -Fq 'self->tls_up && self->tls' <<<"$block"
grep -Fq 'gx_transport_open (FP_DEVICE (self), &transport_error)' <<<"$block"
grep -Fq 'FINALIZE_TRACE reopened transport for warm TLS teardown' <<<"$block"
grep -Fq 'gx_warm_discard (self)' <<<"$block"
grep -Fq 'gx_transport_close (self)' <<<"$block"
echo 'test_finalize_warm_teardown_source_safety: OK'
