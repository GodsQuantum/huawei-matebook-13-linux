#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PKGDIR="$ROOT/packaging/arch"

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

echo "==> Installing libfprint-goodix51a0 and fprintd"
sudo pacman -S --needed --noconfirm fprintd
sudo pacman -U --needed --noconfirm "$PKG"

echo "==> Verifying native udev SPI binding and Claim-time fingerprint preparation"
sudo udevadm control --reload
sudo udevadm trigger --subsystem-match=spi
sudo udevadm settle --timeout=3 || true
sudo systemctl daemon-reload
sudo systemctl restart fprintd.service

test -L /usr/lib/systemd/system/graphical.target.wants/fprintd.service
systemctl cat fprintd.service | grep -Fq '/usr/lib/fprintd --no-timeout'
systemctl cat fprintd.service | grep -Fq 'Before=display-manager.service'
test "$(readlink -f /usr/lib/systemd/system/graphical.target.wants/fprintd.service)" =   "$(readlink -f /usr/lib/systemd/system/fprintd.service)"

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

No GXFP-specific daemon or systemd service is installed. The standard fprintd
daemon starts early in graphical boot and stays alive with --no-timeout so the
driver can keep a short, bounded in-process warm context for fast authentication.

Standard Linux tools:
  fprintd-enroll -f right-index-finger
  fprintd-verify
  fprintd-list "$USER"

The driver does not modify PAM, KDE or GNOME configuration.
EOF
