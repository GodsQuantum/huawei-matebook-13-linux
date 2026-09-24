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
RESUME_HELPER = ROOT / "fingerprint/integration/resume-prewarm/gxfp51a0-resume-prewarm"
RESUME_UNIT = ROOT / "fingerprint/integration/resume-prewarm/gxfp51a0-resume-prewarm.service"
RESUME_WORKER = ROOT / "fingerprint/integration/resume-prewarm/gxfp51a0-resume-prewarm-worker.service"
PLM_INTEGRATION = ROOT / "fingerprint/integration/plasma-login-manager-6.7-pam-messages"
PLM_PKGBUILD = PLM_INTEGRATION / "PKGBUILD"
PLM_PATCH1 = PLM_INTEGRATION / "0001-show-pam-authentication-messages.patch"
PLM_PATCH2 = PLM_INTEGRATION / "0002-stop-notification-timer-for-pam-message.patch"
PLM_PATCH3 = PLM_INTEGRATION / "0003-enable-fprintd-for-plasmalogin.patch"
PLM_PATCH4 = PLM_INTEGRATION / "0004-autostart-first-fingerprint-attempt.patch"
PLM_PATCH5 = PLM_INTEGRATION / "0005-split-fingerprint-password-auth.patch"

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
assert "GX_WARM_TTL_US" not in driver
assert "gx_warm_validate" in driver

# rel26: enumeration is host-transport-only. No TLS/background/FDT prewarm may
# run before a real Claim, because Pegasus 2021 proved that a failed prewarm can
# desynchronise GET_IMAGE before the greeter ever asks for a fingerprint.
assert "probe_prewarm" not in driver
assert "GX_PROBE_PREWARM_ATTEMPTS" not in driver
assert "Enumeration must be passive" in driver
assert "if (!gx_cold_prepare (self))" in driver
assert "gx_prepare_capture_context (self, FALSE)" in driver
assert "GXFP51A0 cold preparation failed" in driver

# Native lifecycle invalidation: active suspend uses libfprint hooks; idle
# suspend is caught from CLOCK_BOOTTIME-vs-MONOTONIC at the next Claim.
assert "dev_class->suspend = gx_dev_suspend;" in driver
assert "dev_class->resume = gx_dev_resume;" in driver
assert "CLOCK_BOOTTIME" in driver
assert "CLOCK_MONOTONIC" in driver
assert "gx_warm_crossed_sleep" in driver
assert "gx_warm_abandon" in driver
assert "force_cold_reset" in driver

assert "gx51_wait_irq_gpio48_low (self->irq_fd, 250)" in driver
assert "first background capture must not race the tail of the TLS handshake" in driver
assert "reset_before_cold" not in driver
assert "warm_expire" not in driver
assert re.search(r"^#define\s+GX_MATCH_THRESHOLD\s+7\s*$", driver, re.M)
assert re.search(r"^#define\s+GX_VERIFY_MAX_ATTEMPTS\s+3\b", driver, re.M)
assert "GPIO112" not in driver
assert "GPP_D16" not in driver

dropin = DROPIN.read_text()
assert "After=systemd-udev-trigger.service" in dropin
assert "Before=display-manager.service" in dropin
assert "ExecStart=/usr/lib/fprintd --no-timeout" in dropin
assert "TimeoutStartSec=40s" in dropin
assert "DeviceAllow=char-gpiochip rw" in dropin
assert "LimitCORE=0" in dropin
assert "gxfp51a0-spidev-bind" not in dropin

pkgbuild = PKGBUILD.read_text()
pkginstall = PKGINSTALL.read_text()
assert "pkgrel=42" in pkgbuild
assert "install=libfprint-goodix51a0.install" in pkgbuild
assert "graphical.target.wants/fprintd.service" in pkgbuild
assert "sleep.target.wants/gxfp51a0-resume-prewarm.service" in pkgbuild
assert "timers.target.wants/gxfp51a0-warm-keepalive.timer" not in pkgbuild
assert "gxfp51a0-kde-lockscreen-integrate" in pkgbuild
assert "90-gxfp51a0-kde-lockscreen.hook" in pkgbuild
assert "gxfp51a0-spidev-bind" not in pkgbuild

resume_helper = RESUME_HELPER.read_text()
resume_unit = RESUME_UNIT.read_text()
resume_worker = RESUME_WORKER.read_text()
assert 'GetDefaultDevice' in resume_helper
assert 'Claim s ""' in resume_helper
assert 'restart fprintd' not in resume_helper
assert 'try-restart fprintd' not in resume_helper
assert 'Before=sleep.target' in resume_unit
assert 'RemainAfterExit=yes' in resume_unit
assert 'systemctl --no-block start gxfp51a0-resume-prewarm-worker.service' in resume_unit
assert 'TimeoutStopSec=5s' in resume_unit
assert 'WantedBy=sleep.target' in resume_unit
assert 'ExecStart=/usr/libexec/gxfp51a0-resume-prewarm' in resume_worker
assert 'TimeoutStartSec=50s' in resume_worker
assert 'NoNewPrivileges=yes' in resume_worker

