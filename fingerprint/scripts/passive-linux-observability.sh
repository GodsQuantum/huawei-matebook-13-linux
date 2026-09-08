#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FP_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd -- "$FP_DIR/.." && pwd)"
OUT_BASE="${GXFP51A0_AUDIT_ROOT:-$REPO_ROOT/../temp}"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$OUT_BASE/gxfp51a0-passive-linux-$STAMP"

mkdir -p "$OUT"

capture() {
  local name="$1"; shift
  {
    printf '$'
    printf ' %q' "$@"
    printf '\n'
    "$@"
  } >"$OUT/$name.txt" 2>&1 || true
}

copy_readonly() {
  local src="$1" dst="$2"
  [[ -r "$src" ]] && cat -- "$src" >"$OUT/$dst" 2>/dev/null || true
}

{
  echo "GXFP51A0_PASSIVE_LINUX_OBSERVABILITY"
  echo "TIMESTAMP=$STAMP"
  echo "ACTIVE_SENSOR_IO=NONE"
  echo "GPIO_WRITES=NONE"
  echo "MMIO_WRITES=NONE"
  echo "FIRMWARE_ACTIONS=NONE"
  echo "DRIVER_BIND_UNBIND=NONE"
  echo "MODULE_LOAD_UNLOAD=NONE"
  echo "POWER_STATE_WRITES=NONE"
} >"$OUT/SUMMARY.txt"

capture uname uname -a
capture kernel_cmdline cat /proc/cmdline
capture lsmod lsmod
capture proc_interrupts cat /proc/interrupts
capture proc_iomem cat /proc/iomem

command -v lspci >/dev/null 2>&1 && capture lspci lspci -nnk
command -v lsmod >/dev/null 2>&1 || true
command -v gpioinfo >/dev/null 2>&1 && capture gpioinfo gpioinfo

for dev in /sys/bus/acpi/devices/GXFP51A0:*; do
  [[ -e "$dev" ]] || continue
  {
    echo "PATH=$dev"
    find "$dev" -maxdepth 2 -type l -printf '%p -> %l\n' 2>/dev/null || true
  } >>"$OUT/acpi-device.txt"
  for f in hid modalias path status uid uevent; do
    [[ -r "$dev/$f" ]] && {
      echo "===== $dev/$f ====="
      cat "$dev/$f"
    } >>"$OUT/acpi-device.txt" 2>/dev/null || true
  done
done

for dev in /sys/bus/spi/devices/*GXFP51A0*; do
  [[ -e "$dev" ]] || continue
  {
    echo "PATH=$dev"
    readlink -f "$dev/driver" 2>/dev/null || true
    find "$dev" -maxdepth 2 -type l -printf '%p -> %l\n' 2>/dev/null || true
  } >>"$OUT/spi-device.txt"
  for f in modalias uevent power/runtime_status power/control power/runtime_active_time power/runtime_suspended_time; do
    [[ -r "$dev/$f" ]] && {
      echo "===== $dev/$f ====="
      cat "$dev/$f"
    } >>"$OUT/spi-device.txt" 2>/dev/null || true
  done
done

for root in /sys/kernel/debug/pinctrl /sys/kernel/debug/gpio; do
  [[ -r "$root" ]] || continue
  if [[ -d "$root" ]]; then
    find "$root" -maxdepth 2 -type f -readable -print 2>/dev/null |
      while read -r f; do
        echo "===== $f ====="
        cat "$f" 2>/dev/null || true
      done >>"$OUT/debugfs-pinctrl.txt"
  else
    cat "$root" >"$OUT/debugfs-gpio.txt" 2>/dev/null || true
  fi
done

if command -v journalctl >/dev/null 2>&1; then
  journalctl -k -b --no-pager 2>/dev/null |
    grep -Ei 'GXFP51A0|Goodix|pxa2xx|spi1|idma|lpss|INT34' \
    >"$OUT/kernel-relevant.txt" || true
fi

tarball="$OUT_BASE/gxfp51a0-passive-linux-$STAMP.tar.gz"
tar -C "$OUT_BASE" -czf "$tarball" "$(basename "$OUT")"

{
  echo "PASSIVE_AUDIT=COMPLETE"
  echo "OUTPUT_DIR=$OUT"
  echo "BUNDLE=$tarball"
  echo "NEXT=ATTACH_BUNDLE_TO_GITHUB_ISSUE_OR_RESEARCH_CHAT"
} | tee -a "$OUT/SUMMARY.txt"

echo "ACTIVE_SENSOR_IO=NONE"
echo "GPIO_WRITES=NONE"
echo "MMIO_WRITES=NONE"
echo "FIRMWARE_ACTIONS=NONE"
