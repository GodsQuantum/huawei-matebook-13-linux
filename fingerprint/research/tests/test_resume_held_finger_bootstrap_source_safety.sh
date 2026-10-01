#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
d="$root/driver/goodix51a0/goodix51a0.c"

# rel58 intentionally returns to the human-validated rel50 driver core.
# Do not retain a pre-S3 image background across power loss: earlier project
# measurements showed old backgrounds can collapse genuine scores into 2-4.
! grep -Fq 'resume_bg_frame' "$d"
! grep -Fq 'resume_bg_valid' "$d"
! grep -Fq 'gx_resume_bootstrap_preserve' "$d"
! grep -Fq 'gx_resume_bootstrap_clear' "$d"
! grep -Fq 'RESUME_BOOTSTRAP' "$d"

# Resume remains native and deterministic: an idle S3 is detected at the next
# Claim; an active S3 marks the session cold and lets libfprint cancel it.
grep -Fq 'gx_warm_crossed_sleep' "$d"
grep -Fq 'active S3 boundary detected during authentication' "$d"
grep -Fq 'FP_DEVICE_ERROR_NOT_SUPPORTED' "$d"
grep -Fq 'self->force_cold_reset = TRUE' "$d"

echo 'test_resume_held_finger_bootstrap_source_safety: OK (stale background bootstrap absent)'
