#!/usr/bin/env bash
set -Eeuo pipefail
STATE_DIR="/var/lib/gxfp51a0-local-install"
DROPIN_FILE="/etc/systemd/system/fprintd.service.d/60-goodix51a0-local-lib.conf"
UDEV_RULE_FILE="/etc/udev/rules.d/70-libfprint-goodix51a0-local.rules"

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

if [[ -f "$STATE_DIR/created-early-wants" ]]; then
  EARLY_WANTS_LINK="$(cat "$STATE_DIR/created-early-wants")"
  [[ -n "$EARLY_WANTS_LINK" ]] && rm -f -- "$EARLY_WANTS_LINK"
fi

rm -f "$DROPIN_FILE" "$UDEV_RULE_FILE"
# Compatibility cleanup for the removed rel22 portable binder.
rm -f /usr/local/libexec/gxfp51a0-spidev-bind \
  /etc/systemd/system/gxfp51a0-spidev-bind.service

udevadm control --reload || true
rm -rf "$STATE_DIR"
ldconfig
systemctl daemon-reload
systemctl restart fprintd.service || true
echo "GXFP51A0 local source installation rolled back."
