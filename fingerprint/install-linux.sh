#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BUILD_ROOT="${XDG_CACHE_HOME:-$HOME/.cache}/gxfp51a0-libfprint-build"
STATE_DIR="/var/lib/gxfp51a0-local-install"
PREFIX="/usr/local"
LIBEXEC_DIR="$PREFIX/libexec"
LDCONF_FILE="/etc/ld.so.conf.d/90-gxfp51a0-local.conf"
UDEV_RULE_FILE="/etc/udev/rules.d/70-libfprint-goodix51a0-local.rules"

DROPIN_DIR="/etc/systemd/system/fprintd.service.d"
DROPIN_FILE="$DROPIN_DIR/60-goodix51a0-local.conf"
EARLY_WANTS_DIR="/etc/systemd/system/graphical.target.wants"
EARLY_WANTS_LINK="$EARLY_WANTS_DIR/fprintd.service"
BOOT_HELPER_FILE="$LIBEXEC_DIR/gxfp51a0-boot-prewarm"
BOOT_UNIT_FILE="/etc/systemd/system/gxfp51a0-boot-prewarm.service"
BOOT_WANTS_LINK="$EARLY_WANTS_DIR/gxfp51a0-boot-prewarm.service"
RESUME_HELPER_FILE="$LIBEXEC_DIR/gxfp51a0-resume-prewarm"
RESUME_UNIT_FILE="/etc/systemd/system/gxfp51a0-resume-prewarm.service"
RESUME_WORKER_FILE="/etc/systemd/system/gxfp51a0-resume-prewarm-worker.service"
RESUME_WANTS_DIR="/etc/systemd/system/sleep.target.wants"
RESUME_WANTS_LINK="$RESUME_WANTS_DIR/gxfp51a0-resume-prewarm.service"
KDE_HELPER_FILE="$LIBEXEC_DIR/gxfp51a0-kde-lockscreen-integrate"

INSTALL_DEPS=1
BUILD_ONLY=0
NO_DESKTOP_INTEGRATION=0

usage() {
  cat <<'EOF'
Usage: ./fingerprint/install-linux.sh [OPTIONS]

Portable source installer for the Huawei MateBook GXFP51A0 / GF3658 ST411
libfprint driver.

The same reviewed driver is built against pinned libfprint v1.94.100 on every
distribution.  Arch/CachyOS uses the native pacman package by default.
Other distributions install an isolated libfprint under /usr/local and make it
available to fprintd without replacing files owned by the distribution package.

Options:
  --build-only
      Build and validate only. Never modifies the system.
  --no-install-deps
      Do not invoke apt/dnf/zypper/pacman. Useful on unsupported distributions
      after installing the required development packages manually.
  --no-desktop-integration
      Install only libfprint/udev plus fprintd runtime glue. Skip KDE helper.
  -h, --help
      Show this help.

Supported automatic dependency installers:
  Arch/CachyOS, Debian/Ubuntu, Fedora/RHEL-family, openSUSE.

Other distributions are supported with --no-install-deps when they provide:
  gcc/clang, git, python3+venv, pkg-config, glib-2.0, gio-unix-2.0,
  gobject-2.0, gmodule-2.0, gusb, cairo, gudev-1.0, openssl, udev, pixman-1.

systemd is optional for the library itself. When systemd/fprintd.service exists,
boot-prewarm and resume-prewarm are installed automatically. On non-systemd
systems the driver is still installed and the distribution's native fprintd/
PAM integration remains responsible for daemon lifecycle.
EOF
}

while (($#)); do
  case "$1" in
    --build-only) BUILD_ONLY=1 ;;
    --no-install-deps) INSTALL_DEPS=0 ;;
    --no-desktop-integration) NO_DESKTOP_INTEGRATION=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if (( EUID == 0 && BUILD_ONLY == 0 )); then
  echo "ERROR: run installation as your normal user; sudo is used only for system changes." >&2
  exit 2
fi

have() { command -v "$1" >/dev/null 2>&1; }
if (( EUID != 0 && BUILD_ONLY == 0 )) && ! have sudo; then
  echo "ERROR: sudo is required for a system installation." >&2
  exit 2
