#!/usr/bin/env bash
set -euo pipefail
driver="$(cd "$(dirname "$0")/../.." && pwd)/driver/goodix51a0/goodix51a0.c"
fn="$(sed -n '/^gx_upload_config_and_reqtls (/,/^}/p' "$driver")"
grep -Fq 'gx_factory_acquire_staging_pmk (self, allow_cache)' <<<"$fn"
grep -Fq 'gx_gpio_reset (self)' <<<"$fn"
grep -Fq 'gx_read_fw_version_stage2e (self' <<<"$fn"
grep -Fq 'post-PMK reset' <<<"$fn"
python3 - "$driver" <<'PY2'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
a=s.index("gx_upload_config_and_reqtls (")
b=s.index("/* Establishes the TLS-PSK channel", a)
f=s[a:b]
load=f.index("gx_factory_acquire_staging_pmk (self, allow_cache)")
reset=f.index("gx_gpio_reset (self)", load)
a8=f.index("gx_read_fw_version_stage2e (self", reset)
cfg=f.index("gx_target_configure (self)", a8)
assert load < reset < a8 < cfg
PY2
echo 'test_post_pmk_reset_source_safety: OK'
