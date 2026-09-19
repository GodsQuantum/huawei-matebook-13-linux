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

if ! grep -Rqs '^acpi:GXFP51A0:$' /sys/bus/spi/devices/*/modalias 2>/dev/null; then
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

echo "==> Reloading the standard Linux device/service integration"
sudo udevadm control --reload
sudo udevadm trigger --subsystem-match=spi
sudo udevadm settle
sudo systemctl daemon-reload
sudo systemctl restart fprintd.service

echo "==> Verifying fprintd discovery"
DEVICE="$(busctl --system call \
  net.reactivated.Fprint \
  /net/reactivated/Fprint/Manager \
  net.reactivated.Fprint.Manager \
  GetDefaultDevice)"
printf 'Default fingerprint device: %s\n' "$DEVICE"

cat <<'EOF'

Installation complete.

Standard Linux tools:
  fprintd-enroll -f right-index-finger
  fprintd-verify
  fprintd-list "$USER"

The driver does not modify PAM or desktop configuration. KDE/GNOME/login
integration remains the distribution/desktop authentication policy.
EOF
