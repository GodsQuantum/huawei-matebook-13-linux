#!/bin/sh
set -eu

research_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
src="$research_dir/../driver/goodix51a0/goodix51a0.c"

test -f "$src"
grep -q 'gxfp_factory_load_pmk_from_single_staging' "$src"
grep -q 'gxfp_14115_parse_rejected_staging_response' "$src"
grep -q 'GXFP_FACTORY_STAGING_LEN' "$src"

if grep -q 'gxfp_factory_load_pmk *(gx_factory_mem_read_cb' "$src"; then
    echo 'safety violation: runtime still treats private F2 as a PMK memory read' >&2
    exit 1
fi

python3 - "$src" <<'PY'
import pathlib, sys
s = pathlib.Path(sys.argv[1]).read_text()
start = s.index("gx_upload_config_and_reqtls (")
end = s.index("/* Establishes the TLS-PSK channel", start)
fn = s[start:end]
assert "gx_factory_acquire_staging_pmk (self, allow_cache)" in fn
assert "gx_gpio_reset (self);" in fn
assert fn.index("gx_factory_acquire_staging_pmk (self, allow_cache)") < fn.index("gx_gpio_reset (self);")
assert "GX_REQTLS" in fn

a = s.index("gx_factory_load_staging_pmk (")
b = s.index("gx_factory_acquire_staging_pmk (", a)
load = s[a:b]
assert load.index("gxfp_factory_load_pmk_from_single_staging") < load.index("gx_factory_e4_sanity")
PY

echo 'test_driver_staging_source_safety: OK'
