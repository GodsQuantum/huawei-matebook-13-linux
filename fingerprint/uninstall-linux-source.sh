#!/usr/bin/env bash
set -Eeuo pipefail
STATE_DIR="/var/lib/gxfp51a0-local-install"
DROPIN_FILE="/etc/systemd/system/fprintd.service.d/60-goodix51a0-local-lib.conf"
UDEV_RULE_FILE="/etc/udev/rules.d/70-libfprint-goodix51a0-local.rules"
BIND_HELPER="/usr/local/libexec/gxfp51a0-spidev-bind"
BIND_SERVICE="/etc/systemd/system/gxfp51a0-spidev-bind.service"

if (( EUID != 0 )); then
  echo "ERROR: run this rollback with sudo/root." >&2
  exit 2
fi
[[ -f "$STATE_DIR/manifest" ]] || {
  echo "ERROR: GXFP51A0 local-install manifest not found." >&2
  exit 3
}

mapfile -t paths < "$STATE_DIR/manifest"
for ((i=${#paths[@]}-1; i>=0; i--)); do
  path="${paths[i]}"
  if [[ -L "$path" || -f "$path" ]]; then
    rm -f -- "$path"
  elif [[ -d "$path" ]]; then
    rmdir --ignore-fail-on-non-empty "$path" 2>/dev/null || true
  fi
done

if [[ -d "$STATE_DIR/backup" ]]; then
  cp -a "$STATE_DIR/backup/." /
fi

rm -f "$DROPIN_FILE" "$UDEV_RULE_FILE" "$BIND_HELPER" "$BIND_SERVICE"
udevadm control --reload || true
rm -rf "$STATE_DIR"
ldconfig
systemctl daemon-reload
systemctl restart fprintd.service || true
echo "GXFP51A0 local source installation rolled back."