plm_pkgbuild = PLM_PKGBUILD.read_text()
plm_patch1 = PLM_PATCH1.read_text()
plm_patch2 = PLM_PATCH2.read_text()
plm_patch3 = PLM_PATCH3.read_text()
plm_patch4 = PLM_PATCH4.read_text()
plm_patch5 = PLM_PATCH5.read_text()
assert "pkgver=6.7.5" in plm_pkgbuild
assert "pkgrel=3.4" in plm_pkgbuild
assert "0001-show-pam-authentication-messages.patch" in plm_pkgbuild
assert "0002-stop-notification-timer-for-pam-message.patch" in plm_pkgbuild
assert "0003-enable-fprintd-for-plasmalogin.patch" in plm_pkgbuild
assert "0004-autostart-first-fingerprint-attempt.patch" in plm_pkgbuild
assert "0005-split-fingerprint-password-auth.patch" in plm_pkgbuild
assert "function onInformationMessage(message)" in plm_patch1
assert "notificationResetTimer.stop();" in plm_patch2
assert "pam_fprintd.so max-tries=3 timeout=12" in plm_patch3
assert "maybeStartFingerprintLogin" in plm_patch4
assert "fingerprintAutoAttemptDone" in plm_patch4
assert "fingerprintAutoAttemptInFlight" in plm_patch4
assert "startLogin(true)" in plm_patch4
assert "plasmalogin-fingerprint" in plm_patch5
assert "FingerprintLogin" in plm_patch5
assert "CancelLogin" in plm_patch5
assert "LoginCancelled" in plm_patch5
assert "setPamService" in plm_patch5
assert "onTextChanged" in plm_patch5
assert "-auth        sufficient  pam_fprintd.so max-tries=3 timeout=12" in plm_patch5
assert "+-auth      required     pam_fprintd.so max-tries=3 timeout=12" in plm_patch5
assert "udevadm control --reload" in pkginstall
assert "udevadm trigger --subsystem-match=spi" in pkginstall
assert "systemctl restart --no-block fprintd.service" in pkginstall
assert "gxfp51a0-kde-lockscreen-integrate --apply" in pkginstall
assert "systemctl stop gxfp51a0-warm-keepalive.timer" in pkginstall
assert "systemctl start --no-block gxfp51a0-warm-keepalive.service" not in pkginstall
assert ".goodix51a0-timing" in pkginstall
assert ".goodix51a0-capture-timing" in pkginstall

arch = ARCH.read_text()
assert "native udev SPI binding, warm readiness and desktop integration" in arch
assert "/usr/lib/fprintd --no-timeout" in arch
assert "gxfp51a0-spidev-bind" not in arch

linux = LINUX.read_text()
assert "UDEV_RULE_FILE=" in linux
assert "EARLY_WANTS_LINK=" in linux
assert "--no-timeout" in linux
assert "TimeoutStartSec=40s" in linux
assert "Before=display-manager.service" in linux
assert "LimitCORE=0" in linux
assert "KEEPALIVE_HELPER_FILE=" not in linux
assert "DBUS_SERVICE_FILE=" in linux
assert "FPRINTD_WRAPPER_FILE=" in linux
assert "FPRINTD_ABI_COMPATIBILITY=PASS" in linux
assert "ldd -r" in linux
assert "LDCONF_FILE=" not in linux
assert "90-gxfp51a0-local.conf" not in linux
assert "SYSTEMD_AVAILABLE=0" in linux
assert "introspect" in linux and "LIBDIR_REL=" in linux
assert "KDE_HELPER_FILE=" in linux
assert "BIND_HELPER=" not in linux
assert "BIND_SERVICE=" not in linux

uninstall = UNINSTALL.read_text()
assert "created-early-wants" in uninstall
assert "KDE_HELPER=" in uninstall and '"$KDE_HELPER" --remove' in uninstall
assert "gxfp51a0-warm-keepalive.timer" in uninstall
assert "DBUS_SERVICE_FILE=" in uninstall
assert "FPRINTD_WRAPPER_FILE=" in uninstall
assert "LEGACY_LDCONF_FILE=" in uninstall
assert "org.freedesktop.DBus.ReloadConfig" in uninstall
assert "command -v systemctl" in uninstall
assert "BIND_HELPER=" not in uninstall
assert "BIND_SERVICE=" not in uninstall

assert not (ROOT / "fingerprint/system/gxfp51a0-spidev-bind").exists()
assert not (ROOT / "fingerprint/system/gxfp51a0-spidev-bind.service").exists()

print("GOODIX51A0_NATIVE_SPI_LIFECYCLE_SOURCE_TEST=PASS")
