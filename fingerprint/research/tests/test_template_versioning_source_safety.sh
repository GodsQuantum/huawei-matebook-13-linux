#!/usr/bin/env bash
set -euo pipefail
driver="$(cd "$(dirname "$0")/../.." && pwd)/driver/goodix51a0/goodix51a0.c"
grep -Fq '#define GX_TEMPLATE_VERSION 1u' "$driver"
grep -Fq 'G_VARIANT_TYPE ("(uaay)")' "$driver"
grep -Fq 'g_variant_new ("(u@aay)"' "$driver"
grep -Fq 'unsupported template version' "$driver"
grep -Fq 'legacy unversioned template accepted' "$driver"
echo 'test_template_versioning_source_safety: OK'
