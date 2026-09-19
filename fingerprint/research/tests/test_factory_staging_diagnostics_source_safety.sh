#!/usr/bin/env bash
set -euo pipefail
base="$(cd "$(dirname "$0")/../.." && pwd)/driver/goodix51a0"
h="$base/gx51_factory_pmk.h"
c="$base/gx51_factory_pmk.c"
d="$base/goodix51a0.c"
grep -Fq 'enum gxfp_factory_staging_diag' "$h"
grep -Fq 'gxfp_factory_load_pmk_from_staging_diag' "$h"
grep -Fq 'GXFP_FACTORY_STAGING_PAIR_BODY_MISMATCH' "$c"
grep -Fq 'gxfp_factory_staging_diag_name' "$c"
! grep -Fq 'PMK staging diagnostic:' "$d"
! grep -Fq 'PMK=' "$d"
echo 'test_factory_staging_diagnostics_source_safety: OK'
