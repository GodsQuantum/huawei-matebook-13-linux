#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
d="$root/driver/goodix51a0/goodix51a0.c"

grep -Fq 'resume_bg_frame' "$d"
grep -Fq 'resume_bg_valid' "$d"
grep -Fq 'gx_resume_bootstrap_preserve' "$d"
grep -Fq 'gx_resume_bootstrap_clear' "$d"
grep -Fq 'GXFP51A0 RESUME_BOOTSTRAP finger already present' "$d"
grep -Fq 'using RAM-only pre-S3' "$d"
grep -Fq 'clean background for first authentication' "$d"

# Bootstrap must be armed only from actual suspend/S3 handling.
grep -A20 -F 'active S3 boundary detected during authentication' "$d" | grep -Fq 'gx_resume_bootstrap_preserve (self);'
grep -A22 -F 'GXFP51A0 suspend: preserving active authentication' "$d" >/dev/null || true
grep -B8 -F 'GXFP51A0 suspend: preserving active authentication' "$d" | grep -Fq 'gx_resume_bootstrap_preserve (self);'
grep -A18 -F 'if (slept || self->force_cold_reset)' "$d" | grep -Fq 'if (slept && !self->resume_bg_valid)'
grep -A18 -F 'if (slept || self->force_cold_reset)' "$d" | grep -Fq 'gx_resume_bootstrap_preserve (self);'

# TLS session is still established before any bootstrap decision.
python3 - "$d" <<'PY'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
fn=s[s.index("gx_prepare_capture_context_once"):s.index("#define GX_PREPARE_ATTEMPTS")]
assert fn.index("gx_tls_session (self)") < fn.index("self->resume_bg_valid")
assert fn.index("gx51_wait_irq_gpio48_low") < fn.index("self->resume_bg_valid")
assert "gx_fdt_probe_ex (self, cur, &touchflag)" in fn
assert "gx_fdt_touch_is_finger (touchflag) || mean < GOODIX_FDT_ABS" in fn
assert "return TRUE;" in fn[fn.index("GXFP51A0 RESUME_BOOTSTRAP"):]

pres_start=s.index("static gboolean\ngx_resume_bootstrap_preserve")
pres=s[pres_start:s.index("static void\ngx_warm_abandon", pres_start)]
assert "self->warm_valid" in pres
assert "self->bg_frame" in pres
assert "self->have_fdt" in pres
assert "self->bg_dirty" in pres
assert "memcpy (self->resume_bg_frame, self->bg_frame" in pres

clear_start=s.index("static void\ngx_resume_bootstrap_clear")
clear=s[clear_start:s.index("static gboolean\ngx_resume_bootstrap_preserve", clear_start)]
assert "OPENSSL_cleanse" in clear
assert "g_clear_pointer (&self->resume_bg_frame, g_free)" in clear
PY

# No resume background may be persisted to disk.
! grep -E 'resume_bg.*(file|path|write|set_contents)|GXFP.*RESUME.*FILE' "$d"
! grep -R -E 'resume_bg_frame.*(/var|/run|fopen|write\()' "$root" --exclude='test_resume_held_finger_bootstrap_source_safety.sh'

echo 'test_resume_held_finger_bootstrap_source_safety: OK'
