#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
out="${1:-$here/gq_sigfm.so}"

cc -O2 -fPIC -shared \
  -I"$root/driver/goodix51a0" \
  -I"$root/driver/goodix51a0/fastbrief" \
  "$here/gq_sigfm_fpeval.c" \
  "$root/driver/goodix51a0/goodix_sift.c" \
  "$root/driver/goodix51a0/fastbrief/sigfm.c" \
  $(pkg-config --cflags --libs glib-2.0) \
  -lm \
  -o "$out"

printf 'FPEVAL_PLUGIN=%s\n' "$out"
