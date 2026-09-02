#!/usr/bin/env bash
# Huawei MateBook 13 GPU Manager
# SPDX-License-Identifier: GPL-2.0-only
#
# On-demand NVIDIA MX250 (GP108M, PCI ID 10de:1d13) power management for
# Huawei MateBook 13 laptops. The validated design keeps the dGPU removed from
# PCI while idle, hot-rescans it only for selected applications, uses PRIME
# Render Offload, then unloads NVIDIA and removes the device again.
#
# UI: English/French. Distribution support is best-effort for Arch/CachyOS,
# Fedora and Debian/Ubuntu families. Plasma Wayland is the validated desktop.

set -Eeuo pipefail
shopt -s nullglob

VERSION="2.0.0"
SELF="$(readlink -f "${BASH_SOURCE[0]}")"

# Public hardware target: NVIDIA GP108M / GeForce MX250.
DGPU_VENDOR="0x10de"
DGPU_DEVICE="0x1d13"

SYSTEM_CONFIG="/etc/huawei-matebook-gpu-manager.conf"
MODPROBE_CONFIG="/etc/modprobe.d/huawei-matebook-gpu-manager.conf"
POWER_HELPER="/usr/local/sbin/huawei-matebook-dgpu-power"
RUNNER="/usr/local/bin/huawei-matebook-dgpu-run"
SUDOERS_FILE="/etc/sudoers.d/huawei-matebook-dgpu"
BOOT_SERVICE="/etc/systemd/system/huawei-matebook-dgpu-off.service"
UDEV_RULE="/etc/udev/rules.d/61-huawei-matebook-igpu.rules"
INTEL_ALIAS="/dev/dri/huawei-matebook-intel"

STATE_DIR="$HOME/.local/state/huawei-matebook-gpu-manager"
DESKTOP_STATE_DIR="$STATE_DIR/desktop"
STEAM_STATE_DIR="$STATE_DIR/steam"
LOCAL_APPS="$HOME/.local/share/applications"
KWIN_DROPIN_DIR="$HOME/.config/systemd/user/plasma-kwin_wayland.service.d"
KWIN_DROPIN="$KWIN_DROPIN_DIR/61-huawei-matebook-igpu.conf"
CLEANUP_SERVICE_DIR="$HOME/.config/systemd/user"
CLEANUP_SERVICE="$CLEANUP_SERVICE_DIR/huawei-matebook-dgpu-cleanup.service"
CLEANUP_TIMER="$CLEANUP_SERVICE_DIR/huawei-matebook-dgpu-cleanup.timer"

# The managed app list intentionally lives in this script so keeping one file
# is enough to recreate the app selection after a Linux reinstall.
# === HUAWEI_GPU_CONFIG_BEGIN ===
MANAGED_DESKTOP_APPS=(
)
MANAGED_STEAM_APPS=(
)
STEAM_ALL=0
# === HUAWEI_GPU_CONFIG_END ===

LANG_CHOICE=""
FORCE_UNSUPPORTED=0
AUTO_YES=0

# ---------------------------------------------------------------------------
# i18n
# ---------------------------------------------------------------------------

choose_language() {
    if [[ -n "$LANG_CHOICE" ]]; then return; fi
    case "${LC_ALL:-${LC_MESSAGES:-${LANG:-en}}}" in
        fr*|FR*) LANG_CHOICE="fr" ;;
        *)       LANG_CHOICE="en" ;;
    esac
}

msg() {
    local key="$1"; shift || true
    choose_language
    case "$LANG_CHOICE:$key" in
        fr:need_user) echo "Lance ce script avec ton utilisateur normal, pas avec sudo." ;;
        en:need_user) echo "Run this script as your normal user, not with sudo." ;;
        fr:install_title) echo "Installation / réparation de la gestion GPU à la demande" ;;
        en:install_title) echo "Install / repair on-demand GPU management" ;;
        fr:unsupported) echo "Matériel non validé. Ce script cible un Huawei avec NVIDIA GeForce MX250 (10de:1d13)." ;;
        en:unsupported) echo "Unsupported hardware. This script targets Huawei hardware with NVIDIA GeForce MX250 (10de:1d13)." ;;
        fr:reboot) echo "Redémarrage requis avant le premier lancement GPU à la demande." ;;
        en:reboot) echo "A reboot is required before the first on-demand GPU launch." ;;
        fr:steam_close) echo "Ferme complètement Steam avant de modifier ses Launch Options." ;;
        en:steam_close) echo "Fully exit Steam before changing its Launch Options." ;;
        fr:no_app) echo "Aucune application trouvée." ;;
        en:no_app) echo "No application found." ;;
        fr:press_enter) echo "Entrée pour continuer..." ;;
        en:press_enter) echo "Press Enter to continue..." ;;
        fr:confirm) echo "Confirmer ?" ;;
        en:confirm) echo "Continue?" ;;
        fr:install_done) echo "Configuration installée. Le mode au repos reste full Integrated (dGPU retirée du PCI)." ;;
        en:install_done) echo "Configuration installed. Idle mode remains full Integrated (dGPU removed from PCI)." ;;
        fr:plasma_warn) echo "Plasma Wayland n'a pas été détecté. Le mécanisme est installé mais le desktop courant n'est pas validé; le runner refusera de lancer si le compositeur accroche la NVIDIA." ;;
        en:plasma_warn) echo "Plasma Wayland was not detected. The core is installed, but this desktop is not validated; the runner will refuse to launch if the compositor grabs NVIDIA." ;;
        fr:driver_missing) echo "Pilote NVIDIA R580 introuvable. La MX250/Pascal n'est plus supportée par les branches NVIDIA 590+; installe R580 puis relance." ;;
        en:driver_missing) echo "NVIDIA R580 driver not found. MX250/Pascal is no longer supported by NVIDIA 590+; install R580 and run again." ;;
        fr:unknown) echo "$*" ;;
        en:unknown) echo "$*" ;;
        *) echo "$*" ;;
    esac
}

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
info() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
err()  { printf '[ERROR] %s\n' "$*" >&2; }
line() { printf '%s\n' '-------------------------------------------------------------------------------'; }

pause() {
    [[ -t 0 ]] || return 0
    local p; p="$(msg press_enter)"
    read -r -p "$p " _ || true
}

confirm() {
    [[ "$AUTO_YES" == 1 ]] && return 0
    [[ -t 0 ]] || return 1
    local p a
    p="${1:-$(msg confirm)}"
    if [[ "$LANG_CHOICE" == fr ]]; then
        read -r -p "$p [o/N] " a || true
        [[ "$a" =~ ^[oOyY]$ ]]
    else
        read -r -p "$p [y/N] " a || true
        [[ "$a" =~ ^[yYoO]$ ]]
    fi
}

if [[ $EUID -eq 0 ]]; then
    err "$(msg need_user)"
    exit 1
fi

USER_NAME="$(id -un)"
USER_UID="$(id -u)"

# ---------------------------------------------------------------------------
# generic helpers
# ---------------------------------------------------------------------------

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || { err "Missing command: $1"; return 1; }
}

ensure_dirs() {
    mkdir -p "$LOCAL_APPS" "$DESKTOP_STATE_DIR" "$STEAM_STATE_DIR" "$CLEANUP_SERVICE_DIR"
}

array_has() {
    local needle="$1"; shift
    local x
    for x in "$@"; do [[ "$x" == "$needle" ]] && return 0; done
    return 1
}

# ---------------------------------------------------------------------------
# config persisted inside this script
# ---------------------------------------------------------------------------

