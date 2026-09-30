#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
driver="$root/driver/goodix51a0/goodix51a0.c"
pkg="$root/packaging/arch/PKGBUILD"
install="$root/packaging/arch/libfprint-goodix51a0.install"

python3 - "$driver" "$pkg" "$install" <<'PY'
from pathlib import Path
import re,sys
driver,pkg,install=map(Path,sys.argv[1:])
s=driver.read_text()
p=pkg.read_text()
i=install.read_text()
def fn(n):
    m=re.search(r"\b"+re.escape(n)+r"\s*\([^;{}]*\)\s*\n\{",s); assert m,n
    b=s.find("{",m.end()-1); d=0
    for x in range(b,len(s)):
        d+=(s[x]=="{")-(s[x]=="}")
        if d==0: return s[m.start():x+1]
    raise AssertionError(n)
open_=fn("gx_dev_open"); close=fn("gx_dev_close"); suspend=fn("gx_dev_suspend"); resume=fn("gx_dev_resume")
assert "self->force_cold_reset = TRUE" in suspend
assert "fpi_device_suspend_complete (dev, NULL)" in suspend
assert "fpi_device_resume_complete (dev, NULL)" in resume
assert "g_cancellable_cancel" in resume
assert resume.index("fpi_device_resume_complete (dev, NULL)") < resume.index("g_cancellable_cancel")
assert "gx_sensor_sleep" not in close
assert "gxfp_build_sleep" not in close
assert "stashed native warm context across fp_device close" in close
assert "gx_warm_validate (self)" in open_
assert "sensor_sleeping" not in open_
assert "sensor_sleeping" not in close
assert "system-sleep" not in s
assert "pkgrel=69" in p
assert "systemctl enable gxfp51a0-boot-prewarm.service" in i
assert "systemctl restart fprintd.service" in i
assert "systemctl start gxfp51a0-boot-prewarm.service" in i
PY
echo 'test_sleep_lifecycle_source_safety: OK (rel69 warm stash + cold S3 boundary)'
