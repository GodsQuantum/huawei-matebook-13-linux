#!/usr/bin/env bash
set -Eeuo pipefail

STATE_DIR="/var/lib/gxfp51a0-local-install"
DROPIN_FILE="/etc/systemd/system/fprintd.service.d/60-goodix51a0-local.conf"
UDEV_RULE_FILE="/etc/udev/rules.d/70-libfprint-goodix51a0-local.rules"
DBUS_SERVICE_FILE="/etc/dbus-1/system-services/net.reactivated.Fprint.service"
FPRINTD_WRAPPER_FILE="/usr/local/libexec/gxfp51a0-fprintd"
# Compatibility cleanup only: rel41 briefly used a global loader fallback.
LEGACY_LDCONF_FILE="/etc/ld.so.conf.d/90-gxfp51a0-local.conf"
KDE_HELPER="/usr/local/libexec/gxfp51a0-kde-lockscreen-integrate"

if (( EUID != 0 )); then
  echo "ERROR: run this rollback with sudo/root." >&2
  exit 2
fi

[[ -f "$STATE_DIR/manifest" ]] || {
  echo "ERROR: GXFP51A0 local-install manifest not found." >&2
  exit 3
}

if [[ -x "$KDE_HELPER" ]]; then
  "$KDE_HELPER" --remove || true
fi

# Stop only obsolete services from older portable releases. rel42 has no
# periodic keepalive.
if command -v systemctl >/dev/null 2>&1; then
  systemctl stop gxfp51a0-warm-keepalive.timer                  gxfp51a0-warm-keepalive.service 2>/dev/null || true
fi

mapfile -t paths < "$STATE_DIR/manifest"
for ((i=${#paths[@]}-1; i>=0; i--)); do
  path="${paths[i]}"
  if [[ -L "$path" || -f "$path" ]]; then
    rm -f -- "$path"
  elif [[ -d "$path" ]]; then
    rmdir --ignore-fail-on-non-empty "$path" 2>/dev/null || true
  fi
done

# Restore any distro-owned files that existed before the source install.
if [[ -d "$STATE_DIR/backup" ]]; then
  cp -a "$STATE_DIR/backup/." /
fi

if [[ -f "$STATE_DIR/created-early-wants" ]]; then
  early="$(cat "$STATE_DIR/created-early-wants")"
  [[ -n "$early" ]] && rm -f -- "$early"
fi

# Compatibility cleanup for older installer generations.
rm -f "$DROPIN_FILE" "$UDEV_RULE_FILE" "$DBUS_SERVICE_FILE"   "$FPRINTD_WRAPPER_FILE" "$LEGACY_LDCONF_FILE"   /usr/local/libexec/gxfp51a0-spidev-bind   /etc/systemd/system/gxfp51a0-spidev-bind.service   /usr/local/libexec/gxfp51a0-warm-keepalive   /etc/systemd/system/gxfp51a0-warm-keepalive.service   /etc/systemd/system/gxfp51a0-warm-keepalive.timer   /etc/systemd/system/timers.target.wants/gxfp51a0-warm-keepalive.timer   /usr/local/libexec/gxfp51a0-resume-prewarm   /etc/systemd/system-sleep/gxfp51a0-resume-prewarm

if command -v udevadm >/dev/null 2>&1; then
  udevadm control --reload || true
  udevadm trigger --subsystem-match=spi || true
fi

# rel41's legacy ld.so file may have populated the loader cache. Refresh it only
# when ldconfig exists; rel42 itself never installs a global loader override.
if command -v ldconfig >/dev/null 2>&1; then
  ldconfig || true
fi

if command -v dbus-send >/dev/null 2>&1; then
  dbus-send --system --type=method_call     --dest=org.freedesktop.DBus /org/freedesktop/DBus     org.freedesktop.DBus.ReloadConfig >/dev/null 2>&1 || true
fi

if command -v systemctl >/dev/null 2>&1 &&    systemctl cat fprintd.service >/dev/null 2>&1; then
  systemctl daemon-reload || true
  systemctl restart fprintd.service || true
else
  # Let the next D-Bus request activate the restored distro service definition.
  pkill -TERM -x fprintd 2>/dev/null || true
fi

rm -rf "$STATE_DIR"
echo "GXFP51A0 local source installation rolled back."