persist_config() {
    local kind="$1" action="$2" value="${3:-}"
    python3 - "$SELF" "$kind" "$action" "$value" <<'PY'
import os, re, sys, tempfile
from pathlib import Path

path = Path(sys.argv[1])
kind, action, value = sys.argv[2:5]
text = path.read_text(encoding="utf-8")
m = re.search(r"(?ms)^# === HUAWEI_GPU_CONFIG_BEGIN ===\n(.*?)^# === HUAWEI_GPU_CONFIG_END ===$", text)
if not m:
    raise SystemExit("embedded config block not found")
block = m.group(1)

def parse_array(name):
    mm = re.search(rf"(?ms)^{re.escape(name)}=\(\n(.*?)^\)$", block)
    if not mm:
        return []
    out=[]
    for line in mm.group(1).splitlines():
        line=line.strip()
        q=re.match(r'^"(.*)"$', line)
        if q:
            out.append(q.group(1).replace('\\"','"').replace('\\\\','\\'))
    return out

def emit(name, vals):
    body="\n".join('  "'+v.replace('\\','\\\\').replace('"','\\"')+'"' for v in vals)
    return f"{name}=(\n{body + chr(10) if body else ''})"

desktop=parse_array("MANAGED_DESKTOP_APPS")
steam=parse_array("MANAGED_STEAM_APPS")
sm=re.search(r"(?m)^STEAM_ALL=(\d+)$", block)
steam_all=int(sm.group(1)) if sm else 0

if kind == "desktop": arr=desktop
elif kind == "steam": arr=steam
elif kind == "steam-all": arr=None
else: raise SystemExit("unknown config type")

if arr is not None:
    if action == "add" and value not in arr: arr.append(value)
    elif action == "remove": arr[:] = [x for x in arr if x != value]
else:
    steam_all = 1 if action in ("1","on","enable") else 0

new_block = emit("MANAGED_DESKTOP_APPS", desktop)+"\n"+emit("MANAGED_STEAM_APPS", steam)+"\n"+f"STEAM_ALL={steam_all}\n"
new = text[:m.start(1)] + new_block + text[m.end(1):]
st=path.stat()
fd,tmp=tempfile.mkstemp(prefix=path.name+".",dir=path.parent)
try:
    with os.fdopen(fd,"w",encoding="utf-8") as f: f.write(new)
    os.chmod(tmp, st.st_mode)
    os.replace(tmp,path)
finally:
    if os.path.exists(tmp): os.unlink(tmp)
PY
}

remember_desktop() {
    local id="$1"
    array_has "$id" "${MANAGED_DESKTOP_APPS[@]:-}" || {
        persist_config desktop add "$id"
        MANAGED_DESKTOP_APPS+=("$id")
    }
}
forget_desktop() {
    local id="$1" x new=()
    persist_config desktop remove "$id"
    for x in "${MANAGED_DESKTOP_APPS[@]:-}"; do [[ "$x" != "$id" ]] && new+=("$x"); done
    MANAGED_DESKTOP_APPS=("${new[@]}")
}
remember_steam() {
    local id="$1"
    array_has "$id" "${MANAGED_STEAM_APPS[@]:-}" || {
        persist_config steam add "$id"
        MANAGED_STEAM_APPS+=("$id")
    }
}
forget_steam() {
    local id="$1" x new=()
    persist_config steam remove "$id"
    for x in "${MANAGED_STEAM_APPS[@]:-}"; do [[ "$x" != "$id" ]] && new+=("$x"); done
    MANAGED_STEAM_APPS=("${new[@]}")
}

# ---------------------------------------------------------------------------
# hardware discovery
# ---------------------------------------------------------------------------

