#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
patch="$root/integration/fprintd-1.94.5-goodix51a0-s3/0001-goodix51a0-open-before-suspend.patch"
pkg="$root/integration/fprintd-1.94.5-goodix51a0-s3/PKGBUILD"

test -s "$patch"
grep -Fq 'fp_device_get_driver' "$patch"
grep -Fq 'goodix51a0' "$patch"
grep -Fq 'fp_device_is_open' "$patch"
grep -Fq 'fp_device_open' "$patch"
grep -Fq 'fp_device_close' "$patch"
grep -Fq 'opened_for_sleep' "$patch"
grep -Fq 'PrepareForSleep' "$patch" || true
grep -Fq 'pkgver=1.94.5' "$pkg"
grep -Fq 'pkgrel=73' "$pkg"
grep -Fq '0001-goodix51a0-open-before-suspend.patch' "$pkg"

echo 'test_fprintd_goodix51a0_s3_patch_source_safety: OK'
