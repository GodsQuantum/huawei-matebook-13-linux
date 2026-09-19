#!/usr/bin/env bash
set -euo pipefail
base="$(cd "$(dirname "$0")/../.." && pwd)/driver/goodix51a0"
grep -Fq 'gxfp_factory_load_pmk_from_single_staging' "$base/gx51_factory_pmk.h"
grep -Fq 'gxfp_factory_load_pmk_from_single_staging' "$base/gx51_factory_pmk.c"
grep -Fq 'gxfp_factory_load_pmk_from_single_staging (' "$base/goodix51a0.c"
grep -Fq 'TLS validation pending' "$base/goodix51a0.c"
grep -Fq 'gxfp_factory_pmk_recover_first_byte' "$base/gx51_factory_pmk.c"
echo 'test_single_staging_runtime_source_safety: OK'