pci_find() {
    local vendor="$1" device="${2:-}" class_prefix="${3:-}"
    local d v x c
    for d in /sys/bus/pci/devices/*; do
        [[ -r "$d/vendor" ]] || continue
        v="$(<"$d/vendor")"
        [[ "${v,,}" == "${vendor,,}" ]] || continue
        if [[ -n "$device" ]]; then
            x="$(<"$d/device")"
            [[ "${x,,}" == "${device,,}" ]] || continue
        fi
        if [[ -n "$class_prefix" ]]; then
            c="$(<"$d/class")"
            [[ "${c,,}" == "${class_prefix,,}"* ]] || continue
        fi
        basename "$d"
    done
}

find_dgpu_bdf() { pci_find "$DGPU_VENDOR" "$DGPU_DEVICE" "0x03" | head -n1; }
find_igpu_bdf() { pci_find "0x8086" "" "0x03" | head -n1; }

rescan_pci() { echo 1 | sudo tee /sys/bus/pci/rescan >/dev/null; }

hardware_discover() {
    local initial_gpu=0 dgpu="" igpu="" root="" vendor="" product=""
    [[ -r /sys/class/dmi/id/sys_vendor ]] && vendor="$(</sys/class/dmi/id/sys_vendor)"
    [[ -r /sys/class/dmi/id/product_name ]] && product="$(</sys/class/dmi/id/product_name)"

    dgpu="$(find_dgpu_bdf || true)"
    if [[ -z "$dgpu" ]]; then
        initial_gpu=1
        info "MX250 is not currently enumerated; performing a temporary PCI rescan for discovery."
        rescan_pci
        sleep 1
        dgpu="$(find_dgpu_bdf || true)"
    fi
    igpu="$(find_igpu_bdf || true)"

    if [[ -z "$dgpu" || -z "$igpu" ]]; then
        [[ "$initial_gpu" == 1 && -n "$dgpu" && -e "/sys/bus/pci/devices/$dgpu/remove" ]] && echo 1 | sudo tee "/sys/bus/pci/devices/$dgpu/remove" >/dev/null || true
        err "$(msg unsupported)"
        return 1
    fi

    local sys="/sys/bus/pci/devices/$dgpu"
    root="$(basename "$(dirname "$(readlink -f "$sys")")")"
    if [[ ! "$root" =~ ^0000:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-7]$ ]]; then
        err "Unable to determine the dGPU PCIe root port."
        return 1
    fi

    if [[ "${vendor,,}" != *huawei* && "$FORCE_UNSUPPORTED" != 1 ]]; then
        err "DMI vendor is '${vendor:-unknown}', not Huawei. Use --force-unsupported only for deliberate testing."
        return 1
    fi

    info "DMI: ${vendor:-unknown} ${product:-unknown}"
    info "Intel GPU: $igpu"
    info "MX250: $dgpu (10de:1d13)"
    info "MX250 root port: $root"

    printf 'IGPU_BDF=%q\nDGPU_BDF=%q\nDGPU_ROOT_BDF=%q\nDGPU_VENDOR=%q\nDGPU_DEVICE=%q\n' \
        "$igpu" "$dgpu" "$root" "$DGPU_VENDOR" "$DGPU_DEVICE" > "$STATE_DIR/discovered.conf"

    if [[ "$initial_gpu" == 1 && -e "/sys/bus/pci/devices/$dgpu/remove" ]]; then
        echo 1 | sudo tee "/sys/bus/pci/devices/$dgpu/remove" >/dev/null
        sleep 1
    fi
}

load_discovered() {
    if [[ -r "$SYSTEM_CONFIG" ]]; then
        # shellcheck disable=SC1090
        source "$SYSTEM_CONFIG"
    elif [[ -r "$STATE_DIR/discovered.conf" ]]; then
        # shellcheck disable=SC1090
        source "$STATE_DIR/discovered.conf"
    else
        return 1
    fi
}

# ---------------------------------------------------------------------------
# packages / distro
# ---------------------------------------------------------------------------

os_release() {
    [[ -r /etc/os-release ]] || return 1
    # shellcheck disable=SC1091
    source /etc/os-release
}

pm_family() {
    os_release || true
    if command -v pacman >/dev/null 2>&1; then echo arch
    elif command -v dnf >/dev/null 2>&1; then echo fedora
    elif command -v apt-get >/dev/null 2>&1; then echo debian
    else echo unknown
    fi
}

nvidia_580_ready() {
    local v=""
    v="$(modinfo -F version nvidia 2>/dev/null | head -n1 || true)"
    [[ "$v" == 580.* ]]
}

install_common_packages() {
    local pm="$1"
    case "$pm" in
        arch)
            sudo pacman -S --needed --noconfirm pciutils psmisc util-linux python sudo 2>/dev/null || \
            sudo pacman -S --needed pciutils psmisc util-linux python sudo
            ;;
        fedora)
            sudo dnf install -y pciutils psmisc util-linux python3 sudo
            ;;
        debian)
            sudo apt-get update
            sudo apt-get install -y pciutils psmisc util-linux python3 sudo
            ;;
        *) err "Unsupported package manager."; return 1 ;;
    esac
}

install_nvidia_580_arch() {
    local installer=""
    if pacman -Q nvidia-580xx-dkms >/dev/null 2>&1 && pacman -Q nvidia-580xx-utils >/dev/null 2>&1; then return 0; fi
    if pacman -Si nvidia-580xx-dkms >/dev/null 2>&1; then
        sudo pacman -S --needed nvidia-580xx-dkms nvidia-580xx-utils
    else
        command -v paru >/dev/null 2>&1 && installer="paru"
        [[ -z "$installer" ]] && command -v yay >/dev/null 2>&1 && installer="yay"
        if [[ -z "$installer" ]]; then
            err "Arch requires the legacy R580 packages for Pascal. Install an AUR helper, then install nvidia-580xx-dkms and nvidia-580xx-utils."
            return 2
        fi
        "$installer" -S --needed nvidia-580xx-dkms nvidia-580xx-utils
    fi

    local kernel_pkg headers
    kernel_pkg="$(pacman -Qqo "/usr/lib/modules/$(uname -r)" 2>/dev/null | head -n1 || true)"
    headers="${kernel_pkg:+${kernel_pkg}-headers}"
    if [[ -n "$headers" ]] && pacman -Si "$headers" >/dev/null 2>&1; then
        sudo pacman -S --needed "$headers"
    fi
}

install_nvidia_580_fedora() {
    if rpm -qa | grep -q '^akmod-nvidia-580xx'; then return 0; fi
    if ! dnf -q repoquery --available akmod-nvidia-580xx >/dev/null 2>&1; then
        err "Fedora needs RPM Fusion Nonfree with the 580xx legacy driver. Enable RPM Fusion first; the script will not add third-party repositories silently."
        return 2
    fi
    sudo dnf install -y akmod-nvidia-580xx xorg-x11-drv-nvidia-580xx xorg-x11-drv-nvidia-580xx-cuda
    command -v akmods >/dev/null 2>&1 && sudo akmods --force || true
}

install_nvidia_580_debian() {
    if dpkg-query -W -f='${Status}' nvidia-driver-580 2>/dev/null | grep -q 'install ok installed'; then return 0; fi
    if apt-cache show nvidia-driver-580 >/dev/null 2>&1; then
        sudo apt-get install -y nvidia-driver-580
    else
        err "This Debian/Ubuntu release does not expose nvidia-driver-580 in enabled repositories. Install NVIDIA R580 manually; do not install 590+ for MX250/Pascal."
        return 2
    fi
}

install_graphics_tools() {
    local pm="$1"
    case "$pm" in
        arch) sudo pacman -S --needed mesa-utils vulkan-tools 2>/dev/null || true ;;
        fedora) sudo dnf install -y glx-utils vulkan-tools 2>/dev/null || sudo dnf install -y mesa-demos vulkan-tools 2>/dev/null || true ;;
        debian) sudo apt-get install -y mesa-utils vulkan-tools 2>/dev/null || true ;;
    esac
}

install_packages() {
    local pm current_nvidia
    pm="$(pm_family)"
    info "Package family: $pm"
    install_common_packages "$pm"

    current_nvidia="$(modinfo -F version nvidia 2>/dev/null || true)"
    if [[ -n "$current_nvidia" && "$current_nvidia" != 580.* ]]; then
        err "An NVIDIA driver outside the R580 branch is already installed: $current_nvidia"
        err "MX250/Pascal requires the legacy R580 branch. This script will not remove or replace an existing driver automatically."
        err "Remove/swap the current NVIDIA driver using your distribution's documented package workflow, then run install again."
        return 2
    fi

    if ! nvidia_580_ready; then
        case "$pm" in
            arch) install_nvidia_580_arch ;;
            fedora) install_nvidia_580_fedora ;;
            debian) install_nvidia_580_debian ;;
            *) return 1 ;;
        esac
    else
        info "NVIDIA R580 kernel module already available."
    fi
    install_graphics_tools "$pm"
}

# ---------------------------------------------------------------------------
# system installation
# ---------------------------------------------------------------------------

install_system_config() {
    load_discovered
    local tmp
    tmp="$(mktemp)"
    cat > "$tmp" <<EOF2
# Generated by huawei-matebook-13-gpu-manager.sh
IGPU_BDF="$IGPU_BDF"
DGPU_BDF="$DGPU_BDF"
DGPU_ROOT_BDF="$DGPU_ROOT_BDF"
DGPU_VENDOR="$DGPU_VENDOR"
DGPU_DEVICE="$DGPU_DEVICE"
EOF2
    sudo install -o root -g root -m 0644 "$tmp" "$SYSTEM_CONFIG"
    rm -f "$tmp"
}

install_modprobe_policy() {
    sudo tee "$MODPROBE_CONFIG" >/dev/null <<'EOF2'
# Huawei MateBook 13: keep NVIDIA from auto-loading at boot.
# Explicit `modprobe nvidia*` from the on-demand helper still works.
blacklist nouveau
blacklist nvidia
blacklist nvidia_drm
blacklist nvidia_modeset
blacklist nvidia_uvm
options nvidia-drm modeset=1
EOF2

    if command -v mkinitcpio >/dev/null 2>&1; then sudo mkinitcpio -P || true
    elif command -v dracut >/dev/null 2>&1; then sudo dracut -f || true
    elif command -v update-initramfs >/dev/null 2>&1; then sudo update-initramfs -u || true
    fi
}

install_udev_alias() {
    load_discovered
    sudo tee "$UDEV_RULE" >/dev/null <<EOF2
# Stable colon-free DRM alias for the Intel iGPU used by KWin isolation.
SUBSYSTEM=="drm", KERNEL=="card*", KERNELS=="$IGPU_BDF", SYMLINK+="dri/huawei-matebook-intel"
EOF2
    sudo udevadm control --reload-rules
    sudo udevadm trigger --subsystem-match=drm || true
    sudo udevadm settle || true
}

plasma_wayland_detected() {
    [[ -f /usr/lib/systemd/user/plasma-kwin_wayland.service || -f /usr/local/lib/systemd/user/plasma-kwin_wayland.service ]] && return 0
    [[ "${XDG_SESSION_TYPE:-}" == wayland ]] || return 1
    [[ "${XDG_CURRENT_DESKTOP:-}" == *KDE* || "${XDG_CURRENT_DESKTOP:-}" == *Plasma* ]]
}

install_kwin_isolation() {
    if ! plasma_wayland_detected; then
        warn "$(msg plasma_warn)"
        return 0
    fi
    mkdir -p "$KWIN_DROPIN_DIR"
    cat > "$KWIN_DROPIN" <<EOF2
[Service]
# Keep KWin on the Intel iGPU even while the MX250 is hot-added.
Environment=KWIN_DRM_DEVICES=$INTEL_ALIAS
# Plasma 6.7+ GpuManager: do not auto-open secondary render nodes.
Environment=KWIN_RENDER_NODES=
EOF2
    systemctl --user daemon-reload
}

install_power_helper() {
    local tmp
    tmp="$(mktemp)"
    cat > "$tmp" <<'EOF2'
#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG="/etc/huawei-matebook-gpu-manager.conf"
[[ -r "$CONFIG" ]] || { echo "missing $CONFIG" >&2; exit 1; }
# shellcheck disable=SC1090
source "$CONFIG"

LOCK="/run/lock/huawei-matebook-dgpu.lock"
RUNTIME="/run/huawei-matebook-dgpu"
LEASES="$RUNTIME/leases"
mkdir -p "$LEASES"
chmod 0755 "$RUNTIME" "$LEASES"
exec 9>"$LOCK"
flock 9

find_gpu_bdf() {
    local d
    for d in /sys/bus/pci/devices/*; do
        [[ -r "$d/vendor" && -r "$d/device" ]] || continue
        [[ "$(<"$d/vendor")" == "$DGPU_VENDOR" && "$(<"$d/device")" == "$DGPU_DEVICE" ]] || continue
        basename "$d"; return 0
    done
    return 1
}

gpu_present() { find_gpu_bdf >/dev/null 2>&1; }

render_node() {
    local bdf
    bdf="$(find_gpu_bdf 2>/dev/null || true)"
    [[ -n "$bdf" ]] || return 1
    readlink -f "/dev/dri/by-path/pci-${bdf}-render" 2>/dev/null || true
}

nvidia_users() {
    local f render
    render="$(render_node || true)"
    for f in /dev/nvidia0 /dev/nvidiactl /dev/nvidia-modeset /dev/nvidia-uvm "$render"; do
        [[ -n "$f" && -e "$f" ]] || continue
        fuser "$f" 2>/dev/null || true
    done | tr ' ' '\n' | grep -E '^[0-9]+$' | sort -u
}

clean_stale_leases() {
    local f pid
    for f in "$LEASES"/*; do
        [[ -e "$f" ]] || continue
        pid="${f##*/}"
        if [[ ! "$pid" =~ ^[0-9]+$ || ! -d "/proc/$pid" ]]; then rm -f "$f"; fi
    done
}

