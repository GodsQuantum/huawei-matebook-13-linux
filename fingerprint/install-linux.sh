#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BUILD_ROOT="${XDG_CACHE_HOME:-$HOME/.cache}/gxfp51a0-libfprint-build"
STATE_DIR="/var/lib/gxfp51a0-local-install"
PREFIX="/usr/local"
LIBEXEC_DIR="$PREFIX/libexec"
UDEV_RULE_FILE="/etc/udev/rules.d/70-libfprint-goodix51a0-local.rules"
DBUS_SERVICE_DIR="/etc/dbus-1/system-services"
DBUS_SERVICE_FILE="$DBUS_SERVICE_DIR/net.reactivated.Fprint.service"
FPRINTD_WRAPPER_FILE="$LIBEXEC_DIR/gxfp51a0-fprintd"

DROPIN_DIR="/etc/systemd/system/fprintd.service.d"
DROPIN_FILE="$DROPIN_DIR/60-goodix51a0-local.conf"
EARLY_WANTS_DIR="/etc/systemd/system/graphical.target.wants"
EARLY_WANTS_LINK="$EARLY_WANTS_DIR/fprintd.service"
BOOT_HELPER_FILE="$LIBEXEC_DIR/gxfp51a0-boot-prewarm"
BOOT_UNIT_FILE="/etc/systemd/system/gxfp51a0-boot-prewarm.service"
BOOT_WANTS_LINK="$EARLY_WANTS_DIR/gxfp51a0-boot-prewarm.service"
RESUME_HELPER_FILE="$LIBEXEC_DIR/gxfp51a0-resume-prewarm"
RESUME_HOOK_FILE="/etc/systemd/system-sleep/gxfp51a0-resume-prewarm"
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
      Do not invoke apt/dnf/zypper/pacman/apk. Useful on unsupported
      distributions after installing the required development packages manually.
  --no-desktop-integration
      Install only libfprint/udev plus fprintd runtime glue. Skip KDE helper.
  -h, --help
      Show this help.

Supported automatic dependency installers:
  Arch/CachyOS, Debian/Ubuntu, Fedora/RHEL-family, openSUSE, Alpine.

Other distributions are supported with --no-install-deps when they provide:
  gcc/clang, git, python3+venv, pkg-config, glib-2.0, gio-unix-2.0,
  gobject-2.0, gmodule-2.0, gusb, cairo, gudev-1.0, openssl, udev, pixman-1.

systemd is optional for the library itself. When systemd/fprintd.service exists,
boot-prewarm and a frozen-user-slice post-resume hook are installed automatically. On non-systemd
systems fprintd is isolated through a higher-priority D-Bus activation wrapper
under /etc/dbus-1/system-services; no global dynamic-linker override is needed.
The distribution's native PAM/desktop integration remains in charge.
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
elif have apk; then distro=alpine
fi

# Native Arch packaging is the cleanest system installation there.
if [[ "$distro" == arch && "$BUILD_ONLY" -eq 0 ]]; then
  exec "$ROOT/install-arch.sh"
fi

install_deps() {
  (( INSTALL_DEPS )) || return 0
  case "$distro" in
    arch)
      # A pristine Arch container has no sync databases yet. Real Arch/CachyOS
      # installation delegates to install-arch.sh before this branch, so this
      # refresh is restricted to build-only validation environments.
      if (( BUILD_ONLY )) && [[ ! -e /var/lib/pacman/sync/core.db && ! -e /var/lib/pacman/sync/core.db.tar.gz ]]; then
        run_root pacman -Sy --noconfirm
      fi
      run_root pacman -S --needed --noconfirm \
        base-devel git python python-pip pkgconf \
        glib2 glib2-devel libgusb cairo libgudev openssl systemd pixman fprintd
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
        libopenssl-devel systemd-devel libpixman-1-0-devel
      ;;
    alpine)
      run_root apk add --no-cache         fprintd fprintd-pam build-base git python3 py3-pip py3-virtualenv pkgconf         glib-dev libgusb-dev cairo-dev libgudev-dev openssl-dev eudev-dev         pixman-dev dbus
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

