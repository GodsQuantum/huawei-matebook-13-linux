#!/usr/bin/env bash
set -euo pipefail
driver="$(cd "$(dirname "$0")/../.." && pwd)/driver/goodix51a0/goodix51a0.c"
grep -Fq 'gx_factory_acquire_staging_pmk' "$driver"
grep -Fq 'GXFP_PMK_ACQUIRE_ATTEMPTS' "$driver"
grep -Fq 'PMK staging attempt' "$driver"
grep -Fq 'PMK single-staging candidate invalid' "$driver"
grep -Fq 'E4 sanity failed' "$driver"
python3 - "$driver" <<'PY2'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
a=s.index("gx_factory_acquire_staging_pmk (")
b=s.index("gx_target_soft_reset (", a)
f=s[a:b]
assert "for (attempt = 1;" in f
assert "gx_gpio_reset (self)" in f
assert "gx_factory_load_staging_pmk (self)" in f
assert f.index("gx_gpio_reset (self)") < f.index("gx_factory_load_staging_pmk (self)")
PY2
echo 'test_pmk_retry_source_safety: OK'