lease_count() {
    clean_stale_leases
    find "$LEASES" -maxdepth 1 -type f -printf . 2>/dev/null | wc -c
}

unexpected_users_after_first_load() {
    local users
    users="$(nvidia_users || true)"
    [[ -z "$users" ]] && return 1
    echo "NVIDIA was grabbed before the managed application started. PID(s): $users" >&2
    ps -o pid,user,comm,args -p "$(tr '\n' ',' <<<"$users" | sed 's/,$//')" 2>/dev/null >&2 || true
    return 0
}

power_on_first() {
    local bdf
    if ! gpu_present; then
        echo 1 > /sys/bus/pci/rescan
        for _ in $(seq 1 40); do gpu_present && break; sleep 0.1; done
    fi
    gpu_present || { echo "MX250 not detected after PCI rescan" >&2; exit 1; }

    modprobe nvidia
    modprobe nvidia_modeset
    modprobe nvidia_drm modeset=1
    modprobe nvidia_uvm
    udevadm settle || true

    bdf="$(find_gpu_bdf)"
    [[ ! -w "/sys/bus/pci/devices/$bdf/power/control" ]] || echo auto > "/sys/bus/pci/devices/$bdf/power/control" || true
    sleep 0.5

    if unexpected_users_after_first_load; then
        echo "Failing closed: the desktop/compositor grabbed NVIDIA. Configure compositor isolation before using on-demand mode." >&2
        return 2
    fi
}

power_off_if_idle() {
    clean_stale_leases
    [[ "$(lease_count)" == 0 ]] || return 75

    local users bdf
    users="$(nvidia_users || true)"
    [[ -z "$users" ]] || return 75

    modprobe -r nvidia_drm 2>/dev/null || true
    modprobe -r nvidia_modeset 2>/dev/null || true
    modprobe -r nvidia_uvm 2>/dev/null || true
    modprobe -r nvidia 2>/dev/null || true

    if lsmod | grep -q '^nvidia'; then return 75; fi

    bdf="$(find_gpu_bdf 2>/dev/null || true)"
    if [[ -n "$bdf" && -e "/sys/bus/pci/devices/$bdf/remove" ]]; then
        echo 1 > "/sys/bus/pci/devices/$bdf/remove"
        for _ in $(seq 1 30); do ! gpu_present && break; sleep 0.1; done
    fi
    gpu_present && { echo "PCI remove failed" >&2; return 1; }
}

acquire() {
    local token="${1:-}"
    [[ "$token" =~ ^[0-9]+$ ]] || { echo "numeric lease token required" >&2; exit 2; }
    clean_stale_leases
    local before
    before="$(lease_count)"
    : > "$LEASES/$token"
    if [[ "$before" == 0 ]]; then
        if ! power_on_first; then
            rm -f "$LEASES/$token"
            power_off_if_idle || true
            return 2
        fi
    fi
}

release() {
    local token="${1:-}"
    [[ "$token" =~ ^[0-9]+$ ]] || { echo "numeric lease token required" >&2; exit 2; }
    rm -f "$LEASES/$token"
    power_off_if_idle || true
}

