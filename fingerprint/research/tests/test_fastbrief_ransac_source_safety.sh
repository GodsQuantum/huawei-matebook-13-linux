#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
driver="$root/driver/goodix51a0/goodix51a0.c"
wrapper="$root/driver/goodix51a0/goodix_sift.c"
matcher="$root/driver/goodix51a0/fastbrief/sigfm.c"
patch="$root/driver/goodix51a0/libfprint-v1.94.100.patch"
pkg="$root/packaging/arch/PKGBUILD"

grep -Fq '#define GX_TEMPLATE_VERSION 4u' "$driver"
grep -Fq '#define GX_MATCH_THRESHOLD            7' "$driver"
grep -Fq '#define GX_MIN_CAPTURE_KEYPOINTS     25' "$driver"
grep -Fq '#define GX_ENROLL_STAGES             20' "$driver"
grep -Fq '#define GX_VIEWS_PER_STAGE            1' "$driver"
! grep -Fq 'GX_ENROLL_COHERENCE_MIN' "$driver"
grep -Fq 'gx_sift_match (probe, g_ptr_array_index (views, i))' "$driver"
! grep -Fq 'GX_ADAPT_' "$driver"
! grep -Fq 'legacy unversioned template accepted' "$driver"

grep -Fq 'gx_unsharp4' "$wrapper"
grep -Fq 'sigfm_extract' "$wrapper"
grep -Fq 'sigfm_match_score' "$wrapper"
grep -Fq 'sigfm_serialize_binary' "$wrapper"
grep -Fq 'sigfm_deserialize_binary' "$wrapper"

grep -Fq '#define FAST_THRESHOLD 10' "$matcher"
grep -Fq '#define RATIO_TEST 0.80f' "$matcher"
grep -Fq '#define RANSAC_ITERATIONS 200' "$matcher"
grep -Fq '#define RANSAC_INLIER_THRESH 2.0f' "$matcher"
grep -Fq '#define SIGFM_VERSION 3u' "$matcher"

grep -Fq 'drivers/goodix51a0/fastbrief/sigfm.c' "$patch"
! grep -Fq 'drivers/goodix51a0/sigfm/sigfm.cpp' "$patch"
! grep -Fq "dependency('opencv5'" "$patch"
! grep -Fq "dependency('opencv4'" "$patch"
! grep -Eq "'opencv'([ )]|$)" "$pkg"

echo 'test_fastbrief_ransac_source_safety: OK'
