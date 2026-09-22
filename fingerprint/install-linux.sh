#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BUILD_ROOT="${XDG_CACHE_HOME:-$HOME/.cache}/gxfp51a0-libfprint-build"
STATE_DIR="/var/lib/gxfp51a0-local-install"
DROPIN_DIR="/etc/systemd/system/fprintd.service.d"
DROPIN_FILE="$DROPIN_DIR/60-goodix51a0-local-lib.conf"
UDEV_RULE_FILE="/etc/udev/rules.d/70-libfprint-goodix51a0-local.rules"
EARLY_WANTS_DIR="/etc/systemd/system/graphical.target.wants"
EARLY_WANTS_LINK="$EARLY_WANTS_DIR/fprintd.service"
INSTALL_DEPS=1
BUILD_ONLY=0

usage() {
  cat <<'EOF'
Usage: ./fingerprint/install-linux.sh [--build-only] [--no-install-deps]

Portable source installer for the validated Huawei MateBook 13 2021
Goodix GXFP51A0 / GF3658 ST411 SPI fingerprint driver.

Arch/CachyOS: delegates to the native pacman package installer.
Debian/Ubuntu and Fedora: rebuilds the same pinned libfprint v1.94.100 driver
from source and installs it under /usr/local with an isolated fprintd drop-in.

Options:
  --build-only       Install build dependencies and compile, but do not modify
                     the system. Useful for validation or unsupported distros.
  --no-install-deps  Do not invoke the distribution package manager.
EOF
}

while (($#)); do
  case "$1" in
    --build-only) BUILD_ONLY=1 ;;
    --no-install-deps) INSTALL_DEPS=0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if (( EUID == 0 && BUILD_ONLY == 0 )); then
  echo "ERROR: run a real system installation as your normal user; sudo is invoked only for system changes." >&2
  exit 2
fi

have() { command -v "$1" >/dev/null 2>&1; }
run_root() {
  if (( EUID == 0 )); then
    "$@"
  else
    sudo "$@"
  fi
}

if have pacman && (( BUILD_ONLY == 0 )); then
  exec "$ROOT/install-arch.sh"
fi

distro=unknown
if have pacman; then distro=arch
elif have apt-get; then distro=debian
elif have dnf; then distro=fedora
elif have zypper; then distro=opensuse
fi

install_deps() {
  (( INSTALL_DEPS )) || return 0
  case "$distro" in
    arch)
      run_root pacman -S --needed --noconfirm \
        base-devel git python python-pip pkgconf \
        glib2 libgusb cairo libgudev openssl systemd pixman
      ;;
    debian)
      run_root apt-get update
      run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y \
        fprintd udev build-essential git python3 python3-venv pkg-config \
        libglib2.0-dev libgusb-dev libcairo2-dev libgudev-1.0-dev \
        libssl-dev libudev-dev systemd-dev libpixman-1-dev
      ;;
    fedora)
      run_root dnf install -y \
        fprintd gcc gcc-c++ git python3 pkgconf-pkg-config \
        glib2-devel libgusb-devel cairo-devel libgudev-devel \
        openssl-devel systemd systemd-udev systemd-devel pixman-devel
      ;;
    opensuse)
      run_root zypper --non-interactive install \
        fprintd gcc gcc-c++ git python3 python3-pip pkg-config \
        glib2-devel libgusb-devel cairo-devel libgudev-1_0-devel \
        libopenssl-dev systemd-devel pixman-devel
      ;;
    *)
      cat >&2 <<'EOF'
ERROR: automatic dependency installation is not available for this distro.
Install the development packages providing:
  glib-2.0 gio-unix-2.0 gobject-2.0 gmodule-2.0
  gusb cairo gudev-1.0 openssl udev pixman-1
plus git, a C compiler, python3+venv and pkg-config.
Then rerun with --no-install-deps.
EOF
      exit 3
      ;;
  esac
}

install_deps

for cmd in git python3 cc pkg-config sha256sum nm strings ar; do
  have "$cmd" || { echo "ERROR: missing required command: $cmd" >&2; exit 4; }
done

rm -rf -- "$BUILD_ROOT"
mkdir -p "$BUILD_ROOT"

GXFP51A0_BUILD_ROOT="$BUILD_ROOT" \
GXFP51A0_MESON_PREFIX=/usr/local \
  "$ROOT/scripts/build-libfprint-v1.94.100.sh"

if (( BUILD_ONLY )); then
  echo "BUILD_ONLY=PASS"
  echo "Build tree: $BUILD_ROOT/libfprint-build"
  exit 0
fi

if ! grep -Rqs '^acpi:GXFP51A0:' /sys/bus/spi/devices/*/modalias 2>/dev/null; then
  echo "ERROR: ACPI/SPI device GXFP51A0 was not found; refusing system install." >&2
  exit 5
fi

MESON="$BUILD_ROOT/build-tools-venv/bin/meson"
BUILD_DIR="$BUILD_ROOT/libfprint-build"
STAGE="$BUILD_ROOT/stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
DESTDIR="$STAGE" "$MESON" install -C "$BUILD_DIR"

UDEV_RULE_SRC="$(find "$STAGE" -type f -path '*/udev/rules.d/70-libfprint-2.rules' -print -quit)"
[[ -n "$UDEV_RULE_SRC" && -f "$UDEV_RULE_SRC" ]] || {
  echo "ERROR: staged GXFP51A0 udev rule was not generated." >&2
  exit 6
}
grep -Fq 'ENV{MODALIAS}=="acpi:GXFP51A0:*"' "$UDEV_RULE_SRC" || {
  echo "ERROR: staged udev rule lacks the GXFP51A0 modalias glob." >&2
  exit 6
}