boot_off() {
    rm -f "$LEASES"/* 2>/dev/null || true
    power_off_if_idle || true
}

status() {
    local bdf users root=""
    bdf="$(find_gpu_bdf 2>/dev/null || true)"
    printf 'GPU_PRESENT=%s\n' "$([[ -n "$bdf" ]] && echo YES || echo NO)"
    printf 'GPU_BDF=%s\n' "${bdf:-ABSENT}"
    printf 'LEASES=%s\n' "$(lease_count)"
    users="$(nvidia_users || true)"
    printf 'USERS=%s\n' "${users//$'\n'/ }"
    printf 'NVIDIA_MODULES='; lsmod | awk '$1~/^nvidia/{printf "%s ",$1} END{print ""}'
    if [[ -n "$bdf" ]]; then
        root="$(basename "$(dirname "$(readlink -f "/sys/bus/pci/devices/$bdf")")")"
    else
        root="$DGPU_ROOT_BDF"
    fi
    printf 'ROOT_RUNTIME='; cat "/sys/bus/pci/devices/$root/power/runtime_status" 2>/dev/null || echo N/A
}

case "${1:-}" in
    acquire) acquire "${2:-}" ;;
    release) release "${2:-}" ;;
    cleanup) power_off_if_idle || true ;;
    boot-off) boot_off ;;
    status) status ;;
    *) echo "usage: $0 {acquire PID|release PID|cleanup|boot-off|status}" >&2; exit 2 ;;
esac
EOF2
    sudo install -o root -g root -m 0755 "$tmp" "$POWER_HELPER"
    rm -f "$tmp"
}

install_runner() {
    local tmp
    tmp="$(mktemp)"
    cat > "$tmp" <<EOF2
#!/usr/bin/env bash
set -Eeuo pipefail
POWER="$POWER_HELPER"
[[ \$# -gt 0 ]] || { echo "usage: huawei-matebook-dgpu-run command [args...]" >&2; exit 2; }
TOKEN="\$\$"
acquired=0
cleanup() {
    if [[ \$acquired == 1 ]]; then sudo -n "\$POWER" release "\$TOKEN" >/dev/null 2>&1 || true; fi
}
trap cleanup EXIT HUP INT TERM
sudo -n "\$POWER" acquire "\$TOKEN" || { echo "Unable to enable the MX250 safely." >&2; exit 1; }
acquired=1
unset DRI_PRIME
export __NV_PRIME_RENDER_OFFLOAD=1
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export __VK_LAYER_NV_optimus=NVIDIA_only
export VK_LOADER_DRIVERS_SELECT='*nvidia*'
"\$@"
EOF2
    sudo install -o root -g root -m 0755 "$tmp" "$RUNNER"
    rm -f "$tmp"
}

install_sudoers() {
    local tmp
    tmp="$(mktemp)"
    cat > "$tmp" <<EOF2
Cmnd_Alias HUAWEI_MATEBOOK_DGPU = $POWER_HELPER acquire *, $POWER_HELPER release *, $POWER_HELPER cleanup, $POWER_HELPER status
$USER_NAME ALL=(root) NOPASSWD: HUAWEI_MATEBOOK_DGPU
EOF2
    sudo visudo -cf "$tmp" >/dev/null
    sudo install -o root -g root -m 0440 "$tmp" "$SUDOERS_FILE"
    rm -f "$tmp"
}

install_boot_service() {
    sudo tee "$BOOT_SERVICE" >/dev/null <<EOF2
[Unit]
Description=Huawei MateBook 13 - keep MX250 off while idle
After=systemd-udev-settle.service systemd-modules-load.service
Before=display-manager.service

[Service]
Type=oneshot
ExecStart=$POWER_HELPER boot-off
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF2
    sudo systemctl daemon-reload
    sudo systemctl enable huawei-matebook-dgpu-off.service >/dev/null
    sudo systemctl disable --now nvidia-persistenced.service >/dev/null 2>&1 || true
}

install_cleanup_timer() {
    cat > "$CLEANUP_SERVICE" <<EOF2
[Unit]
Description=Release idle Huawei MateBook MX250

[Service]
Type=oneshot
ExecStart=/usr/bin/sudo -n $POWER_HELPER cleanup
StandardOutput=null
EOF2
    cat > "$CLEANUP_TIMER" <<'EOF2'
[Unit]
Description=Periodic cleanup for Huawei MateBook on-demand dGPU

[Timer]
OnBootSec=45s
OnUnitActiveSec=30s
AccuracySec=5s
Persistent=false

[Install]
WantedBy=timers.target
EOF2
    systemctl --user daemon-reload
    systemctl --user enable --now huawei-matebook-dgpu-cleanup.timer >/dev/null 2>&1 || true
}

# ---------------------------------------------------------------------------
# Desktop application management
# ---------------------------------------------------------------------------

resolve_desktop_source() {
    local id="$1"
    if [[ -f "$id" ]]; then readlink -f "$id"; return 0; fi
    id="$(basename "$id")"
    if [[ -f "$LOCAL_APPS/$id" ]]; then echo "$LOCAL_APPS/$id"
    elif [[ -f "/usr/share/applications/$id" ]]; then echo "/usr/share/applications/$id"
    else return 1
    fi
}

desktop_name() { awk -F= '$1=="Name" {print substr($0,6); exit}' "$1" 2>/dev/null || basename "$1"; }

rewrite_desktop_gpu() {
    local src="$1" dst="$2"
    python3 - "$src" "$dst" "$RUNNER" <<'PY'
from pathlib import Path
import sys
src,dst,runner=Path(sys.argv[1]),Path(sys.argv[2]),sys.argv[3]
lines=src.read_text(encoding='utf-8',errors='replace').splitlines()
out=[]; main=False; seen_exec=False; seen_pref=False; seen_kde=False; seen_mark=False; seen_dbus=False

def finish():
    global seen_pref,seen_kde,seen_mark,seen_dbus
    if not seen_pref: out.append('PrefersNonDefaultGPU=false'); seen_pref=True
    if not seen_kde: out.append('X-KDE-RunOnDiscreteGpu=false'); seen_kde=True
    if not seen_dbus: out.append('DBusActivatable=false'); seen_dbus=True
    if not seen_mark: out.append('X-Huawei-MateBook-GPU-Managed=true'); seen_mark=True

for line in lines:
    if line == '[Desktop Entry]': main=True; out.append(line); continue
    if line.startswith('[') and line.endswith(']') and line != '[Desktop Entry]':
        if main: finish()
        main=False
    if main and line.startswith('Exec='):
        cmd=line[5:]
        if runner not in cmd: cmd=f'{runner} {cmd}'
        line='Exec='+cmd; seen_exec=True
    elif main and line.startswith('PrefersNonDefaultGPU='): line='PrefersNonDefaultGPU=false'; seen_pref=True
    elif main and line.startswith('X-KDE-RunOnDiscreteGpu='): line='X-KDE-RunOnDiscreteGpu=false'; seen_kde=True
    elif main and line.startswith('DBusActivatable='): line='DBusActivatable=false'; seen_dbus=True
    elif main and line.startswith('X-Huawei-MateBook-GPU-Managed='): line='X-Huawei-MateBook-GPU-Managed=true'; seen_mark=True
    out.append(line)
if main: finish()
if not seen_exec: raise SystemExit('main Desktop Entry has no Exec=')
dst.write_text('\n'.join(out)+'\n',encoding='utf-8')
PY
}

strip_desktop_gpu() {
    local src="$1" dst="$2"
    python3 - "$src" "$dst" "$RUNNER" <<'PY'
from pathlib import Path
import sys
src,dst,runner=Path(sys.argv[1]),Path(sys.argv[2]),sys.argv[3]
lines=src.read_text(encoding='utf-8',errors='replace').splitlines(); out=[]; main=False
for line in lines:
    if line == '[Desktop Entry]': main=True; out.append(line); continue
    if line.startswith('[') and line.endswith(']') and line != '[Desktop Entry]': main=False
    if main and line.startswith('Exec='): line='Exec='+line[5:].replace(runner+' ','',1)
    elif main and line.startswith('X-Huawei-MateBook-GPU-Managed='): continue
    out.append(line)
dst.write_text('\n'.join(out)+'\n',encoding='utf-8')
PY
}

apply_desktop_app() {
    local requested="$1" remember="${2:-true}" src id dst state tmp
    ensure_dirs
    src="$(resolve_desktop_source "$requested" 2>/dev/null || true)"
    [[ -n "$src" ]] || { err "Application not found: $requested"; return 2; }
    id="$(basename "$src")"; dst="$LOCAL_APPS/$id"; state="$DESKTOP_STATE_DIR/$id"
    mkdir -p "$state"
    if [[ ! -f "$state/captured" ]]; then
        if [[ -f "$dst" ]]; then
            if grep -qF "$RUNNER" "$dst"; then strip_desktop_gpu "$dst" "$state/original.desktop"; else cp -a "$dst" "$state/original.desktop"; fi
            echo 1 > "$state/had_local"
        else echo 0 > "$state/had_local"
        fi
        touch "$state/captured"
    fi
    tmp="$(mktemp)"; cp -a "$src" "$tmp"; rewrite_desktop_gpu "$tmp" "$dst"; rm -f "$tmp"
    [[ "$remember" == true ]] && remember_desktop "$id"
    command -v kbuildsycoca6 >/dev/null 2>&1 && kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
    info "GPU on-demand enabled: $(desktop_name "$dst") [$id]"
}

remove_desktop_app() {
    local id state dst had forget="${2:-true}"
    id="$(basename "$1")"; state="$DESKTOP_STATE_DIR/$id"; dst="$LOCAL_APPS/$id"
    if [[ -f "$state/captured" ]]; then
        had="$(cat "$state/had_local" 2>/dev/null || echo 0)"
        if [[ "$had" == 1 && -f "$state/original.desktop" ]]; then cp -a "$state/original.desktop" "$dst"; else rm -f "$dst"; fi
        rm -rf "$state"
    elif [[ -f "$dst" ]] && grep -q '^X-Huawei-MateBook-GPU-Managed=true$' "$dst"; then rm -f "$dst"
    fi
    [[ "$forget" == true ]] && forget_desktop "$id"
    command -v kbuildsycoca6 >/dev/null 2>&1 && kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
    info "GPU on-demand removed: $id"
}

search_desktop_app() {
    local query="${1:-}"
    if [[ -z "$query" && -t 0 ]]; then
        if [[ "$LANG_CHOICE" == fr ]]; then read -r -p "Recherche application : " query; else read -r -p "Search application: " query; fi
    fi
    mapfile -t rows < <(python3 - "$HOME" "$query" <<'PY'
from pathlib import Path
import configparser,sys
home=Path(sys.argv[1]); q=sys.argv[2].lower(); paths={}
for base in (Path('/usr/share/applications'),home/'.local/share/applications'):
    if base.exists():
        for p in base.glob('*.desktop'): paths[p.name]=p
rows=[]
for ident,p in paths.items():
    cp=configparser.ConfigParser(interpolation=None,strict=False)
    try:
        cp.read(p,encoding='utf-8'); s=cp['Desktop Entry']
        if s.get('Hidden','false').lower()=='true' or s.get('NoDisplay','false').lower()=='true': continue
        name=s.get('Name',ident)
        if q and q not in name.lower() and q not in ident.lower(): continue
        rows.append((name,ident))
    except Exception: pass
for name,ident in sorted(rows,key=lambda x:x[0].lower()): print(name+'\t'+ident)
PY
)
    ((${#rows[@]})) || { err "$(msg no_app)"; return 1; }
    local max=$(( ${#rows[@]} < 40 ? ${#rows[@]} : 40 )) i name id n
    for ((i=0;i<max;i++)); do IFS=$'\t' read -r name id <<<"${rows[$i]}"; printf '%3d) %-48s %s\n' "$((i+1))" "$name" "$id"; done
    read -r -p "# " n
    [[ "$n" =~ ^[0-9]+$ ]] && ((n>=1 && n<=max)) || return 1
    IFS=$'\t' read -r _ id <<<"${rows[$((n-1))]}"; echo "$id"
}

apply_saved_desktop_apps() {
    local id
    for id in "${MANAGED_DESKTOP_APPS[@]:-}"; do [[ -n "$id" ]] && apply_desktop_app "$id" false || true; done
}

# ---------------------------------------------------------------------------
# Steam game management (experimental; backups are always kept)
# ---------------------------------------------------------------------------

steam_root() {
    local p
    for p in "$HOME/.local/share/Steam" "$HOME/.steam/steam"; do [[ -d "$p" ]] && { readlink -f "$p"; return; }; done
    return 1
}
steam_running() { pgrep -u "$USER_UID" -x steam >/dev/null 2>&1 || pgrep -u "$USER_UID" -f 'steamwebhelper' >/dev/null 2>&1; }

steam_games_tsv() {
    local root; root="$(steam_root)" || return 1
    python3 - "$root" <<'PY'
from pathlib import Path
import re,sys
root=Path(sys.argv[1]); libs=[root/'steamapps']
vdf=root/'steamapps/libraryfolders.vdf'
if vdf.exists():
    text=vdf.read_text(errors='ignore')
    for p in re.findall(r'"path"\s+"([^"]+)"',text): libs.append(Path(p.replace('\\\\','\\'))/'steamapps')
seen=set()
for lib in libs:
    for mf in lib.glob('appmanifest_*.acf'):
        t=mf.read_text(errors='ignore')
        a=re.search(r'"appid"\s+"(\d+)"',t); n=re.search(r'"name"\s+"([^"]+)"',t)
        if a and n and a.group(1) not in seen:
            seen.add(a.group(1)); print(a.group(1)+'\t'+n.group(1))
PY
}

steam_localconfig() {
    local root; root="$(steam_root)" || return 1
    find "$root/userdata" -mindepth 2 -maxdepth 2 -type f -name localconfig.vdf -print 2>/dev/null | head -n1
}
steam_game_name() { steam_games_tsv 2>/dev/null | awk -F'\t' -v id="$1" '$1==id {print $2; exit}'; }

steam_edit_launchoption() {
    local action="$1" appid="$2" vdf
    vdf="$(steam_localconfig)"; [[ -f "$vdf" ]] || { err "Steam localconfig.vdf not found"; return 1; }
    steam_running && { err "$(msg steam_close)"; return 3; }
    mkdir -p "$STEAM_STATE_DIR/backups" "$STEAM_STATE_DIR/original"
    cp -a "$vdf" "$STEAM_STATE_DIR/backups/localconfig.vdf.$(date +%Y%m%d-%H%M%S)"
    python3 - "$vdf" "$action" "$appid" "$RUNNER" "$STEAM_STATE_DIR/original/$appid.json" <<'PY'
from pathlib import Path
import json,re,sys
path=Path(sys.argv[1]); action=sys.argv[2]; appid=sys.argv[3]; runner=sys.argv[4]; state=Path(sys.argv[5])
text=path.read_text(encoding='utf-8',errors='replace')
def section(txt,key,start=0,end=None):
    end=len(txt) if end is None else end
    m=re.search(r'"'+re.escape(key)+r'"\s*\{',txt[start:end],re.I)
    if not m:return None
    brace=start+m.end()-1; depth=0; ins=False; esc=False
    for i in range(brace,end):
        c=txt[i]
        if ins:
            if esc:esc=False
            elif c=='\\':esc=True
            elif c=='"':ins=False
            continue
        if c=='"':ins=True
        elif c=='{':depth+=1
        elif c=='}':
            depth-=1
            if depth==0:return brace,i
    return None
def dec(s):return s.replace('\\"','"').replace('\\\\','\\')
def enc(s):return s.replace('\\','\\\\').replace('"','\\"')
apps=section(text,'apps')
if not apps: raise SystemExit('Steam apps section not found')
a0,a1=apps; app=section(text,appid,a0+1,a1)
if not app and action=='add':
    ind='\t\t\t\t\t'; ins=a0+1
    block=f'\n{ind}"{appid}"\n{ind}{{\n{ind}\t"LaunchOptions"\t\t"{enc(runner+" %command%")}"\n{ind}}}'
    text=text[:ins]+block+text[ins:]
    if not state.exists(): state.write_text(json.dumps({'had':False,'value':''}))
elif app:
    b0,b1=app; body=text[b0+1:b1]
    lm=re.search(r'(?m)^([ \t]*)"LaunchOptions"[ \t]+"((?:\\.|[^"])*)"[ \t]*$',body)
    cur=dec(lm.group(2)) if lm else ''
    if action=='add':
        if not state.exists(): state.write_text(json.dumps({'had':bool(lm),'value':cur}))
        if runner not in cur:
            new=cur.replace('%command%',runner+' %command%',1) if '%command%' in cur else (runner+' %command% '+cur.strip()).strip()
            line=(lm.group(1) if lm else '\n\t')+'"LaunchOptions"\t\t"'+enc(new)+'"'
            body=body[:lm.start()]+line+body[lm.end():] if lm else line+body
            text=text[:b0+1]+body+text[b1:]
    elif action=='remove':
        if state.exists():
            st=json.loads(state.read_text())
            if st.get('had'):
                line=(lm.group(1) if lm else '\n\t')+'"LaunchOptions"\t\t"'+enc(st.get('value',''))+'"'
                body=body[:lm.start()]+line+body[lm.end():] if lm else line+body
            elif lm: body=body[:lm.start()]+body[lm.end():]
            state.unlink(missing_ok=True)
        elif lm:
            new=cur.replace(runner+' %command%','%command%',1).replace(runner+' ','',1).strip()
            line=lm.group(1)+'"LaunchOptions"\t\t"'+enc(new)+'"'; body=body[:lm.start()]+line+body[lm.end():]
        text=text[:b0+1]+body+text[b1:]
path.write_text(text,encoding='utf-8')
PY
}

steam_add_game() { steam_edit_launchoption add "$1"; [[ "${2:-true}" == true ]] && remember_steam "$1"; info "Steam GPU on-demand enabled: $(steam_game_name "$1") [$1]"; }
steam_remove_game() { steam_edit_launchoption remove "$1"; [[ "${2:-true}" == true ]] && forget_steam "$1"; info "Steam GPU on-demand removed: $(steam_game_name "$1") [$1]"; }
steam_enable_all() {
    steam_running && { err "$(msg steam_close)"; return 3; }
    local id name
    while IFS=$'\t' read -r id name; do [[ -n "$id" ]] && steam_add_game "$id" false || true; done < <(steam_games_tsv 2>/dev/null || true)
    [[ "${1:-true}" == true ]] && persist_config steam-all on ""
    STEAM_ALL=1
    info "All currently installed Steam games are configured for MX250 on-demand."
}
steam_disable_all() {
    steam_running && { err "$(msg steam_close)"; return 3; }
    local id name
    while IFS=$'\t' read -r id name; do [[ -n "$id" ]] && steam_edit_launchoption remove "$id" || true; done < <(steam_games_tsv 2>/dev/null || true)
    # Also restore saved state for games that are no longer installed but still have a known APPID.
    for id in "${MANAGED_STEAM_APPS[@]:-}"; do [[ -n "$id" ]] && steam_edit_launchoption remove "$id" 2>/dev/null || true; done
    [[ "${1:-true}" == true ]] && persist_config steam-all off ""
    STEAM_ALL=0
    info "Global Steam GPU on-demand mode disabled; saved LaunchOptions restored where available."
}
apply_saved_steam_apps() {
    steam_running && { warn "$(msg steam_close)"; return 3; }
    local id name
    if [[ "$STEAM_ALL" == 1 ]]; then
        while IFS=$'\t' read -r id name; do steam_add_game "$id" false || true; done < <(steam_games_tsv 2>/dev/null || true)
    else
        for id in "${MANAGED_STEAM_APPS[@]:-}"; do [[ -n "$id" ]] && steam_add_game "$id" false || true; done
    fi
}

# ---------------------------------------------------------------------------
# install / status / test / uninstall
# ---------------------------------------------------------------------------

configure_steam_client_intel() {
    local src="/usr/share/applications/steam.desktop" dst="$LOCAL_APPS/steam.desktop"
    [[ -f "$src" ]] || return 0
    mkdir -p "$STATE_DIR/steam-client"
    if [[ ! -f "$STATE_DIR/steam-client/captured" ]]; then
        if [[ -f "$dst" ]]; then cp -a "$dst" "$STATE_DIR/steam-client/original.desktop"; echo 1 > "$STATE_DIR/steam-client/had_local"; else echo 0 > "$STATE_DIR/steam-client/had_local"; fi
        touch "$STATE_DIR/steam-client/captured"
    fi
    cp -a "$src" "$dst"
    python3 - "$dst" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); lines=p.read_text().splitlines(); out=[]; main=False; a=b=False
for line in lines:
    if line=='[Desktop Entry]':main=True;out.append(line);continue
    if line.startswith('[') and line.endswith(']') and line!='[Desktop Entry]':
        if main:
            if not a:out.append('PrefersNonDefaultGPU=false')
            if not b:out.append('X-KDE-RunOnDiscreteGpu=false')
        main=False
    if main and line.startswith('PrefersNonDefaultGPU='):line='PrefersNonDefaultGPU=false';a=True
    elif main and line.startswith('X-KDE-RunOnDiscreteGpu='):line='X-KDE-RunOnDiscreteGpu=false';b=True
    out.append(line)
if main:
    if not a:out.append('PrefersNonDefaultGPU=false')
    if not b:out.append('X-KDE-RunOnDiscreteGpu=false')
p.write_text('\n'.join(out)+'\n')
PY
}

install_core() {
    ensure_dirs
    bold "Huawei MateBook 13 GPU Manager $VERSION — $(msg install_title)"
    line
    hardware_discover
    install_packages
    install_system_config
    install_modprobe_policy
    install_udev_alias
    install_kwin_isolation
    install_power_helper
    install_runner
    install_sudoers
    install_boot_service
    install_cleanup_timer
    configure_steam_client_intel
    apply_saved_desktop_apps
    apply_saved_steam_apps || true
    line
    info "$(msg install_done)"
    warn "$(msg reboot)"
}

status() {
    bold "Huawei MateBook 13 GPU Manager $VERSION"
    line
    if load_discovered 2>/dev/null; then
        printf 'IGPU_BDF=%s\nDGPU_EXPECTED_BDF=%s\nDGPU_ROOT_BDF=%s\n' "$IGPU_BDF" "$DGPU_BDF" "$DGPU_ROOT_BDF"
    fi
    printf 'CURRENT_DGPU_BDF=%s\n' "$(find_dgpu_bdf 2>/dev/null || echo ABSENT)"
    printf 'INTEL_ALIAS='; readlink -f "$INTEL_ALIAS" 2>/dev/null || echo ABSENT
    printf 'NVIDIA_VERSION='; modinfo -F version nvidia 2>/dev/null | head -n1 || echo ABSENT
    echo 'KWIN:'
    systemctl --user show plasma-kwin_wayland.service -p Environment -p DropInPaths --no-pager 2>/dev/null || true
    echo 'POWER:'
    [[ -x "$POWER_HELPER" ]] && sudo -n "$POWER_HELPER" status 2>/dev/null || echo 'helper not installed'
    echo 'MANAGED_DESKTOP_APPS:'; printf '  %s\n' "${MANAGED_DESKTOP_APPS[@]:-(none)}"
    echo 'MANAGED_STEAM_APPS:'; printf '  %s\n' "${MANAGED_STEAM_APPS[@]:-(none)}"
    echo "STEAM_ALL=$STEAM_ALL"
}

smoke_test() {
    [[ -x "$RUNNER" ]] || { err "Install first."; return 1; }
    if command -v glxinfo >/dev/null 2>&1; then
        "$RUNNER" glxinfo -B 2>&1 | grep -Ei 'direct rendering|OpenGL vendor|OpenGL renderer|OpenGL version'
    else "$RUNNER" true
    fi
    sleep 1
    sudo -n "$POWER_HELPER" cleanup || true
    sudo -n "$POWER_HELPER" status
}

list_managed() {
    echo 'Desktop:'
    local x
    for x in "${MANAGED_DESKTOP_APPS[@]:-}"; do [[ -n "$x" ]] && echo "  - $x"; done
    echo 'Steam:'
    echo "  all=$STEAM_ALL"
    for x in "${MANAGED_STEAM_APPS[@]:-}"; do [[ -n "$x" ]] && echo "  - $x"; done
}

restore_steam_client() {
    local d="$STATE_DIR/steam-client" dst="$LOCAL_APPS/steam.desktop"
    [[ -f "$d/captured" ]] || return 0
    if [[ "$(cat "$d/had_local" 2>/dev/null || echo 0)" == 1 && -f "$d/original.desktop" ]]; then cp -a "$d/original.desktop" "$dst"; else rm -f "$dst"; fi
    rm -rf "$d"
}

uninstall_core() {
    confirm "Remove the on-demand GPU infrastructure?" || return 0
    local id
    if ! steam_running; then
        if [[ "$STEAM_ALL" == 1 ]]; then steam_disable_all false || true
        else for id in "${MANAGED_STEAM_APPS[@]:-}"; do [[ -n "$id" ]] && steam_edit_launchoption remove "$id" || true; done
        fi
    fi
    for id in "${MANAGED_DESKTOP_APPS[@]:-}"; do [[ -n "$id" ]] && remove_desktop_app "$id" false || true; done
    restore_steam_client
    systemctl --user disable --now huawei-matebook-dgpu-cleanup.timer >/dev/null 2>&1 || true
    rm -f "$CLEANUP_SERVICE" "$CLEANUP_TIMER" "$KWIN_DROPIN"
    systemctl --user daemon-reload || true
    sudo systemctl disable huawei-matebook-dgpu-off.service >/dev/null 2>&1 || true
    sudo rm -f "$BOOT_SERVICE" "$SUDOERS_FILE" "$POWER_HELPER" "$RUNNER" "$UDEV_RULE" "$MODPROBE_CONFIG" "$SYSTEM_CONFIG"
    sudo systemctl daemon-reload
    sudo udevadm control --reload-rules || true
    warn "Reboot recommended. NVIDIA packages were intentionally left installed."
}

# ---------------------------------------------------------------------------
# interactive menus
# ---------------------------------------------------------------------------

choose_managed_desktop() {
    ((${#MANAGED_DESKTOP_APPS[@]})) || return 1
    local i n
    for i in "${!MANAGED_DESKTOP_APPS[@]}"; do printf '%3d) %s\n' "$((i+1))" "${MANAGED_DESKTOP_APPS[$i]}"; done
    read -r -p '# ' n
    [[ "$n" =~ ^[0-9]+$ ]] && ((n>=1 && n<=${#MANAGED_DESKTOP_APPS[@]})) || return 1
    echo "${MANAGED_DESKTOP_APPS[$((n-1))]}"
}

choose_steam_game() {
    mapfile -t games < <(steam_games_tsv)
    ((${#games[@]})) || return 1
    local i max=$(( ${#games[@]} < 50 ? ${#games[@]} : 50 )) id name n
    for ((i=0;i<max;i++)); do IFS=$'\t' read -r id name <<<"${games[$i]}"; printf '%3d) %-55s %s\n' "$((i+1))" "$name" "$id"; done
    read -r -p '# ' n
    [[ "$n" =~ ^[0-9]+$ ]] && ((n>=1 && n<=max)) || return 1
    IFS=$'\t' read -r id _ <<<"${games[$((n-1))]}"; echo "$id"
}

choose_managed_steam() {
    ((${#MANAGED_STEAM_APPS[@]})) || return 1
    local i n id
    for i in "${!MANAGED_STEAM_APPS[@]}"; do
        id="${MANAGED_STEAM_APPS[$i]}"
        printf '%3d) %-55s %s\n' "$((i+1))" "$(steam_game_name "$id" 2>/dev/null || true)" "$id"
    done
    read -r -p '# ' n
    [[ "$n" =~ ^[0-9]+$ ]] && ((n>=1 && n<=${#MANAGED_STEAM_APPS[@]})) || return 1
    echo "${MANAGED_STEAM_APPS[$((n-1))]}"
}

main_menu() {
    choose_language
    while true; do
        clear 2>/dev/null || true
        bold "Huawei MateBook 13 GPU Manager — MX250 on-demand"
        echo "v$VERSION"
        line
        if [[ "$LANG_CHOICE" == fr ]]; then
            cat <<'MENU'
1) Installer / réparer
2) Ajouter une application Desktop
3) Retirer une application Desktop
4) Ajouter un jeu Steam
5) Retirer un jeu Steam
6) Tous les jeux Steam -> MX250
7) Réappliquer les applications enregistrées
8) Lister
9) Diagnostic
10) Test GPU à la demande
11) Désinstaller l'infrastructure
0) Quitter
MENU
        else
            cat <<'MENU'
1) Install / repair
2) Add a Desktop application
3) Remove a Desktop application
4) Add a Steam game
5) Remove a Steam game
6) All installed Steam games -> MX250
7) Re-apply saved applications
8) List
9) Status
10) Test on-demand GPU
11) Uninstall infrastructure
0) Quit
MENU
        fi
        local c id
        read -r -p '> ' c
        case "$c" in
            1) install_core; pause ;;
            2) id="$(search_desktop_app)" && apply_desktop_app "$id" true; pause ;;
            3) id="$(choose_managed_desktop)" && remove_desktop_app "$id"; pause ;;
            4) id="$(choose_steam_game)" && steam_add_game "$id" true; pause ;;
            5) id="$(choose_managed_steam)" && steam_remove_game "$id" true || true; pause ;;
            6)
                if [[ "$STEAM_ALL" == 1 ]]; then steam_disable_all true || true
                else steam_enable_all true || true
                fi
                pause ;;
            7) apply_saved_desktop_apps; apply_saved_steam_apps || true; pause ;;
            8) list_managed; pause ;;
            9) status; pause ;;
            10) smoke_test; pause ;;
            11) uninstall_core; pause ;;
            0) return ;;
        esac
    done
}

usage() {
    cat <<EOF2
Huawei MateBook 13 GPU Manager $VERSION

Usage:
  $0 [--lang en|fr] [--yes] install
  $0 [--lang en|fr] add [APP.desktop]
  $0 [--lang en|fr] remove [APP.desktop]
  $0 steam-add [APPID]
  $0 steam-remove APPID
  $0 steam-all-on
  $0 steam-all-off
  $0 apply
  $0 list
  $0 status
  $0 test
  $0 run -- COMMAND [ARGS...]
  $0 uninstall
  $0                 # interactive menu

Safety:
  --force-unsupported   bypasses the Huawei DMI check only; the MX250 PCI ID
                        is still required. Use only for deliberate testing.
EOF2
}

# Parse global flags before command.
args=()
while (($#)); do
    case "$1" in
        --lang) LANG_CHOICE="${2:-}"; shift 2 ;;
        --lang=*) LANG_CHOICE="${1#*=}"; shift ;;
        --yes|-y) AUTO_YES=1; shift ;;
        --force-unsupported) FORCE_UNSUPPORTED=1; shift ;;
        --) args+=("$1"); shift; args+=("$@"); break ;;
        *) args+=("$1"); shift ;;
    esac
done
set -- "${args[@]}"
[[ "$LANG_CHOICE" == "" || "$LANG_CHOICE" == en || "$LANG_CHOICE" == fr ]] || { err "--lang must be en or fr"; exit 2; }
choose_language
ensure_dirs

cmd="${1:-menu}"
case "$cmd" in
    menu) main_menu ;;
    install|repair) install_core ;;
    add) if [[ -n "${2:-}" ]]; then apply_desktop_app "$2" true; else id="$(search_desktop_app)"; apply_desktop_app "$id" true; fi ;;
    remove) if [[ -n "${2:-}" ]]; then remove_desktop_app "$2"; else id="$(choose_managed_desktop)"; remove_desktop_app "$id"; fi ;;
    steam-add) id="${2:-}"; [[ -n "$id" ]] || id="$(choose_steam_game)"; steam_add_game "$id" true ;;
    steam-remove) [[ -n "${2:-}" ]] || { err "APPID required"; exit 2; }; steam_remove_game "$2" true ;;
    steam-all-on) steam_enable_all true ;;
    steam-all-off) steam_disable_all true ;;
    apply) apply_saved_desktop_apps; apply_saved_steam_apps || true ;;
    list) list_managed ;;
    status) status ;;
    test) smoke_test ;;
    run) shift; [[ "${1:-}" == -- ]] && shift; [[ -x "$RUNNER" ]] || { err "Install first"; exit 1; }; exec "$RUNNER" "$@" ;;
    uninstall) uninstall_core ;;
    help|-h|--help) usage ;;
    *) err "Unknown command: $cmd"; usage; exit 2 ;;
esac