for cmd in git python3 cc pkg-config sha256sum nm strings ar ldd; do
  have "$cmd" || { echo "ERROR: missing required command: $cmd" >&2; exit 4; }
done

rm -rf -- "$BUILD_ROOT"
mkdir -p "$BUILD_ROOT"

GXFP51A0_BUILD_ROOT="$BUILD_ROOT" \
GXFP51A0_MESON_PREFIX="$PREFIX" \
  "$ROOT/scripts/build-libfprint-v1.94.100.sh"

MESON="$BUILD_ROOT/build-tools-venv/bin/meson"
BUILD_DIR="$BUILD_ROOT/libfprint-build"
STAGE="$BUILD_ROOT/stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
DESTDIR="$STAGE" "$MESON" install --no-rebuild -C "$BUILD_DIR"

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
DBUS_SERVICE_SRC=""

find_dbus_service() {
  local candidate
  for candidate in \
    /usr/share/dbus-1/system-services/net.reactivated.Fprint.service \
    /usr/lib/dbus-1/system-services/net.reactivated.Fprint.service \
    /lib/dbus-1/system-services/net.reactivated.Fprint.service \
    /usr/local/share/dbus-1/system-services/net.reactivated.Fprint.service \
    /etc/dbus-1/system-services/net.reactivated.Fprint.service; do
    [[ -f "$candidate" ]] && { printf '%s\n' "$candidate"; return 0; }
  done
  return 1
}

if have systemctl; then
  FPRINTD_UNIT="$(systemctl show -p FragmentPath --value fprintd.service 2>/dev/null || true)"
  if [[ -n "$FPRINTD_UNIT" && -f "$FPRINTD_UNIT" ]]; then
    SYSTEMD_AVAILABLE=1
    FPRINTD_BIN="$(systemctl show -p ExecStart --value fprintd.service 2>/dev/null |
      sed -n 's/.*path=\([^ ;}]*\).*/\1/p' | head -n1)"
  fi
fi

DBUS_SERVICE_SRC="$(find_dbus_service || true)"
if [[ -z "$FPRINTD_BIN" || ! -x "$FPRINTD_BIN" ]]; then
  if [[ -n "$DBUS_SERVICE_SRC" ]]; then
    FPRINTD_BIN="$(sed -n 's/^[[:space:]]*Exec=\([^[:space:]]*\).*/\1/p' "$DBUS_SERVICE_SRC" | head -n1)"
  fi
fi
if [[ -z "$FPRINTD_BIN" || ! -x "$FPRINTD_BIN" ]]; then
  FPRINTD_BIN="$(command -v fprintd 2>/dev/null || true)"
fi
if [[ -z "$FPRINTD_BIN" || ! -x "$FPRINTD_BIN" ]]; then
  for candidate in /usr/lib/fprintd /usr/libexec/fprintd /usr/lib/fprintd/fprintd /usr/sbin/fprintd; do
    [[ -x "$candidate" ]] && { FPRINTD_BIN="$candidate"; break; }
  done
fi
[[ -n "$FPRINTD_BIN" && -x "$FPRINTD_BIN" ]] || {
  echo "ERROR: installed fprintd daemon executable could not be resolved." >&2
  exit 6
}

# ABI/load gate: prove the distro fprintd can actually start against the staged
# custom libfprint before making any system change. This catches future distro
# fprintd builds that require symbols newer than pinned libfprint v1.94.100.
ABI_LOG="$BUILD_ROOT/fprintd-abi-check.txt"
STAGED_LD_PATH="$STAGE$LIBDIR"
ABI_ENV="LD_LIBRARY_PATH=$STAGED_LD_PATH${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# glibc's ldd supports -r and reports unresolved relocations directly. musl's
# ldd is the dynamic loader and treats "-r" as a filename, so use ordinary ldd
# there and force eager relocation with LD_BIND_NOW=1 below.
if env "$ABI_ENV" ldd -r "$FPRINTD_BIN" >"$ABI_LOG" 2>&1; then
  echo "FPRINTD_ABI_LDD_MODE=relocations"