LIBDIR_REL="$("$MESON" introspect "$BUILD_DIR" --buildoptions | \
  python3 -c 'import json,sys; a=json.load(sys.stdin); print(next(x["value"] for x in a if x["name"]=="libdir"))')"
LIBDIR="/usr/local/$LIBDIR_REL"
[[ -f "$STAGE$LIBDIR/libfprint-2.so.2.0.0" ]] || {
  echo "ERROR: staged libfprint shared library not found in $LIBDIR" >&2
  exit 6
}

FPRINTD_UNIT="$(systemctl show -p FragmentPath --value fprintd.service)"
[[ -n "$FPRINTD_UNIT" && -f "$FPRINTD_UNIT" ]] || {
  echo "ERROR: fprintd.service fragment was not found." >&2
  exit 6
}
FPRINTD_BIN="$(sed -n 's/^ExecStart=//p' "$FPRINTD_UNIT" | head -n1 | awk '{print $1}')"
[[ -n "$FPRINTD_BIN" && -x "$FPRINTD_BIN" ]] || {
  echo "ERROR: fprintd daemon executable could not be resolved from $FPRINTD_UNIT." >&2
  exit 6
}
UDEVADM_BIN="$(command -v udevadm)"

TMP_STATE="$(mktemp -d)"
trap 'rm -rf "$TMP_STATE"' EXIT
mkdir -p "$TMP_STATE/backup"

(
  cd "$STAGE"
  find usr/local -mindepth 1 -printf '/%p\n' | sort
) > "$TMP_STATE/manifest"

while IFS= read -r path; do
  if [[ -e "$path" || -L "$path" ]]; then
    mkdir -p "$TMP_STATE/backup$(dirname "$path")"
    cp -a -- "$path" "$TMP_STATE/backup$path"
  fi
done < "$TMP_STATE/manifest"

sudo mkdir -p /usr/local
sudo cp -a "$STAGE/usr/local/." /usr/local/

sudo mkdir -p "$DROPIN_DIR"
cat > "$TMP_STATE/dropin" <<EOF
[Unit]
After=systemd-udev-trigger.service
Before=display-manager.service

[Service]
ExecStartPre=-$UDEVADM_BIN settle --timeout=3
ExecStart=
ExecStart=$FPRINTD_BIN --no-timeout
TimeoutStartSec=40s
# Local GXFP51A0 libfprint build; isolated to fprintd.
Environment=LD_LIBRARY_PATH=$LIBDIR
DeviceAllow=char-gpiochip rw
LimitCORE=0
EOF
sudo install -m 0644 "$TMP_STATE/dropin" "$DROPIN_FILE"
sudo install -Dm0644 "$UDEV_RULE_SRC" "$UDEV_RULE_FILE"

# Remove rel22 portable-install glue if upgrading in place. rel23 relies on the
# generated libfprint udev rule and the standard fprintd service only.
sudo rm -f /usr/local/libexec/gxfp51a0-spidev-bind \
  /etc/systemd/system/gxfp51a0-spidev-bind.service

sudo mkdir -p "$STATE_DIR"
sudo rm -rf "$STATE_DIR/backup"
sudo cp -a "$TMP_STATE/backup" "$STATE_DIR/backup"
sudo install -m 0644 "$TMP_STATE/manifest" "$STATE_DIR/manifest"
printf '%s\n' "$LIBDIR" | sudo tee "$STATE_DIR/libdir" >/dev/null
sudo install -m 0755 "$ROOT/uninstall-linux-source.sh" "$STATE_DIR/uninstall.sh"

sudo mkdir -p "$EARLY_WANTS_DIR"
if [[ ! -e "$EARLY_WANTS_LINK" && ! -L "$EARLY_WANTS_LINK" ]]; then
  sudo ln -s "$FPRINTD_UNIT" "$EARLY_WANTS_LINK"
  printf '%s\n' "$EARLY_WANTS_LINK" | sudo tee "$STATE_DIR/created-early-wants" >/dev/null
fi

sudo ldconfig
sudo udevadm control --reload
sudo udevadm trigger --subsystem-match=spi
sudo udevadm settle
sudo systemctl daemon-reload
sudo systemctl restart fprintd.service

DEVICE="$(busctl --system call \
  net.reactivated.Fprint \
  /net/reactivated/Fprint/Manager \
  net.reactivated.Fprint.Manager \
  GetDefaultDevice)"
printf 'Default fingerprint device: %s\n' "$DEVICE"

cat <<EOF

Installation complete.

Installed source build: /usr/local
Runtime library directory: $LIBDIR
Rollback:
  sudo $STATE_DIR/uninstall.sh

The installer did not modify PAM, KDE or GNOME configuration.
It uses only the generated libfprint udev SPI rule and the standard fprintd
service. fprintd starts early so the greeter can discover fingerprint support and
stays alive with --no-timeout; sensor/TLS preparation occurs only on a real
Claim/open, and no GXFP-specific daemon/service is installed.
Enroll through your desktop settings or:
  fprintd-enroll -f right-index-finger
EOF
