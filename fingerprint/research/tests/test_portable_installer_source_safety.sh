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

# Cross-distro build and layout.
grep -Fq 'distro=generic' "$i"
grep -Fq 'apt-get' "$i"
grep -Fq 'dnf install' "$i"
grep -Fq 'zypper' "$i"
grep -Fq -- '--no-install-deps' "$i"
grep -Fq 'MESON_PREFIX="$PREFIX"' "$i"
grep -Fq 'introspect "$BUILD_DIR" --buildoptions' "$i"
grep -Fq 'LIBDIR_REL=' "$i"
grep -Fq '90-gxfp51a0-local.conf' "$i"
grep -Fq 'Environment=LD_LIBRARY_PATH=$LIBDIR' "$i"
grep -Fq 'if (( ! SYSTEMD_AVAILABLE )); then' "$i"
grep -Fq 'ldconfig' "$i"
grep -Fq 'SYSTEMD_AVAILABLE=0' "$i"
grep -Fq 'restorecon -RF' "$i"
grep -Fq 'sudo is required' "$i"

# Debian multiarch must not be hard-coded as /usr/lib.
! grep -Fq '/usr/lib/libfprint-2.so.2.0.0' "$i"
grep -Fq 'libsystemd-dev' "$i"

# Runtime integration is capability-based, not desktop mandatory.
grep -Fq 'systemd is optional' "$i"
grep -Fq 'NO_DESKTOP_INTEGRATION' "$i"
grep -Fq 'boot-prewarm' "$i"
grep -Fq 'resume-prewarm' "$i"
! grep -Fq 'KEEPALIVE_' "$i"

# rel41 migrates only obsolete timing integers, not PMK/templates.
grep -Fq '/var/lib/fprint/.goodix51a0-timing' "$i"
grep -Fq '/var/lib/fprint/.goodix51a0-capture-timing' "$i"
! grep -Eq 'rm .*goodix51a0-pmk' "$i"
! grep -Eq 'rm .*template' "$i"

# Rollback restores previous files and works without requiring systemd.
grep -Fq 'STATE_DIR/backup' "$u"
grep -Fq 'command -v systemctl' "$u"
grep -Fq '90-gxfp51a0-local.conf' "$u"

# Native Arch path also has no periodic keepalive and migrates timing state.
! grep -Fq 'systemctl start gxfp51a0-warm-keepalive' "$a"
grep -Fq '/var/lib/fprint/.goodix51a0-timing' "$hook"

echo 'test_portable_installer_source_safety: OK'
