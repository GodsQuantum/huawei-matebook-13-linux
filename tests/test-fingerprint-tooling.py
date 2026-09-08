#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
FP = ROOT / "fingerprint"
SCRIPTS = FP / "scripts"

def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)

build = (SCRIPTS / "build-libfprint-v1.94.100.sh").read_text(encoding="utf-8")
verify = (SCRIPTS / "verify-software-baseline.sh").read_text(encoding="utf-8")
passive = (SCRIPTS / "passive-linux-observability.sh").read_text(encoding="utf-8")
makefile = (FP / "Makefile").read_text(encoding="utf-8")
readme = (FP / "README.md").read_text(encoding="utf-8")

require('LIBFPRINT_TAG="v1.94.100"' in build, "libfprint tag drift")
require('MESON_VERSION="1.12.0"' in build, "Meson version drift")
require('NINJA_VERSION="1.13.2"' in build, "Ninja version drift")
require("-Ddrivers=goodix51a0" in build, "driver selection missing")
require("-Dintrospection=false" in build, "introspection gate missing")
require("-Ddoc=false" in build, "doc gate missing")
require("-Dinstalled-tests=false" in build, "installed-tests gate missing")
require("sha256sum -c SOURCE_MANIFEST.sha256" in build, "source manifest gate missing")
require("git -C \"$SRC_DIR\" apply --check" in build, "patch preflight missing")
require("fpi_device_goodix51a0_get_type" in build, "type-symbol artifact gate missing")
require("GXFP51A0" in build, "driver string artifact gate missing")
require(
    re.search(r'nm\s+"\$archive"\s*\|\s*grep\s+[^\n]*-q', build) is None,
    "pipefail-unsafe nm|grep -q artifact gate reintroduced",
)
require(
    re.search(r'strings\s+"\$archive"\s*\|\s*grep\s+[^\n]*-q', build) is None,
    "pipefail-unsafe strings|grep -q artifact gate reintroduced",
)
require('nm "$driver_obj" >"$object_nm_dump"' in build, "object nm gate missing")
require('strings "$driver_obj" >"$object_strings_dump"' in build, "object strings gate missing")
require('nm "$archive" >"$archive_nm_dump"' in build, "archive nm gate missing")
require('ar t "$archive" >"$archive_members_dump"' in build, "archive membership gate missing")
require('strings "$archive"' not in build, "archive-level strings gate must not be used")
require("GOODIX51A0_ACPI_ID_IN_OBJECT=YES" in build, "compiled-object ACPI-ID success marker missing")
require("GOODIX51A0_OBJECT_IN_DRIVER_ARCHIVE=YES" in build, "archive-membership success marker missing")

require("test-goodix51a0-first-contact.py" in verify, "first-contact regression missing")
require('make -C "$FP_DIR/research" test' in verify, "research suite missing")
require('"$SCRIPT_DIR/build-libfprint-v1.94.100.sh"' in verify, "build delegation missing")

dangerous = (
    r"/sys/.*/(?:bind|unbind)",
    r"\bmodprobe\b",
    r"\brmmod\b",
    r"SPI_IOC_MESSAGE",
    r"gpiod_line_request_output",
    r"\bgpioset\b",
)
for pattern in dangerous:
    require(re.search(pattern, passive) is None, f"passive script contains active token: {pattern}")

for marker in (
    "ACTIVE_SENSOR_IO=NONE",
    "GPIO_WRITES=NONE",
    "MMIO_WRITES=NONE",
    "FIRMWARE_ACTIONS=NONE",
):
    require(marker in passive, f"passive safety marker missing: {marker}")

for target in ("verify:", "build:", "research:", "passive-audit:"):
    require(target in makefile, f"Makefile target missing: {target}")

require("make -C fingerprint verify" in readme, "README one-shot command missing")
require("HANDOFF_CURRENT.md" in readme, "README current handoff link missing")

print("FINGERPRINT_TOOLING_TEST=PASS")