else
  if ! env "$ABI_ENV" ldd "$FPRINTD_BIN" >"$ABI_LOG" 2>&1; then
    cat "$ABI_LOG" >&2
    echo "ERROR: distro fprintd failed dynamic-link validation against staged libfprint." >&2
    exit 7
  fi
  echo "FPRINTD_ABI_LDD_MODE=dependency-only"
fi
if grep -Eqi 'undefined symbol|not found|Error relocating' "$ABI_LOG"; then
  cat "$ABI_LOG" >&2
  echo "ERROR: staged libfprint is ABI-incompatible with distro fprintd." >&2
  exit 7
fi
grep -Fq "$STAGE$LIBDIR" "$ABI_LOG" || {
  cat "$ABI_LOG" >&2
  echo "ERROR: ABI check did not resolve libfprint from the staged candidate." >&2
  exit 7
}
if ! env "$ABI_ENV" LD_BIND_NOW=1 "$FPRINTD_BIN" --help >/dev/null 2>&1; then
  echo "ERROR: distro fprintd cannot execute with the staged libfprint." >&2
  exit 7
fi
echo "FPRINTD_ABI_COMPATIBILITY=PASS"

if (( BUILD_ONLY )); then
  echo "BUILD_ONLY=PASS"
  echo "Build tree: $BUILD_ROOT/libfprint-build"
  echo "Staged lib: $STAGE$LIBDIR/libfprint-2.so.2.0.0"
  exit 0
fi

