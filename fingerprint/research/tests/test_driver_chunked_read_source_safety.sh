#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
driver="$root/driver/goodix51a0/goodix51a0.c"
transport="$root/driver/goodix51a0/gx51_transport.c"

grep -q 'gx51_read_chunk_size' "$driver"
grep -q 'gx51_read_chunk_size' "$transport"
read_fn="$(sed -n '/^gx_read_frame (/,/^}/p' "$driver")"
grep -q 'gx51_read_chunk_size' <<<"$read_fn"
if grep -Fq 'xfer.len = n;' <<<"$read_fn"; then
  echo 'safety violation: runtime RX still reads a whole variable-length frame body in one SPI transfer' >&2
  exit 1
fi
echo 'test_driver_chunked_read_source_safety: OK'