fi
run_root() {
  if (( EUID == 0 )); then "$@"; else sudo "$@"; fi
}

distro=generic
if have pacman; then distro=arch
elif have apt-get; then distro=debian
elif have dnf; then distro=fedora
elif have zypper; then distro=opensuse
fi

# Native Arch packaging is the cleanest system installation there.
if [[ "$distro" == arch && "$BUILD_ONLY" -eq 0 ]]; then
  exec "$ROOT/install-arch.sh"
fi

install_deps() {
  (( INSTALL_DEPS )) || return 0
  case "$distro" in
    arch)
      run_root pacman -S --needed --noconfirm \
        base-devel git python python-pip pkgconf \
        glib2 libgusb cairo libgudev openssl systemd pixman fprintd
      ;;
    debian)
      run_root apt-get update
      run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y \
        fprintd udev build-essential git python3 python3-venv pkg-config \
        libglib2.0-dev libgusb-dev libcairo2-dev libgudev-1.0-dev \
        libssl-dev libudev-dev libsystemd-dev libpixman-1-dev
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
        libopenssl-devel systemd-devel pixman-devel
      ;;
    generic)
      cat >&2 <<'EOF'
ERROR: no automatic dependency recipe for this distribution.
Install the development dependencies listed by --help, then rerun:
  ./fingerprint/install-linux.sh --no-install-deps
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
GXFP51A0_MESON_PREFIX="$PREFIX" \
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
  echo "ERROR: staged udev rule lacks GXFP51A0 modalias." >&2
  exit 6
}

LIBDIR_REL="$("$MESON" introspect "$BUILD_DIR" --buildoptions |
  python3 -c 'import json,sys; a=json.load(sys.stdin); print(next(x["value"] for x in a if x["name"]=="libdir"))')"
