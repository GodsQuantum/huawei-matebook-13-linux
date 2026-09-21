#!/usr/bin/env python3
from pathlib import Path
import fnmatch
import re

ROOT = Path(__file__).resolve().parents[1]
PATCH = ROOT / "fingerprint/driver/goodix51a0/libfprint-v1.94.100.patch"
DRIVER = ROOT / "fingerprint/driver/goodix51a0/goodix51a0.c"
ARCH = ROOT / "fingerprint/install-arch.sh"
LINUX = ROOT / "fingerprint/install-linux.sh"
UNINSTALL = ROOT / "fingerprint/uninstall-linux-source.sh"
BUILD = ROOT / "fingerprint/scripts/build-libfprint-v1.94.100.sh"
PKGBUILD = ROOT / "fingerprint/packaging/arch/PKGBUILD"
PKGINSTALL = ROOT / "fingerprint/packaging/arch/libfprint-goodix51a0.install"
DROPIN = ROOT / "fingerprint/packaging/arch/fprintd-goodix51a0.conf"

actual = "acpi:GXFP51A0:GXFP51A0:"
legacy = "acpi:GXFP51A0:"
pattern = "acpi:GXFP51A0:*"
assert fnmatch.fnmatchcase(actual, pattern)
assert fnmatch.fnmatchcase(legacy, pattern)

patch = PATCH.read_text()
plus = "\n".join(
    line[1:] for line in patch.splitlines()
    if line.startswith("+") and not line.startswith("+++")
)
assert 'ENV{MODALIAS}==\\"acpi:%s:*\\"' in plus
assert "test -L %%S%%p/driver || echo %%k > %%S%%p/subsystem/drivers/spidev/bind" in plus

build = BUILD.read_text()
assert "GOODIX51A0_UDEV_MODALIAS_GLOB=PASS" in build
assert 'ENV{MODALIAS}=="acpi:GXFP51A0:*"' in build

driver = DRIVER.read_text()
assert "FPI_DEVICE_UDEV_SUBTYPE_SPIDEV" in driver
assert '.spi_acpi_id = "GXFP51A0"' in driver
assert "dev_class->probe = gx_dev_probe;" in driver
assert "fpi_device_probe_complete (dev, NULL, NULL, NULL);" in driver
assert "historical libfprint device ID" in driver
assert "GX_WARM_TTL_US" not in driver
assert "gx_warm_validate" in driver
assert "native prewarm completed during libfprint probe" in driver
assert "#define GX_PROBE_PREWARM_ATTEMPTS 1" in driver
assert "probe prewarm attempt %d/%d failed" in driver
assert "gx_prepare_capture_context_once (self, FALSE)" in driver
assert "gx51_wait_irq_gpio48_low (self->irq_fd, 250)" in driver
assert "first background capture must not race the tail of the TLS handshake" in driver
assert "deferring bounded recovery to the biometric action" in driver
assert "probe() is an enumeration-time optimization" in driver
assert "falling back to cold preparation" in driver
assert "reset_before_cold" not in driver
assert "warm_expire" not in driver
assert re.search(r"^#define\s+GX_MATCH_THRESHOLD\s+7\s*$", driver, re.M)
assert re.search(r"^#define\s+GX_VERIFY_MAX_ATTEMPTS\s+3\b", driver, re.M)
assert "GPIO112" not in driver
assert "GPP_D16" not in driver

dropin = DROPIN.read_text()
assert "After=systemd-udev-trigger.service" in dropin
assert "Before=display-manager.service" not in dropin
assert "ExecStart=/usr/lib/fprintd --no-timeout" in dropin
assert "TimeoutStartSec=40s" in dropin
assert "DeviceAllow=char-gpiochip rw" in dropin
assert "LimitCORE=0" in dropin
assert "gxfp51a0-spidev-bind" not in dropin

pkgbuild = PKGBUILD.read_text()
pkginstall = PKGINSTALL.read_text()
assert "pkgrel=24" in pkgbuild
assert "install=libfprint-goodix51a0.install" in pkgbuild
assert "graphical.target.wants/fprintd.service" in pkgbuild
assert "gxfp51a0-spidev-bind" not in pkgbuild
assert "udevadm control --reload" in pkginstall
assert "udevadm trigger --subsystem-match=spi" in pkginstall
assert "systemctl restart --no-block fprintd.service" in pkginstall

arch = ARCH.read_text()
assert "native udev SPI binding and standard fprintd prewarm" in arch
assert "/usr/lib/fprintd --no-timeout" in arch
assert "gxfp51a0-spidev-bind" not in arch

linux = LINUX.read_text()
assert "UDEV_RULE_FILE=" in linux
assert "EARLY_WANTS_LINK=" in linux
assert "--no-timeout" in linux
assert "TimeoutStartSec=40s" in linux
assert "Before=display-manager.service" not in linux
assert "LimitCORE=0" in linux
assert "BIND_HELPER=" not in linux
assert "BIND_SERVICE=" not in linux

uninstall = UNINSTALL.read_text()
assert "created-early-wants" in uninstall
assert "BIND_HELPER=" not in uninstall
assert "BIND_SERVICE=" not in uninstall

assert not (ROOT / "fingerprint/system/gxfp51a0-spidev-bind").exists()
assert not (ROOT / "fingerprint/system/gxfp51a0-spidev-bind.service").exists()

print("GOODIX51A0_NATIVE_SPI_PREWARM_SOURCE_TEST=PASS")
