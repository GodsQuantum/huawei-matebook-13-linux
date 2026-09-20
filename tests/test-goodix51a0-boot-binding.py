#!/usr/bin/env python3
from pathlib import Path
import fnmatch

ROOT = Path(__file__).resolve().parents[1]
PATCH = ROOT / 'fingerprint/driver/goodix51a0/libfprint-v1.94.100.patch'
ARCH = ROOT / 'fingerprint/install-arch.sh'
LINUX = ROOT / 'fingerprint/install-linux.sh'
UNINSTALL = ROOT / 'fingerprint/uninstall-linux-source.sh'
BUILD = ROOT / 'fingerprint/scripts/build-libfprint-v1.94.100.sh'
PKGBUILD = ROOT / 'fingerprint/packaging/arch/PKGBUILD'
PKGINSTALL = ROOT / 'fingerprint/packaging/arch/libfprint-goodix51a0.install'
DROPIN = ROOT / 'fingerprint/packaging/arch/fprintd-goodix51a0.conf'
BINDER = ROOT / 'fingerprint/system/gxfp51a0-spidev-bind'
SERVICE = ROOT / 'fingerprint/system/gxfp51a0-spidev-bind.service'

actual = 'acpi:GXFP51A0:GXFP51A0:'
legacy = 'acpi:GXFP51A0:'
pattern = 'acpi:GXFP51A0:*'
assert fnmatch.fnmatchcase(actual, pattern)
assert fnmatch.fnmatchcase(legacy, pattern)

patch = PATCH.read_text()
plus = '\n'.join(line[1:] for line in patch.splitlines() if line.startswith('+') and not line.startswith('+++'))
assert 'ENV{MODALIAS}==\\"acpi:%s:*\\"' in plus
assert 'test -L %%S%%p/driver || echo %%k > %%S%%p/subsystem/drivers/spidev/bind' in plus

build = BUILD.read_text()
assert 'GOODIX51A0_UDEV_MODALIAS_GLOB=PASS' in build
assert 'ENV{MODALIAS}=="acpi:GXFP51A0:*"' in build

binder = BINDER.read_text()
assert binder.startswith('#!/usr/bin/env bash\nset -Eeuo pipefail')
assert "ACPI_PREFIX='acpi:GXFP51A0:'" in binder
assert 'modprobe spidev' in binder
assert 'driver_override' in binder
assert 'refusing to unbind it' in binder
assert 'udevadm settle --timeout=2' in binder
assert '/dev/$(basename "$child")' in binder
assert 'GPIO112' not in binder
assert 'gpio112' not in binder.lower()
assert 'GPIO264' not in binder

service = SERVICE.read_text()
assert 'Before=fprintd.service' in service
assert 'ExecStart=/usr/libexec/gxfp51a0-spidev-bind' in service
assert 'TimeoutStartSec=5s' in service

dropin = DROPIN.read_text()
assert 'Requires=gxfp51a0-spidev-bind.service' in dropin
assert 'After=gxfp51a0-spidev-bind.service' in dropin
assert 'DeviceAllow=char-gpiochip rw' in dropin

arch = ARCH.read_text()
assert "grep -Rqs '^acpi:GXFP51A0:'" in arch
assert 'sudo /usr/libexec/gxfp51a0-spidev-bind' in arch

linux = LINUX.read_text()
assert "grep -Rqs '^acpi:GXFP51A0:'" in linux
assert 'UDEV_RULE_FILE="/etc/udev/rules.d/70-libfprint-goodix51a0-local.rules"' in linux
assert 'BIND_HELPER="/usr/local/libexec/gxfp51a0-spidev-bind"' in linux
assert 'Requires=gxfp51a0-spidev-bind.service' in linux
assert 'sudo "$BIND_HELPER"' in linux

uninstall = UNINSTALL.read_text()
assert 'UDEV_RULE_FILE=' in uninstall
assert 'BIND_HELPER=' in uninstall
assert 'BIND_SERVICE=' in uninstall

pkgbuild = PKGBUILD.read_text()
pkginstall = PKGINSTALL.read_text()
assert 'pkgrel=22' in pkgbuild
assert 'install=libfprint-goodix51a0.install' in pkgbuild
assert 'gxfp51a0-spidev-bind' in pkgbuild
assert 'gxfp51a0-spidev-bind.service' in pkgbuild
assert 'udevadm control --reload' in pkginstall
assert 'udevadm trigger --subsystem-match=spi' in pkginstall
assert 'systemctl try-restart fprintd.service' in pkginstall

print('GOODIX51A0_BOOT_BINDING_SOURCE_TEST=PASS')
