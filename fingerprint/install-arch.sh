#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PKGDIR="$ROOT/packaging/arch"
PLMDIR="$ROOT/integration/plasma-login-manager-6.7-pam-messages"

if (( EUID == 0 )); then
  echo "ERROR: run this installer as your normal user, not as root." >&2
  exit 2
fi

for cmd in makepkg pacman sudo udevadm systemctl busctl; do
  command -v "$cmd" >/dev/null || {
    echo "ERROR: missing required command: $cmd" >&2
    exit 3
  }
done

if ! grep -Rqs '^acpi:GXFP51A0:' /sys/bus/spi/devices/*/modalias 2>/dev/null; then
  echo "ERROR: ACPI/SPI device GXFP51A0 was not found." >&2
  exit 4
fi

echo "==> Building libfprint-goodix51a0 from the reviewed source tree"
(
  cd "$PKGDIR"
  makepkg -s -f --noconfirm
)

PKG="$(find "$PKGDIR" -maxdepth 1 -type f \
  -name 'libfprint-goodix51a0-*.pkg.tar.zst' -print | sort -V | tail -n1)"
[[ -n "$PKG" && -f "$PKG" ]] || {
  echo "ERROR: package build completed without a package artifact." >&2
  exit 5
}

PLM_PKG=""
if pacman -Qq plasma-login-manager >/dev/null 2>&1; then
  plasma_ver="$(pacman -Q plasma-desktop 2>/dev/null | awk '{print $2}' || true)"
  if [[ "$plasma_ver" == 6.7.5-* ]]; then
    echo "==> Building Plasma Login Manager 6.7.5 fingerprint integration"
    (
      cd "$PLMDIR"
      makepkg -s -f --noconfirm
    )
    PLM_PKG="$(find "$PLMDIR" -maxdepth 1 -type f \
      -name 'plasma-login-manager-6.7.5-*.pkg.tar.zst' -print | sort -V | tail -n1)"
    [[ -n "$PLM_PKG" && -f "$PLM_PKG" ]] || {
      echo "ERROR: Plasma Login Manager integration build produced no package." >&2
      exit 5
    }
  else
    echo "WARNING: Plasma Login Manager integration is validated for Plasma 6.7.5; found plasma-desktop $plasma_ver." >&2
  fi
fi

echo "==> Installing libfprint-goodix51a0 and fprintd"
sudo pacman -S --needed --noconfirm fprintd
sudo pacman -U --needed --noconfirm "$PKG"
if [[ -n "$PLM_PKG" ]]; then
  sudo pacman -U --needed --noconfirm "$PLM_PKG"
fi

echo "==> Verifying native udev SPI binding, warm readiness and desktop integration"
sudo udevadm control --reload
sudo udevadm trigger --subsystem-match=spi
sudo udevadm settle --timeout=3 || true
sudo systemctl daemon-reload
sudo systemctl restart fprintd.service

test -L /usr/lib/systemd/system/graphical.target.wants/fprintd.service
systemctl cat fprintd.service | grep -Fq '/usr/lib/fprintd --no-timeout'
systemctl cat fprintd.service | grep -Fq 'Before=display-manager.service'
test "$(readlink -f /usr/lib/systemd/system/graphical.target.wants/fprintd.service)" =   "$(readlink -f /usr/lib/systemd/system/fprintd.service)"
test -L /usr/lib/systemd/system/graphical.target.wants/gxfp51a0-boot-prewarm.service
test -x /usr/lib/systemd/system-sleep/gxfp51a0-resume-prewarm
systemctl cat gxfp51a0-boot-prewarm.service >/dev/null
if [[ -f /usr/share/plasma/shells/org.kde.plasma.desktop/contents/lockscreen/LockScreenUi.qml ]]; then
  sudo /usr/libexec/gxfp51a0-kde-lockscreen-integrate --apply
  sudo /usr/libexec/gxfp51a0-kde-lockscreen-integrate --check
fi

DEVICE="$(busctl --system call \
  net.reactivated.Fprint \
  /net/reactivated/Fprint/Manager \
  net.reactivated.Fprint.Manager \
  GetDefaultDevice)"
printf 'Default fingerprint device: %s\n' "$DEVICE"

cat <<'EOF'

Installation complete.

GXFP51A0 now follows the native libfprint SPI path:
  udev -> spidev -> libfprint probe/open -> standard fprintd -> PAM/KDE

The standard fprintd daemon starts early and stays alive with --no-timeout.
A bounded cold-boot Claim prepares TLS/background/FDT before the greeter, and a
separate post-resume Claim rebuilds state after deep sleep. There is no periodic
synthetic keepalive. Runtime timing adaptation is session-local and always
starts from the validated nominal 100% values after a fresh lifecycle. KDE Plasma
is detected automatically: on the validated 6.7.5 lock screen, fingerprint PAM
is armed at lock creation instead of waiting for mouse/keyboard activity.
Plasma Login Manager 6.7.5 receives the package-managed fingerprint-first PAM
integration when that display manager is installed.

Standard Linux tools:
  fprintd-enroll -f right-index-finger
  fprintd-verify
  fprintd-list "$USER"

Non-KDE desktops keep their native PAM/greeter behavior; no KDE integration is applied when Plasma is absent.
EOF
