#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
d="$root/driver/goodix51a0/goodix51a0.c"

grep -Fq 'static const guint8 wake[4] = { 0x0f, 0x00, 0x00, 0x0e };' "$d"
grep -Fq 'g_usleep (5000);' "$d"
grep -Fq 'AUTH_TRACE WakeupMCU raw SPI write complete' "$d"

session="$(sed -n '/^gx_session_start (/,/^}/p' "$d")"
grep -Fq 'return gx_wakeup_mcu (self);' <<<"$session"

grep -Fq 'GPtrArray      *identify_gallery' "$d"
grep -Fq 'fpi_device_get_identify_data (dev, &gallery)' "$d"
grep -Fq 'gx_capture_auth_same_press' "$d"
grep -Fq 'gx_score_probe_against_gallery' "$d"
grep -Fq 'mode=%s same-press image %u/%u ' "$d"
grep -Fq 't->identifying ? "IDENTIFY" : "VERIFY"' "$d"

grep -Eq '^#define GX_MATCH_THRESHOLD[[:space:]]+7$' "$d"
grep -Eq '^#define GX_SAME_PRESS_CAPTURE_ATTEMPTS[[:space:]]+3' "$d"
echo 'test_windows_wakeup_identify_same_press_source_safety: OK'