if ! grep -Rqs '^acpi:GXFP51A0:' /sys/bus/spi/devices/*/modalias 2>/dev/null; then
  echo "ERROR: ACPI/SPI device GXFP51A0 was not found; refusing system install." >&2
  exit 5
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
if (( SYSTEMD_AVAILABLE )); then
  printf '%s\n' \
    "$DROPIN_FILE" "$BOOT_HELPER_FILE" "$BOOT_UNIT_FILE" "$BOOT_WANTS_LINK" \
    "$RESUME_HELPER_FILE" "$RESUME_HOOK_FILE" \
    >> "$TMP_STATE/manifest"
else
  printf '%s\n' "$DBUS_SERVICE_FILE" "$FPRINTD_WRAPPER_FILE" >> "$TMP_STATE/manifest"
fi
if (( ! NO_DESKTOP_INTEGRATION )); then
  printf '%s\n' "$KDE_HELPER_FILE" >> "$TMP_STATE/manifest"
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
run_root install -Dm0644 "$UDEV_RULE_SRC" "$UDEV_RULE_FILE"

if (( ! SYSTEMD_AVAILABLE )); then
  cat > "$TMP_STATE/fprintd-wrapper" <<EOF
#!/bin/sh
export LD_LIBRARY_PATH="$LIBDIR\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
exec "$FPRINTD_BIN" --no-timeout "\$@"
EOF
  run_root install -Dm0755 "$TMP_STATE/fprintd-wrapper" "$FPRINTD_WRAPPER_FILE"

  cat > "$TMP_STATE/fprintd-dbus.service" <<EOF
[D-BUS Service]
Name=net.reactivated.Fprint
Exec=$FPRINTD_WRAPPER_FILE
User=root
EOF
  run_root install -Dm0644 "$TMP_STATE/fprintd-dbus.service" "$DBUS_SERVICE_FILE"
fi

# Fedora/RHEL and other SELinux systems may label /usr/local more strictly than
# the build staging tree. Re-apply the distro's canonical contexts when the
# tool is available; this is a no-op elsewhere.
if have restorecon; then
  run_root restorecon -RF "$PREFIX" "$UDEV_RULE_FILE" || true
fi

# rel42 migration: rel24-rel40 timing integers are known to be contaminated by
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
  sed "s#/usr/libexec/gxfp51a0-resume-prewarm#$RESUME_HELPER_FILE#" \
    "$ROOT/integration/resume-prewarm/gxfp51a0-system-sleep" > "$TMP_STATE/resume-system-sleep"
  run_root install -Dm0755 "$TMP_STATE/resume-system-sleep" "$RESUME_HOOK_FILE"

  run_root mkdir -p "$EARLY_WANTS_DIR"
  if [[ ! -e "$EARLY_WANTS_LINK" && ! -L "$EARLY_WANTS_LINK" ]]; then
    run_root ln -s "$FPRINTD_UNIT" "$EARLY_WANTS_LINK"
    printf '%s\n' "$EARLY_WANTS_LINK" > "$TMP_STATE/created-early-wants"
  fi
  run_root ln -sfn "$BOOT_UNIT_FILE" "$BOOT_WANTS_LINK"

fi

if (( ! NO_DESKTOP_INTEGRATION )); then
  run_root install -Dm0755 "$ROOT/integration/kde-lockscreen/gxfp51a0-kde-lockscreen-integrate" "$KDE_HELPER_FILE"
fi

# Remove obsolete local glue from older portable releases.
run_root rm -f \
  /usr/local/libexec/gxfp51a0-spidev-bind \
  /etc/systemd/system/gxfp51a0-spidev-bind.service \
  /usr/local/libexec/gxfp51a0-warm-keepalive \
  /etc/systemd/system/gxfp51a0-warm-keepalive.service \
  /etc/systemd/system/gxfp51a0-warm-keepalive.timer \
  /etc/systemd/system/timers.target.wants/gxfp51a0-warm-keepalive.timer \
  /etc/systemd/system/gxfp51a0-resume-prewarm.service \
  /etc/systemd/system/gxfp51a0-resume-prewarm-worker.service \
  /etc/systemd/system/sleep.target.wants/gxfp51a0-resume-prewarm.service

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
  if have dbus-send; then
    run_root dbus-send --system --type=method_call \
      --dest=org.freedesktop.DBus /org/freedesktop/DBus \
      org.freedesktop.DBus.ReloadConfig >/dev/null 2>&1 || true
  fi
  # Ensure the next activation uses the isolated wrapper. A native init service
  # that immediately respawns fprintd will be detected below.
  run_root pkill -TERM -x fprintd 2>/dev/null || true
  sleep 0.2
  if pgrep -x fprintd >/dev/null 2>&1; then
    echo "WARNING: fprintd was respawned by the distro init system; configure that service" >&2
    echo "         to execute $FPRINTD_WRAPPER_FILE for isolated libfprint loading." >&2
  fi
fi
if have udevadm; then
  run_root udevadm control --reload || true
  run_root udevadm trigger --subsystem-match=spi || true
  run_root udevadm settle --timeout=3 || true
fi

if (( SYSTEMD_AVAILABLE )); then
  run_root systemctl daemon-reload
  run_root systemctl restart fprintd.service
fi
if [[ -x "$KDE_HELPER_FILE" &&
      -f /usr/share/plasma/shells/org.kde.plasma.desktop/contents/lockscreen/LockScreenUi.qml ]]; then
  run_root "$KDE_HELPER_FILE" --apply || true
  run_root "$KDE_HELPER_FILE" --check || true
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
  echo "  library scope: fprintd only (D-Bus activation wrapper)"
fi
echo "  rollback:      sudo $STATE_DIR/uninstall.sh"
echo
echo "Existing fingerprint enrollments and the validated PMK cache are untouched."
echo "Legacy rel24-rel40 timing files were removed; rel42 adaptation is RAM-only."
echo
echo "Standard tools:"
echo "  fprintd-list \"$USER\""
echo "  fprintd-enroll -f right-index-finger"
echo "  fprintd-verify"
