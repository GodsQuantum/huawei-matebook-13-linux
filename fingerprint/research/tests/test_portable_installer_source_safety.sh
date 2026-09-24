#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
i="$root/install-linux.sh"
u="$root/uninstall-linux-source.sh"
a="$root/install-arch.sh"
hook="$root/packaging/arch/libfprint-goodix51a0.install"

bash -n "$i"
bash -n "$u"
bash -n "$a"
bash -n "$hook"

# Automatic dependency families + generic escape hatch.
grep -Fq 'distro=generic' "$i"
grep -Fq 'apt-get' "$i"
grep -Fq 'dnf install' "$i"
grep -Fq 'zypper' "$i"
grep -Fq 'apk add --no-cache' "$i"
grep -Fq 'distro=alpine' "$i"
grep -Fq -- '--no-install-deps' "$i"

# Cross-distro staged build, dynamic libdir, and ABI gate.
grep -Fq 'MESON_PREFIX="$PREFIX"' "$i"
grep -Fq 'introspect "$BUILD_DIR" --buildoptions' "$i"
grep -Fq 'LIBDIR_REL=' "$i"
grep -Fq 'FPRINTD_ABI_COMPATIBILITY=PASS' "$i"
grep -Fq 'ldd -r "$FPRINTD_BIN"' "$i"
grep -Fq 'FPRINTD_ABI_LDD_MODE=dependency-only' "$i"
grep -Fq 'LD_BIND_NOW=1' "$i"
grep -Fq '"$FPRINTD_BIN" --help' "$i"
grep -Fq 'undefined symbol|not found' "$i"
grep -Fq 'UDEV_RULES_DIR=' "$root/scripts/build-libfprint-v1.94.100.sh"
grep -Fq -- '-Dudev_rules_dir="$UDEV_RULES_DIR"' "$root/scripts/build-libfprint-v1.94.100.sh"
grep -Fq -- '-Dudev_hwdb=disabled' "$root/scripts/build-libfprint-v1.94.100.sh"

# Debian multiarch / Fedora lib64 must be discovered, never hard-coded.
! grep -Fq '/usr/lib/libfprint-2.so.2.0.0' "$i"
grep -Fq 'libsystemd-dev' "$i"

# systemd: isolate candidate to fprintd only.
grep -Fq 'Environment=LD_LIBRARY_PATH=$LIBDIR' "$i"
grep -Fq 'SYSTEMD_AVAILABLE=0' "$i"
grep -Fq 'boot-prewarm' "$i"
grep -Fq 'resume-prewarm' "$i"
! grep -Fq 'KEEPALIVE_' "$i"

# non-systemd: D-Bus activation wrapper; never a global loader override.
grep -Fq '/etc/dbus-1/system-services' "$i"
grep -Fq 'net.reactivated.Fprint.service' "$i"
grep -Fq 'gxfp51a0-fprintd' "$i"
grep -Fq 'org.freedesktop.DBus.ReloadConfig' "$i"
grep -Fq 'library scope: fprintd only (D-Bus activation wrapper)' "$i"
! grep -Fq 'LDCONF_FILE=' "$i"
! grep -Fq '90-gxfp51a0-local.conf' "$i"
! grep -Eq 'run_root[[:space:]]+ldconfig' "$i"

# SELinux and privilege safety.
grep -Fq 'restorecon -RF' "$i"
grep -Fq 'sudo is required' "$i"

# Migration removes only obsolete non-secret timing integers.
grep -Fq '/var/lib/fprint/.goodix51a0-timing' "$i"
grep -Fq '/var/lib/fprint/.goodix51a0-capture-timing' "$i"
! grep -Eq 'rm .*goodix51a0-pmk' "$i"
! grep -Eq 'rm .*template' "$i"

# Rollback restores distro files and supports both init paths.
grep -Fq 'STATE_DIR/backup' "$u"
grep -Fq 'command -v systemctl' "$u"
grep -Fq 'DBUS_SERVICE_FILE=' "$u"
grep -Fq 'FPRINTD_WRAPPER_FILE=' "$u"
grep -Fq 'org.freedesktop.DBus.ReloadConfig' "$u"
grep -Fq 'LEGACY_LDCONF_FILE=' "$u"

# Native Arch path has no periodic keepalive and migrates timing state.
! grep -Fq 'systemctl start gxfp51a0-warm-keepalive' "$a"
grep -Fq '/var/lib/fprint/.goodix51a0-timing' "$hook"

echo 'test_portable_installer_source_safety: OK (systemd + D-Bus activation)'