if [[ "$LIBDIR_REL" = /* ]]; then
  LIBDIR="$LIBDIR_REL"
else
  LIBDIR="$PREFIX/$LIBDIR_REL"
fi
[[ -f "$STAGE$LIBDIR/libfprint-2.so.2.0.0" ]] || {
  echo "ERROR: staged libfprint shared library not found in $LIBDIR" >&2
  exit 6
}

SYSTEMD_AVAILABLE=0
FPRINTD_UNIT=""
FPRINTD_BIN=""
if have systemctl; then
  FPRINTD_UNIT="$(systemctl show -p FragmentPath --value fprintd.service 2>/dev/null || true)"
  if [[ -n "$FPRINTD_UNIT" && -f "$FPRINTD_UNIT" ]]; then
    SYSTEMD_AVAILABLE=1
    FPRINTD_BIN="$(systemctl show -p ExecStart --value fprintd.service 2>/dev/null |
      sed -n 's/.*path=\([^ ;}]*\).*/\1/p' | head -n1)"
    if [[ -z "$FPRINTD_BIN" || ! -x "$FPRINTD_BIN" ]]; then
      FPRINTD_BIN="$(command -v fprintd 2>/dev/null || true)"
    fi
    if [[ -z "$FPRINTD_BIN" || ! -x "$FPRINTD_BIN" ]]; then
      for candidate in /usr/lib/fprintd /usr/libexec/fprintd /usr/lib/fprintd/fprintd; do
        [[ -x "$candidate" ]] && { FPRINTD_BIN="$candidate"; break; }
      done
    fi
    [[ -n "$FPRINTD_BIN" && -x "$FPRINTD_BIN" ]] || {
      echo "ERROR: fprintd.service exists but daemon executable could not be resolved." >&2
      exit 6
    }
  fi
fi

TMP_STATE="$(mktemp -d)"
trap 'rm -rf "$TMP_STATE"' EXIT
mkdir -p "$TMP_STATE/backup"

# Manifest of files/directories owned by this local installation.
(
  cd "$STAGE"
  find usr/local -mindepth 1 -printf '/%p\n' | sort
) > "$TMP_STATE/manifest"
printf '%s\n' "$UDEV_RULE_FILE" >> "$TMP_STATE/manifest"
if (( ! SYSTEMD_AVAILABLE )); then
  printf '%s\n' "$LDCONF_FILE" >> "$TMP_STATE/manifest"
fi

if (( SYSTEMD_AVAILABLE )); then
  printf '%s\n' \
    "$DROPIN_FILE" "$BOOT_HELPER_FILE" "$BOOT_UNIT_FILE" "$BOOT_WANTS_LINK" \
    "$RESUME_HELPER_FILE" "$RESUME_UNIT_FILE" "$RESUME_WORKER_FILE" "$RESUME_WANTS_LINK" \
    "$KDE_HELPER_FILE" >> "$TMP_STATE/manifest"
fi
sort -u -o "$TMP_STATE/manifest" "$TMP_STATE/manifest"

while IFS= read -r path; do
  if [[ -e "$path" || -L "$path" ]]; then
    mkdir -p "$TMP_STATE/backup$(dirname "$path")"
    cp -a -- "$path" "$TMP_STATE/backup$path"
  fi
done < "$TMP_STATE/manifest"

run_root mkdir -p "$PREFIX"
run_root cp -a "$STAGE$PREFIX/." "$PREFIX/"
if (( ! SYSTEMD_AVAILABLE )); then
  printf '%s\n' "$LIBDIR" > "$TMP_STATE/ldconf"
  run_root install -Dm0644 "$TMP_STATE/ldconf" "$LDCONF_FILE"
fi
run_root install -Dm0644 "$UDEV_RULE_SRC" "$UDEV_RULE_FILE"

# Fedora/RHEL and other SELinux systems may label /usr/local more strictly than
# the build staging tree. Re-apply the distro's canonical contexts when the
# tool is available; this is a no-op elsewhere.
if have restorecon; then
  run_root restorecon -RF "$PREFIX" "$UDEV_RULE_FILE" || true
fi

# rel41 migration: rel24-rel40 timing integers are known to be contaminated by
# lifecycle/prewarm ratcheting. They are not biometric or key material.
run_root rm -f /var/lib/fprint/.goodix51a0-timing \
               /var/lib/fprint/.goodix51a0-capture-timing

if (( SYSTEMD_AVAILABLE )); then
  UDEVADM_BIN="$(command -v udevadm)"

  run_root mkdir -p "$DROPIN_DIR"
  cat > "$TMP_STATE/dropin" <<EOF
[Unit]
After=systemd-udev-trigger.service
Before=display-manager.service

[Service]
ExecStartPre=-$UDEVADM_BIN settle --timeout=3
ExecStart=
ExecStart=$FPRINTD_BIN --no-timeout
TimeoutStartSec=40s
Environment=LD_LIBRARY_PATH=$LIBDIR
DeviceAllow=char-gpiochip rw
LimitCORE=0
EOF
  run_root install -m0644 "$TMP_STATE/dropin" "$DROPIN_FILE"

  run_root install -Dm0755 "$ROOT/integration/boot-prewarm/gxfp51a0-boot-prewarm" "$BOOT_HELPER_FILE"
  sed "s#/usr/libexec/gxfp51a0-boot-prewarm#$BOOT_HELPER_FILE#" \
    "$ROOT/integration/boot-prewarm/gxfp51a0-boot-prewarm.service" > "$TMP_STATE/boot.service"
  run_root install -Dm0644 "$TMP_STATE/boot.service" "$BOOT_UNIT_FILE"

  run_root install -Dm0755 "$ROOT/integration/resume-prewarm/gxfp51a0-resume-prewarm" "$RESUME_HELPER_FILE"
  run_root install -Dm0644 "$ROOT/integration/resume-prewarm/gxfp51a0-resume-prewarm.service" "$RESUME_UNIT_FILE"
  sed "s#/usr/libexec/gxfp51a0-resume-prewarm#$RESUME_HELPER_FILE#" \
    "$ROOT/integration/resume-prewarm/gxfp51a0-resume-prewarm-worker.service" > "$TMP_STATE/resume-worker.service"
  run_root install -Dm0644 "$TMP_STATE/resume-worker.service" "$RESUME_WORKER_FILE"

  run_root mkdir -p "$EARLY_WANTS_DIR" "$RESUME_WANTS_DIR"
  if [[ ! -e "$EARLY_WANTS_LINK" && ! -L "$EARLY_WANTS_LINK" ]]; then
    run_root ln -s "$FPRINTD_UNIT" "$EARLY_WANTS_LINK"
    printf '%s\n' "$EARLY_WANTS_LINK" > "$TMP_STATE/created-early-wants"
  fi
  run_root ln -sfn "$BOOT_UNIT_FILE" "$BOOT_WANTS_LINK"
  run_root ln -sfn "$RESUME_UNIT_FILE" "$RESUME_WANTS_LINK"

  if (( ! NO_DESKTOP_INTEGRATION )); then
    run_root install -Dm0755 "$ROOT/integration/kde-lockscreen/gxfp51a0-kde-lockscreen-integrate" "$KDE_HELPER_FILE"
  fi
fi

# Remove obsolete local glue from older portable releases.
run_root rm -f \
  /usr/local/libexec/gxfp51a0-spidev-bind \
  /etc/systemd/system/gxfp51a0-spidev-bind.service \
  /usr/local/libexec/gxfp51a0-warm-keepalive \
  /etc/systemd/system/gxfp51a0-warm-keepalive.service \
  /etc/systemd/system/gxfp51a0-warm-keepalive.timer \
  /etc/systemd/system/timers.target.wants/gxfp51a0-warm-keepalive.timer

run_root mkdir -p "$STATE_DIR"
run_root rm -rf "$STATE_DIR/backup"
run_root cp -a "$TMP_STATE/backup" "$STATE_DIR/backup"
run_root install -m0644 "$TMP_STATE/manifest" "$STATE_DIR/manifest"
printf '%s\n' "$LIBDIR" > "$TMP_STATE/libdir"
run_root install -m0644 "$TMP_STATE/libdir" "$STATE_DIR/libdir"
run_root install -m0755 "$ROOT/uninstall-linux-source.sh" "$STATE_DIR/uninstall.sh"
if [[ -f "$TMP_STATE/created-early-wants" ]]; then
  run_root install -m0644 "$TMP_STATE/created-early-wants" "$STATE_DIR/created-early-wants"
fi

if (( ! SYSTEMD_AVAILABLE )); then
  run_root ldconfig
fi
if have udevadm; then
  run_root udevadm control --reload || true
  run_root udevadm trigger --subsystem-match=spi || true
  run_root udevadm settle --timeout=3 || true
fi

if (( SYSTEMD_AVAILABLE )); then
  run_root systemctl daemon-reload
  run_root systemctl restart fprintd.service
  if [[ -x "$KDE_HELPER_FILE" &&
        -f /usr/share/plasma/shells/org.kde.plasma.desktop/contents/lockscreen/LockScreenUi.qml ]]; then
    run_root "$KDE_HELPER_FILE" --apply || true
    run_root "$KDE_HELPER_FILE" --check || true
  fi
fi

echo
echo "GXFP51A0 portable installation complete."
echo "  distribution: $distro"
echo "  libfprint:     $LIBDIR/libfprint-2.so.2.0.0"
echo "  udev rule:     $UDEV_RULE_FILE"
echo "  systemd glue:  $([[ "$SYSTEMD_AVAILABLE" -eq 1 ]] && echo enabled || echo skipped)"
if (( SYSTEMD_AVAILABLE )); then
  echo "  library scope: fprintd only (LD_LIBRARY_PATH service override)"
else
  echo "  library scope: system loader fallback ($LDCONF_FILE)"
fi
echo "  rollback:      sudo $STATE_DIR/uninstall.sh"
echo
echo "Existing fingerprint enrollments and the validated PMK cache are untouched."
echo "Legacy rel24-rel40 timing files were removed; rel41 adaptation is RAM-only."
echo
echo "Standard tools:"
echo "  fprintd-list \"$USER\""
echo "  fprintd-enroll -f right-index-finger"
echo "  fprintd-verify"
