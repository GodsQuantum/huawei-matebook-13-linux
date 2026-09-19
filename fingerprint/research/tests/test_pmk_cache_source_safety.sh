#!/usr/bin/env bash
set -euo pipefail
driver="$(cd "$(dirname "$0")/../.." && pwd)/driver/goodix51a0/goodix51a0.c"
grep -Fq '#define GX_PMK_CACHE_FILE "/var/lib/fprint/.goodix51a0-pmk"' "$driver"
grep -Fq 'G_FILE_SET_CONTENTS_CONSISTENT | G_FILE_SET_CONTENTS_DURABLE' "$driver"
grep -Fq '0600' "$driver"
grep -Fq 'st.st_uid != geteuid ()' "$driver"
grep -Fq '(st.st_mode & 0077) != 0' "$driver"
grep -Fq 'len != GOODIX_PSK_LEN' "$driver"
grep -Fq 'PMK cache candidate loaded; TLS validation pending' "$driver"
grep -Fq 'PMK cache saved after live TLS validation' "$driver"
grep -Fq 'cached PMK retained after failed session' "$driver"
grep -Fq 'OPENSSL_cleanse (self->psk, sizeof self->psk)' "$driver"
if grep -Eq 'fp_(info|warn|dbg).*\b(self->psk|pmk|psk)\b' "$driver"; then
  echo 'safety violation: PMK/PSK buffer appears passed into logging' >&2
  exit 1
fi
echo 'test_pmk_cache_source_safety: OK'
