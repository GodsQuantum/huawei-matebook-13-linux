#!/usr/bin/env bash
# Huawei MateBook 13 GPU Manager
# SPDX-License-Identifier: GPL-2.0-only
#
# On-demand NVIDIA MX250 (GP108M, PCI ID 10de:1d13) power management for
# Huawei MateBook 13 laptops. The validated design keeps the dGPU removed from
# PCI while idle, hot-rescans it only for selected applications, uses PRIME
# Render Offload, then unloads NVIDIA and removes the device again.
#
# UI: English/French. Automatic package adapters cover Arch/CachyOS, Fedora,
# Debian/Ubuntu and common openSUSE prerequisites; any systemd distribution can
# use the core with a preinstalled proprietary NVIDIA R580 driver. Plasma
# Wayland is the validated desktop.

set -Eeuo pipefail
shopt -s nullglob

VERSION="3.0.2"
STATE_SCHEMA=3
INSTALL_SCHEMA=3
SELF="$(readlink -f "${BASH_SOURCE[0]}")"

# Public hardware target: NVIDIA GP108M / GeForce MX250.
DGPU_VENDOR="0x10de"
DGPU_DEVICE="0x1d13"

# System paths are environment-overridable only for the source-only test harness.
SYSTEM_CONFIG="${HUAWEI_GPU_SYSTEM_CONFIG:-/etc/huawei-matebook-gpu-manager.conf}"
MODPROBE_CONFIG="${HUAWEI_GPU_MODPROBE_CONFIG:-/etc/modprobe.d/huawei-matebook-gpu-manager.conf}"
POWER_HELPER="${HUAWEI_GPU_POWER_HELPER:-/usr/local/sbin/huawei-matebook-dgpu-power}"
RUNNER="${HUAWEI_GPU_RUNNER:-/usr/local/bin/huawei-matebook-dgpu-run}"
SUDOERS_FILE="${HUAWEI_GPU_SUDOERS_FILE:-/etc/sudoers.d/huawei-matebook-dgpu}"
BOOT_SERVICE="${HUAWEI_GPU_BOOT_SERVICE:-/etc/systemd/system/huawei-matebook-dgpu-off.service}"
UDEV_RULE="${HUAWEI_GPU_UDEV_RULE:-/etc/udev/rules.d/61-huawei-matebook-igpu.rules}"
INTEL_ALIAS="${HUAWEI_GPU_INTEL_ALIAS:-/dev/dri/huawei-matebook-intel}"
SYSFS_PCI_DEVICES="${HUAWEI_GPU_SYSFS_PCI_DEVICES:-/sys/bus/pci/devices}"
DMI_ROOT="${HUAWEI_GPU_DMI_ROOT:-/sys/class/dmi/id}"
LIMINE_CONFIG="${HUAWEI_GPU_LIMINE_CONFIG:-/etc/default/limine}"
LIMINE_BOOT_CONFIG="${HUAWEI_GPU_LIMINE_BOOT_CONFIG:-/boot/limine.conf}"

XDG_CONFIG_HOME_EFFECTIVE="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_STATE_HOME_EFFECTIVE="${XDG_STATE_HOME:-$HOME/.local/state}"
CONFIG_DIR="$XDG_CONFIG_HOME_EFFECTIVE/huawei-matebook-gpu-manager"
USER_STATE_FILE="$CONFIG_DIR/state.json"
STATE_DIR="$XDG_STATE_HOME_EFFECTIVE/huawei-matebook-gpu-manager"
DESKTOP_STATE_DIR="$STATE_DIR/desktop"
STEAM_STATE_DIR="$STATE_DIR/steam"
LOCAL_APPS="${HUAWEI_GPU_LOCAL_APPS:-$HOME/.local/share/applications}"
KWIN_DROPIN_DIR="${HUAWEI_GPU_KWIN_DROPIN_DIR:-$XDG_CONFIG_HOME_EFFECTIVE/systemd/user/plasma-kwin_wayland.service.d}"
KWIN_DROPIN="$KWIN_DROPIN_DIR/61-huawei-matebook-igpu.conf"
CLEANUP_SERVICE_DIR="${HUAWEI_GPU_CLEANUP_SERVICE_DIR:-$XDG_CONFIG_HOME_EFFECTIVE/systemd/user}"
CLEANUP_SERVICE="$CLEANUP_SERVICE_DIR/huawei-matebook-dgpu-cleanup.service"
CLEANUP_TIMER="$CLEANUP_SERVICE_DIR/huawei-matebook-dgpu-cleanup.timer"

# Legacy v1 artifacts are discovered by behavior/name pattern rather than a
# private machine codename. Explicit HUAWEI_GPU_LEGACY_V1_* overrides remain
# available for recovery/testing on unusual historical installations.
USR_LOCAL_BIN="${HUAWEI_GPU_USR_LOCAL_BIN:-/usr/local/bin}"
USR_LOCAL_SBIN="${HUAWEI_GPU_USR_LOCAL_SBIN:-/usr/local/sbin}"
SUDOERS_DIR="${HUAWEI_GPU_SUDOERS_DIR:-/etc/sudoers.d}"
UDEV_RULES_DIR="${HUAWEI_GPU_UDEV_RULES_DIR:-/etc/udev/rules.d}"
PLASMA_ENV_DIR="${HUAWEI_GPU_PLASMA_ENV_DIR:-$XDG_CONFIG_HOME_EFFECTIVE/plasma-workspace/env}"
LEGACY_V1_RUNNER="${HUAWEI_GPU_LEGACY_V1_RUNNER:-}"
LEGACY_V1_POWER="${HUAWEI_GPU_LEGACY_V1_POWER:-}"
LEGACY_V1_SUDOERS="${HUAWEI_GPU_LEGACY_V1_SUDOERS:-}"
LEGACY_V1_UDEV="${HUAWEI_GPU_LEGACY_V1_UDEV:-}"
LEGACY_V1_KWIN="${HUAWEI_GPU_LEGACY_V1_KWIN:-}"
LEGACY_V1_OLD_KWIN_ENV="${HUAWEI_GPU_LEGACY_V1_OLD_KWIN_ENV:-}"
LEGACY_V1_STATE_DIR="${HUAWEI_GPU_LEGACY_V1_STATE_DIR:-$XDG_STATE_HOME_EFFECTIVE/huawei-gpu-manager}"
LEGACY_GENERATIONS=""
LEGACY_COMPONENTS=0
NO_DRIVER_INSTALL=0
MIGRATION_ACTIVE=0
MIGRATION_COMMITTED=0
MIGRATION_DIR=""
USER_STATE_CHECKED=0
USER_STATE_PREEXISTED=0
MIGRATION_ROOT="${HUAWEI_GPU_MIGRATION_ROOT:-$XDG_STATE_HOME_EFFECTIVE/huawei-matebook-gpu-manager-migrations}"
MANAGER_LOCK="${HUAWEI_GPU_MANAGER_LOCK:-${XDG_RUNTIME_DIR:-/tmp}/huawei-matebook-gpu-manager-${UID}.lock}"
MANAGER_LOCK_FD=""

# NVIDIA R580 documents PCIe RTD3 only for Turing or newer GPUs. The MX250 is
# Pascal, so full idle here deliberately relies on module unload + PCI remove.

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

if [[ $EUID -eq 0 && "${HUAWEI_GPU_TEST_MODE:-0}" != 1 ]]; then
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
    mkdir -p "$CONFIG_DIR" "$LOCAL_APPS" "$DESKTOP_STATE_DIR" "$STEAM_STATE_DIR" "$CLEANUP_SERVICE_DIR"
    chmod 0700 "$CONFIG_DIR" "$STATE_DIR" 2>/dev/null || true
}

array_has() {
    local needle="$1"; shift
    local x
    for x in "$@"; do [[ "$x" == "$needle" ]] && return 0; done
    return 1
}

# ---------------------------------------------------------------------------
# versioned user state + portable embedded manifest
# ---------------------------------------------------------------------------

array_add_unique() {
    local name="$1" value="$2" x
    local -n ref="$name"
    [[ -n "$value" ]] || return 0
    for x in "${ref[@]:-}"; do [[ "$x" == "$value" ]] && return 0; done
    ref+=("$value")
}

save_user_state() {
    ensure_dirs
    python3 - "$USER_STATE_FILE" "$STATE_SCHEMA" "$VERSION" "$STEAM_ALL" \
        "${#MANAGED_DESKTOP_APPS[@]}" "${MANAGED_DESKTOP_APPS[@]}" \
        "${#MANAGED_STEAM_APPS[@]}" "${MANAGED_STEAM_APPS[@]}" \
        "$LEGACY_GENERATIONS" <<'PY'
import json, os, sys, tempfile
from datetime import datetime, timezone
from pathlib import Path

path=Path(sys.argv[1]); schema=int(sys.argv[2]); version=sys.argv[3]; steam_all=bool(int(sys.argv[4]))
i=5; nd=int(sys.argv[i]); i+=1; desktop=sys.argv[i:i+nd]; i+=nd
ns=int(sys.argv[i]); i+=1; steam=sys.argv[i:i+ns]; i+=ns
legacy=[x for x in sys.argv[i].split() if x]
obj={
    "state_schema": schema,
    "manager_version": version,
    "managed_desktop_apps": sorted(dict.fromkeys(desktop)),
    "managed_steam_apps": sorted(dict.fromkeys(steam), key=lambda x: (not x.isdigit(), int(x) if x.isdigit() else x)),
    "steam_all": steam_all,
    "legacy_generations": sorted(dict.fromkeys(legacy)),
    "updated_at": datetime.now(timezone.utc).isoformat(),
}
path.parent.mkdir(parents=True,exist_ok=True)
fd,tmp=tempfile.mkstemp(prefix=path.name+'.',dir=path.parent)
try:
    with os.fdopen(fd,'w',encoding='utf-8') as f:
        json.dump(obj,f,indent=2,sort_keys=True); f.write('\n')
        f.flush(); os.fsync(f.fileno())
    os.chmod(tmp,0o600)
    os.replace(tmp,path)
finally:
    if os.path.exists(tmp): os.unlink(tmp)
PY
}

migrate_state_file() {
    [[ -f "$USER_STATE_FILE" ]] || return 0
    python3 - "$USER_STATE_FILE" "$STATE_SCHEMA" "$VERSION" <<'PY'
import json, os, sys, tempfile
from pathlib import Path
p=Path(sys.argv[1]); target=int(sys.argv[2]); version=sys.argv[3]
obj=json.loads(p.read_text(encoding='utf-8'))
schema=int(obj.get('state_schema',1))
if schema > target:
    raise SystemExit(f'state schema {schema} is newer than supported schema {target}')
while schema < target:
    if schema == 1:
        obj={
            'state_schema':2,
            'managed_desktop_apps':obj.get('desktop_apps',obj.get('managed_desktop_apps',[])),
            'managed_steam_apps':obj.get('steam_apps',obj.get('managed_steam_apps',[])),
            'steam_all':bool(obj.get('steam_all',False)),
            'legacy_generations':obj.get('legacy_generations',[]),
        }
        schema=2
    elif schema == 2:
        obj['state_schema']=3
        obj.setdefault('managed_desktop_apps',[])
        obj.setdefault('managed_steam_apps',[])
        obj.setdefault('steam_all',False)
        obj.setdefault('legacy_generations',[])
        schema=3
    else:
        raise SystemExit(f'no migration path from state schema {schema}')
obj['state_schema']=target
obj['manager_version']=version
obj['managed_desktop_apps']=sorted(dict.fromkeys(str(x) for x in obj.get('managed_desktop_apps',[]) if str(x)))
obj['managed_steam_apps']=sorted(dict.fromkeys(str(x) for x in obj.get('managed_steam_apps',[]) if str(x)), key=lambda x: (not x.isdigit(), int(x) if x.isdigit() else x))
obj['steam_all']=bool(obj.get('steam_all',False))
fd,tmp=tempfile.mkstemp(prefix=p.name+'.',dir=p.parent)
try:
    with os.fdopen(fd,'w',encoding='utf-8') as f:
        json.dump(obj,f,indent=2,sort_keys=True); f.write('\n')
    os.chmod(tmp,0o600); os.replace(tmp,p)
finally:
    if os.path.exists(tmp): os.unlink(tmp)
PY
}

load_user_state() {
    [[ -f "$USER_STATE_FILE" ]] || return 1
    migrate_state_file
    MANAGED_DESKTOP_APPS=()
    MANAGED_STEAM_APPS=()
    STEAM_ALL=0
    LEGACY_GENERATIONS=""
    local kind value
    while IFS=$'\t' read -r kind value; do
        case "$kind" in
            D) array_add_unique MANAGED_DESKTOP_APPS "$value" ;;
            S) array_add_unique MANAGED_STEAM_APPS "$value" ;;
            A) [[ "$value" == 1 ]] && STEAM_ALL=1 || STEAM_ALL=0 ;;
            L) [[ -n "$value" ]] && LEGACY_GENERATIONS+="${LEGACY_GENERATIONS:+ }$value" ;;
        esac
    done < <(python3 - "$USER_STATE_FILE" <<'PY'
import json,sys
obj=json.load(open(sys.argv[1],encoding='utf-8'))
for x in obj.get('managed_desktop_apps',[]): print('D\t'+str(x))
for x in obj.get('managed_steam_apps',[]): print('S\t'+str(x))
print('A\t'+('1' if obj.get('steam_all') else '0'))
for x in obj.get('legacy_generations',[]): print('L\t'+str(x))
PY
)
}

sync_embedded_manifest() {
    [[ -f "$SELF" && -w "$SELF" ]] || return 0
    python3 - "$SELF" "$STEAM_ALL" "${#MANAGED_DESKTOP_APPS[@]}" "${MANAGED_DESKTOP_APPS[@]}" \
        "${#MANAGED_STEAM_APPS[@]}" "${MANAGED_STEAM_APPS[@]}" <<'PY'
import os,re,sys,tempfile
from pathlib import Path
p=Path(sys.argv[1]); steam_all=int(sys.argv[2]); i=3
nd=int(sys.argv[i]); i+=1; desktop=sys.argv[i:i+nd]; i+=nd
ns=int(sys.argv[i]); i+=1; steam=sys.argv[i:i+ns]
text=p.read_text(encoding='utf-8')
m=re.search(r'(?ms)^# === HUAWEI_GPU_CONFIG_BEGIN ===\n(.*?)^# === HUAWEI_GPU_CONFIG_END ===$',text)
if not m: raise SystemExit('embedded config block not found')
def emit(name,vals):
    body='\n'.join('  "'+v.replace('\\','\\\\').replace('"','\\"')+'"' for v in vals)
    return f'{name}=(\n{body + chr(10) if body else ""})'
block=emit('MANAGED_DESKTOP_APPS',sorted(dict.fromkeys(desktop)))+'\n'+emit('MANAGED_STEAM_APPS',sorted(dict.fromkeys(steam)))+'\n'+f'STEAM_ALL={steam_all}\n'
new=text[:m.start(1)]+block+text[m.end(1):]
st=p.stat(); fd,tmp=tempfile.mkstemp(prefix=p.name+'.',dir=p.parent)
try:
    with os.fdopen(fd,'w',encoding='utf-8') as f: f.write(new)
    os.chmod(tmp,st.st_mode); os.replace(tmp,p)
finally:
    if os.path.exists(tmp): os.unlink(tmp)
PY
}

sync_persistent_state() {
    save_user_state
    sync_embedded_manifest || true
}

remember_desktop() {
    array_add_unique MANAGED_DESKTOP_APPS "$1"
    sync_persistent_state
}
forget_desktop() {
    local id="$1" x new=()
    for x in "${MANAGED_DESKTOP_APPS[@]:-}"; do [[ "$x" != "$id" ]] && new+=("$x"); done
    MANAGED_DESKTOP_APPS=("${new[@]}")
    sync_persistent_state
}
remember_steam() {
    array_add_unique MANAGED_STEAM_APPS "$1"
    sync_persistent_state
}
forget_steam() {
    local id="$1" x new=()
    for x in "${MANAGED_STEAM_APPS[@]:-}"; do [[ "$x" != "$id" ]] && new+=("$x"); done
    MANAGED_STEAM_APPS=("${new[@]}")
    sync_persistent_state
}

bootstrap_user_state() {
    local embedded_d=("${MANAGED_DESKTOP_APPS[@]:-}") embedded_s=("${MANAGED_STEAM_APPS[@]:-}") embedded_all="$STEAM_ALL" x
    if [[ "$USER_STATE_CHECKED" == 0 ]]; then
        [[ -f "$USER_STATE_FILE" ]] && USER_STATE_PREEXISTED=1 || USER_STATE_PREEXISTED=0
        USER_STATE_CHECKED=1
    fi
    if [[ -f "$USER_STATE_FILE" ]]; then load_user_state; fi
    for x in "${embedded_d[@]:-}"; do [[ -n "$x" ]] && array_add_unique MANAGED_DESKTOP_APPS "$x"; done
    for x in "${embedded_s[@]:-}"; do [[ -n "$x" ]] && array_add_unique MANAGED_STEAM_APPS "$x"; done
    [[ "$embedded_all" == 1 ]] && STEAM_ALL=1 || true
    return 0
}

# ---------------------------------------------------------------------------
# legacy discovery / import
# ---------------------------------------------------------------------------

installed_install_schema() {
    local schema="0"
    if [[ -r "$SYSTEM_CONFIG" ]]; then
        schema="$(sed -n 's/^INSTALL_SCHEMA=//p' "$SYSTEM_CONFIG" | head -n1)"
    fi
    [[ "$schema" =~ ^[0-9]+$ ]] || schema=0
    printf '%s\n' "$schema"
}

assert_install_schema_compatible() {
    local installed
    installed="$(installed_install_schema)"
    if (( installed > INSTALL_SCHEMA )); then
        err "Installed GPU Manager schema $installed is newer than this script supports ($INSTALL_SCHEMA). Refusing downgrade."
        return 2
    fi
    return 0
}

mode_switcher_guard() {
    local mode
    if command -v supergfxctl >/dev/null 2>&1; then
        mode="$(supergfxctl -g 2>/dev/null | tr -d '\r' | tail -n1 || true)"
        if [[ -n "$mode" && "${mode,,}" != integrated ]]; then
            err "supergfxctl reports '$mode'. Put supergfxctl in Integrated mode before installing/upgrading this manager."
            err "This script intentionally does not trigger a live supergfxctl mode switch because that may restart the graphical login session."
            return 2
        fi
    fi
    if systemctl is-active --quiet optimus-manager.service 2>/dev/null; then
        err "optimus-manager.service is active and conflicts with this manager's PCI/module lifecycle. Disable it before continuing."
        return 2
    fi
    return 0
}

discover_legacy_v1_paths() {
    local f power legacy_alias=""

    if [[ -z "$LEGACY_V1_RUNNER" ]]; then
        for f in "$USR_LOCAL_BIN"/*-dgpu-run; do
            [[ -f "$f" && "$f" != "$RUNNER" ]] || continue
            if grep -q '__NV_PRIME_RENDER_OFFLOAD=1' "$f" 2>/dev/null; then
                LEGACY_V1_RUNNER="$f"
                break
            fi
        done
    fi

    if [[ -z "$LEGACY_V1_POWER" && -n "$LEGACY_V1_RUNNER" && -r "$LEGACY_V1_RUNNER" ]]; then
        power="$(python3 - "$LEGACY_V1_RUNNER" <<'PY2'
from pathlib import Path
import re,sys
try:
    text=Path(sys.argv[1]).read_text(encoding='utf-8',errors='replace')
except Exception:
    raise SystemExit(0)
m=re.search(r'(?m)^\s*POWER=["\']?([^"\'\n]+)', text)
if m:
    print(m.group(1).strip())
PY2
)"
        [[ -n "$power" && -f "$power" ]] && LEGACY_V1_POWER="$power"
    fi

    if [[ -z "$LEGACY_V1_POWER" ]]; then
        for f in "$USR_LOCAL_SBIN"/*-dgpu-power; do
            [[ -f "$f" && "$f" != "$POWER_HELPER" ]] || continue
            if grep -qE '(MX250|10de:1d13|nvidia_drm)' "$f" 2>/dev/null; then
                LEGACY_V1_POWER="$f"
                break
            fi
        done
    fi

    if [[ -z "$LEGACY_V1_SUDOERS" && -n "$LEGACY_V1_POWER" && -d "$SUDOERS_DIR" ]]; then
        for f in "$SUDOERS_DIR"/*; do
            [[ -f "$f" && "$f" != "$SUDOERS_FILE" ]] || continue
            grep -Fq "$LEGACY_V1_POWER" "$f" 2>/dev/null && { LEGACY_V1_SUDOERS="$f"; break; }
        done
    fi

    if [[ -z "$LEGACY_V1_UDEV" && -d "$UDEV_RULES_DIR" ]]; then
        for f in "$UDEV_RULES_DIR"/*.rules; do
            [[ -f "$f" && "$f" != "$UDEV_RULE" ]] || continue
            if grep -q 'SUBSYSTEM=="drm"' "$f" 2>/dev/null && grep -q 'SYMLINK+="dri/.*intel' "$f" 2>/dev/null; then
                LEGACY_V1_UDEV="$f"
                break
            fi
        done
    fi

    if [[ -n "$LEGACY_V1_UDEV" && -r "$LEGACY_V1_UDEV" ]]; then
        legacy_alias="$(sed -n 's/.*SYMLINK+="\(dri\/[^" ]*\)".*/\/dev\/\1/p' "$LEGACY_V1_UDEV" | head -n1)"
    fi

    if [[ -z "$LEGACY_V1_KWIN" && -n "$legacy_alias" && -d "$KWIN_DROPIN_DIR" ]]; then
        for f in "$KWIN_DROPIN_DIR"/*.conf; do
            [[ -f "$f" && "$f" != "$KWIN_DROPIN" ]] || continue
            grep -Fq "KWIN_DRM_DEVICES=$legacy_alias" "$f" 2>/dev/null && { LEGACY_V1_KWIN="$f"; break; }
        done
    fi

    if [[ -z "$LEGACY_V1_OLD_KWIN_ENV" && -n "$legacy_alias" && -d "$PLASMA_ENV_DIR" ]]; then
        for f in "$PLASMA_ENV_DIR"/*.sh; do
            [[ -f "$f" ]] || continue
            grep -Fq "KWIN_DRM_DEVICES=$legacy_alias" "$f" 2>/dev/null && { LEGACY_V1_OLD_KWIN_ENV="$f"; break; }
        done
    fi
    return 0
}

known_runner_args() {
    printf '%s\n' "$RUNNER" "$LEGACY_V1_RUNNER" | awk 'NF && !seen[$0]++'
}

discover_legacy_generations() {
    local v1=0 v2=0 f runner
    discover_legacy_v1_paths
    [[ (-n "$LEGACY_V1_RUNNER" && -e "$LEGACY_V1_RUNNER") || (-n "$LEGACY_V1_POWER" && -e "$LEGACY_V1_POWER") || (-n "$LEGACY_V1_SUDOERS" && -e "$LEGACY_V1_SUDOERS") || -d "$LEGACY_V1_STATE_DIR" ]] && v1=1
    mapfile -t _legacy_runners < <(known_runner_args)
    for f in "$LOCAL_APPS"/*.desktop; do
        [[ -f "$f" ]] || continue
        if grep -q '^X-Huawei-GPU-Managed=true$' "$f" 2>/dev/null; then v1=1; break; fi
        for runner in "${_legacy_runners[@]:-}"; do
            [[ -n "$runner" && "$runner" != "$RUNNER" ]] || continue
            grep -Fq "$runner" "$f" 2>/dev/null && { v1=1; break 2; }
        done
    done
    if [[ -e "$POWER_HELPER" || -e "$RUNNER" || -e "$SYSTEM_CONFIG" ]]; then
        local installed
        installed="$(installed_install_schema)"
        if (( installed < INSTALL_SCHEMA )); then v2=1; fi
    fi
    LEGACY_GENERATIONS=""
    [[ "$v1" == 1 ]] && LEGACY_GENERATIONS="v1"
    [[ "$v2" == 1 ]] && LEGACY_GENERATIONS+="${LEGACY_GENERATIONS:+ }v2"
    LEGACY_COMPONENTS=$((v1+v2))
}

import_adjacent_script_manifests() {
    local scan="${HUAWEI_GPU_SCAN_DIRS:-$(dirname "$SELF"):$HOME/.local/bin}" kind value
    while IFS=$'\t' read -r kind value; do
        case "$kind" in
            D) array_add_unique MANAGED_DESKTOP_APPS "$value" ;;
            S) array_add_unique MANAGED_STEAM_APPS "$value" ;;
            A) [[ "$value" == 1 ]] && STEAM_ALL=1 || true ;;
        esac
    done < <(python3 - "$SELF" "$scan" <<'PY'
from pathlib import Path
import os,re,sys
selfp=Path(sys.argv[1]).resolve(); dirs=[Path(x).expanduser() for x in sys.argv[2].split(':') if x]
seen=set()
for d in dirs:
    if not d.is_dir(): continue
    for p in d.glob('*.sh'):
        try:
            if p.resolve()==selfp: continue
            text=p.read_text(encoding='utf-8',errors='replace')
        except Exception: continue
        m=re.search(r'(?ms)^# === HUAWEI_GPU_CONFIG_BEGIN ===\n(.*?)^# === HUAWEI_GPU_CONFIG_END ===$',text)
        if not m: continue
        block=m.group(1)
        for name,prefix in [('MANAGED_DESKTOP_APPS','D'),('MANAGED_STEAM_APPS','S')]:
            a=re.search(rf'(?ms)^{name}=\(\n(.*?)^\)$',block)
            if a:
                for line in a.group(1).splitlines():
                    q=re.match(r'^\s*"(.*)"\s*$',line)
                    if q:
                        v=q.group(1).replace('\\"','"').replace('\\\\','\\')
                        key=(prefix,v)
                        if key not in seen: print(prefix+'\t'+v); seen.add(key)
        sm=re.search(r'(?m)^STEAM_ALL=(\d+)$',block)
        if sm and sm.group(1)=='1': print('A\t1')
PY
)
}

import_legacy_desktop_apps() {
    local f runner matched
    mapfile -t _legacy_runners < <(known_runner_args)
    for f in "$LOCAL_APPS"/*.desktop; do
        [[ -f "$f" ]] || continue
        matched=0
        if grep -qE '^X-Huawei-(MateBook-)?GPU-Managed=true$' "$f" 2>/dev/null; then matched=1; fi
        if [[ "$matched" == 0 ]]; then
            for runner in "${_legacy_runners[@]:-}"; do
                [[ -n "$runner" ]] || continue
                grep -Fq "$runner" "$f" 2>/dev/null && { matched=1; break; }
            done
        fi
        [[ "$matched" == 1 ]] && array_add_unique MANAGED_DESKTOP_APPS "$(basename "$f")"
    done
}

import_legacy_backup_inventory() {
    # Recover managed selections even if an older personalized script was
    # overwritten before upgrade. v1/v2 stored enough per-app backup metadata
    # to reconstruct the intended Desktop/Steam selection.
    local root d f id
    for root in "$LEGACY_V1_STATE_DIR" "$STATE_DIR"; do
        [[ -d "$root" ]] || continue
        for d in "$root"/desktop/*; do
            [[ -d "$d" && -f "$d/captured" ]] || continue
            array_add_unique MANAGED_DESKTOP_APPS "$(basename "$d")"
        done
        for f in "$root"/steam/original/*.json; do
            [[ -f "$f" ]] || continue
            id="$(basename "$f" .json)"
            [[ "$id" =~ ^[0-9]+$ ]] && array_add_unique MANAGED_STEAM_APPS "$id"
        done
    done
    return 0
}

strip_known_runners_from_desktop() {
    local src="$1" dst="$2"
    mapfile -t _runners < <(known_runner_args)
    python3 - "$src" "$dst" "${_runners[@]}" <<'PY'
from pathlib import Path
import sys
src,dst=Path(sys.argv[1]),Path(sys.argv[2]); runners=sys.argv[3:]
lines=src.read_text(encoding='utf-8',errors='replace').splitlines(); out=[]; main=False
for line in lines:
    if line=='[Desktop Entry]': main=True
    elif line.startswith('[') and line.endswith(']'): main=False
    if main and line.startswith('Exec='):
        cmd=line[5:]
        for runner in runners:
            token=runner+' '
            while token in cmd: cmd=cmd.replace(token,'',1)
        line='Exec='+cmd
    if main and line.startswith('X-Huawei-MateBook-GPU-Managed='): continue
    out.append(line)
dst.write_text('\n'.join(out)+'\n',encoding='utf-8')
PY
}

import_legacy_steam_apps() {
    local vdf="${HUAWEI_GPU_STEAM_LOCALCONFIG:-}" id
    [[ -n "$vdf" ]] || vdf="$(steam_localconfig 2>/dev/null || true)"
    [[ -f "$vdf" ]] || return 0
    mapfile -t _legacy_runners < <(known_runner_args)
    while IFS= read -r id; do [[ -n "$id" ]] && array_add_unique MANAGED_STEAM_APPS "$id"; done < <(python3 - "$vdf" "${_legacy_runners[@]}" <<'PY3'
from pathlib import Path
import re,sys
text=Path(sys.argv[1]).read_text(encoding='utf-8',errors='replace')
runners=[x for x in sys.argv[2:] if x]
for m in re.finditer(r'"(\d+)"\s*\{',text):
    appid=m.group(1); start=m.end(); depth=1; ins=False; esc=False; end=None
    for i,c in enumerate(text[start:],start):
        if ins:
            if esc: esc=False
            elif c=='\\': esc=True
            elif c=='"': ins=False
            continue
        if c=='"': ins=True
        elif c=='{': depth+=1
        elif c=='}':
            depth-=1
            if depth==0: end=i; break
    if end is None: continue
    body=text[start:end]
    if any(r in body for r in runners): print(appid)
PY3
)
}

import_legacy_state() {
    discover_legacy_generations
    # External v3+ state is authoritative once it exists. Legacy artifacts may
    # remain after an interrupted cleanup, but must never resurrect selections
    # the user removed later. On a fresh install/legacy upgrade (no v3 state),
    # combine every recoverable source exactly once.
    if [[ "$USER_STATE_PREEXISTED" == 0 ]]; then
        import_adjacent_script_manifests
        import_legacy_backup_inventory
        import_legacy_desktop_apps
        import_legacy_steam_apps
    fi
    return 0
}

# ---------------------------------------------------------------------------
# hardware discovery
# ---------------------------------------------------------------------------

pci_find() {
    local vendor="$1" device="${2:-}" class_prefix="${3:-}"
    local d v x c
    for d in "$SYSFS_PCI_DEVICES"/*; do
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

rescan_pci() { echo 1 | sudo tee "$(dirname "$SYSFS_PCI_DEVICES")/rescan" >/dev/null; }

hardware_discover() {
    local initial_gpu=0 dgpu="" igpu="" root="" vendor="" product=""
    [[ -r "$DMI_ROOT/sys_vendor" ]] && vendor="$(<"$DMI_ROOT/sys_vendor")"
    [[ -r "$DMI_ROOT/product_name" ]] && product="$(<"$DMI_ROOT/product_name")"

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
        [[ "$initial_gpu" == 1 && -n "$dgpu" && -e "$SYSFS_PCI_DEVICES/$dgpu/remove" ]] && echo 1 | sudo tee "$SYSFS_PCI_DEVICES/$dgpu/remove" >/dev/null || true
        err "$(msg unsupported)"
        return 1
    fi

    local sys="$SYSFS_PCI_DEVICES/$dgpu"
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

    if [[ "$initial_gpu" == 1 && -e "$SYSFS_PCI_DEVICES/$dgpu/remove" ]]; then
        echo 1 | sudo tee "$SYSFS_PCI_DEVICES/$dgpu/remove" >/dev/null
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
    elif command -v zypper >/dev/null 2>&1; then echo opensuse
    else echo unknown
    fi
}

nvidia_580_ready() {
    local v=""
    v="$(modinfo -F version nvidia 2>/dev/null | head -n1 || true)"
    [[ "$v" == 580.* ]]
}

require_core_commands() {
    local missing=0 c
    for c in python3 sudo lspci fuser flock modprobe udevadm systemctl; do
        command -v "$c" >/dev/null 2>&1 || { err "Missing required command: $c"; missing=1; }
    done
    [[ "$missing" == 0 ]]
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
        opensuse)
            sudo zypper --non-interactive install pciutils psmisc util-linux python3 sudo
            ;;
        unknown)
            require_core_commands
            ;;
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
            err "Arch requires NVIDIA's legacy R580 branch for Pascal. Install nvidia-580xx-dkms and nvidia-580xx-utils from the AUR, then rerun."
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

fedora_repo_version_580() {
    local pkg="$1" v
    v="$(dnf -q repoquery --available --qf '%{version}' "$pkg" 2>/dev/null | sort -V | tail -n1 || true)"
    [[ "$v" == 580.* ]]
}

install_nvidia_580_fedora() {
    if rpm -qa 2>/dev/null | grep -Eq '^akmod-nvidia(-580xx)?-.*580\.'; then return 0; fi
    if dnf -q repoquery --available akmod-nvidia-580xx >/dev/null 2>&1; then
        sudo dnf install -y akmod-nvidia-580xx xorg-x11-drv-nvidia-580xx xorg-x11-drv-nvidia-580xx-cuda
    elif fedora_repo_version_580 akmod-nvidia; then
        sudo dnf install -y akmod-nvidia xorg-x11-drv-nvidia xorg-x11-drv-nvidia-cuda
    else
        err "Fedora requires an enabled RPM Fusion package providing NVIDIA R580 for Pascal. The manager will not enable third-party repositories automatically."
        return 2
    fi
    command -v akmods >/dev/null 2>&1 && sudo akmods --force || true
}

install_nvidia_580_debian() {
    if dpkg-query -W -f='${Status}' nvidia-driver-580 2>/dev/null | grep -q 'install ok installed'; then return 0; fi
    if apt-cache show nvidia-driver-580 >/dev/null 2>&1; then
        sudo apt-get install -y nvidia-driver-580
    else
        err "This Debian/Ubuntu installation does not expose nvidia-driver-580 in enabled repositories. Install a supported R580 proprietary driver using the distribution/NVIDIA workflow, then rerun with --no-driver-install."
        return 2
    fi
}

install_graphics_tools() {
    local pm="$1"
    case "$pm" in
        arch) sudo pacman -S --needed mesa-utils vulkan-tools 2>/dev/null || true ;;
        fedora) sudo dnf install -y glx-utils vulkan-tools 2>/dev/null || sudo dnf install -y mesa-demos vulkan-tools 2>/dev/null || true ;;
        debian) sudo apt-get install -y mesa-utils vulkan-tools 2>/dev/null || true ;;
        opensuse) sudo zypper --non-interactive install Mesa-demo-x vulkan-tools 2>/dev/null || true ;;
    esac
}

install_packages() {
    local pm current_nvidia
    pm="$(pm_family)"
    info "Package family: $pm"
    install_common_packages "$pm"

    current_nvidia="$(modinfo -F version nvidia 2>/dev/null | head -n1 || true)"
    if [[ -n "$current_nvidia" && "$current_nvidia" != 580.* ]]; then
        err "An NVIDIA driver outside the R580 branch is installed: $current_nvidia"
        err "MX250/Pascal requires proprietary R580; NVIDIA 590+ no longer supports Pascal."
        err "This manager will not remove/replace an existing driver automatically."
        return 2
    fi

    if ! nvidia_580_ready; then
        if [[ "$NO_DRIVER_INSTALL" == 1 ]]; then
            err "--no-driver-install was requested, but an NVIDIA R580 kernel module is not available."
            return 2
        fi
        case "$pm" in
            arch) install_nvidia_580_arch ;;
            fedora) install_nvidia_580_fedora ;;
            debian) install_nvidia_580_debian ;;
            opensuse|unknown)
                err "Automatic NVIDIA driver installation is intentionally disabled for $pm. Install proprietary R580 first, then rerun with --no-driver-install."
                return 2
                ;;
        esac
    else
        info "NVIDIA R580 kernel module already available."
    fi
    nvidia_580_ready || { err "NVIDIA R580 verification failed after package setup."; return 2; }
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
MANAGER_VERSION="$VERSION"
INSTALL_SCHEMA=$INSTALL_SCHEMA
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

    rebuild_initramfs
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
shopt -s nullglob

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
    for f in /dev/nvidia0 /dev/nvidiactl /dev/nvidia-modeset /dev/nvidia-uvm /dev/nvidia-uvm-tools /dev/nvidia-caps/* "$render"; do
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

    modprobe -r nvidia_uvm 2>/dev/null || true
    modprobe -r nvidia_drm 2>/dev/null || true
    modprobe -r nvidia_modeset 2>/dev/null || true
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
# Avoid inheriting a desktop/session Vulkan driver filter that can hide NVIDIA.
unset VK_LOADER_DRIVERS_SELECT
# Optional compatibility fallback; not enabled by default because Steam/Pressure Vessel
# has historically had issues with host-side loader manifest filtering.
if [[ "\${HUAWEI_GPU_VK_DRIVER_FILTER:-0}" == 1 ]]; then
    export VK_LOADER_DRIVERS_SELECT='*nvidia*'
fi
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
    systemctl --user enable --now huawei-matebook-dgpu-cleanup.timer >/dev/null
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
    strip_known_runners_from_desktop "$1" "$2"
}

import_legacy_desktop_backup() {
    local id="$1" state="$2" legacy="$LEGACY_V1_STATE_DIR/desktop/$id"
    [[ -f "$state/captured" || ! -f "$legacy/captured" ]] && return 0
    mkdir -p "$state"
    cp -a "$legacy/captured" "$state/captured"
    [[ -f "$legacy/had_local" ]] && cp -a "$legacy/had_local" "$state/had_local" || echo 1 > "$state/had_local"
    [[ -f "$legacy/original.desktop" ]] && cp -a "$legacy/original.desktop" "$state/original.desktop"
}

apply_desktop_app() {
    local requested="$1" remember="${2:-true}" src id dst state tmp normalized
    ensure_dirs
    src="$(resolve_desktop_source "$requested" 2>/dev/null || true)"
    [[ -n "$src" ]] || { err "Application not found: $requested"; return 2; }
    id="$(basename "$src")"; dst="$LOCAL_APPS/$id"; state="$DESKTOP_STATE_DIR/$id"
    mkdir -p "$state"
    import_legacy_desktop_backup "$id" "$state"
    if [[ ! -f "$state/captured" ]]; then
        if [[ -f "$dst" ]]; then
            strip_known_runners_from_desktop "$dst" "$state/original.desktop"
            echo 1 > "$state/had_local"
        else
            echo 0 > "$state/had_local"
        fi
        touch "$state/captured"
    fi
    tmp="$(mktemp)"; normalized="$(mktemp)"
    cp -a "$src" "$tmp"
    strip_known_runners_from_desktop "$tmp" "$normalized"
    rewrite_desktop_gpu "$normalized" "$dst"
    rm -f "$tmp" "$normalized"
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
    local id rc=0
    for id in "${MANAGED_DESKTOP_APPS[@]:-}"; do
        [[ -n "$id" ]] || continue
        apply_desktop_app "$id" false || { rc=$?; break; }
    done
    return "$rc"
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
    if [[ -n "${HUAWEI_GPU_STEAM_LOCALCONFIG:-}" ]]; then
        [[ -f "$HUAWEI_GPU_STEAM_LOCALCONFIG" ]] && printf '%s\n' "$HUAWEI_GPU_STEAM_LOCALCONFIG"
        return
    fi
    local root; root="$(steam_root)" || return 1
    find "$root/userdata" -mindepth 2 -maxdepth 2 -type f -name localconfig.vdf -print 2>/dev/null | head -n1
}
steam_game_name() { steam_games_tsv 2>/dev/null | awk -F'\t' -v id="$1" '$1==id {print $2; exit}'; }

import_legacy_steam_backup() {
    local appid="$1" target="$STEAM_STATE_DIR/original/$appid.json"
    [[ -f "$target" ]] && return 0
    local candidate
    for candidate in         "$LEGACY_V1_STATE_DIR/steam/original/$appid.json"         "$LEGACY_V1_STATE_DIR/original/$appid.json"; do
        if [[ -f "$candidate" ]]; then
            mkdir -p "$(dirname "$target")"
            cp -a "$candidate" "$target"
            return 0
        fi
    done
}

steam_edit_launchoption() {
    local action="$1" appid="$2" vdf
    vdf="$(steam_localconfig)"; [[ -f "$vdf" ]] || { err "Steam localconfig.vdf not found"; return 1; }
    steam_running && { err "$(msg steam_close)"; return 3; }
    mkdir -p "$STEAM_STATE_DIR/backups" "$STEAM_STATE_DIR/original"
    import_legacy_steam_backup "$appid"
    cp -a "$vdf" "$STEAM_STATE_DIR/backups/localconfig.vdf.$(date +%Y%m%d-%H%M%S)"
    mapfile -t _known_runners < <(known_runner_args)
    python3 - "$vdf" "$action" "$appid" "$RUNNER" "$STEAM_STATE_DIR/original/$appid.json" "${_known_runners[@]}" <<'PY'
from pathlib import Path
import json,re,sys
path=Path(sys.argv[1]); action=sys.argv[2]; appid=sys.argv[3]; runner=sys.argv[4]; state=Path(sys.argv[5]); known=sys.argv[6:]
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
def baseline(s):
    out=s
    for r in [runner,*known]:
        out=out.replace(r+' %command%','%command%').replace(r+' ','')
    out=out.strip()
    return '' if out in ('%command%','') else out
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
        base=baseline(cur)
        if not state.exists(): state.write_text(json.dumps({'had':bool(base),'value':base}))
        if runner not in cur or any(r in cur for r in known):
            curbase=base
            if '%command%' in curbase:
                new=curbase.replace('%command%',runner+' %command%',1)
            elif curbase:
                new=runner+' %command% '+curbase
            else:
                new=runner+' %command%'
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
            new=baseline(cur)
            if new:
                line=lm.group(1)+'"LaunchOptions"\t\t"'+enc(new)+'"'; body=body[:lm.start()]+line+body[lm.end():]
            else:
                body=body[:lm.start()]+body[lm.end():]
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
    STEAM_ALL=1
    [[ "${1:-true}" == true ]] && sync_persistent_state
    info "All currently installed Steam games are configured for MX250 on-demand."
}
steam_disable_all() {
    steam_running && { err "$(msg steam_close)"; return 3; }
    local id name
    while IFS=$'\t' read -r id name; do [[ -n "$id" ]] && steam_edit_launchoption remove "$id" || true; done < <(steam_games_tsv 2>/dev/null || true)
    # Also restore saved state for games that are no longer installed but still have a known APPID.
    for id in "${MANAGED_STEAM_APPS[@]:-}"; do [[ -n "$id" ]] && steam_edit_launchoption remove "$id" 2>/dev/null || true; done
    STEAM_ALL=0
    [[ "${1:-true}" == true ]] && sync_persistent_state
    info "Global Steam GPU on-demand mode disabled; saved LaunchOptions restored where available."
}
apply_saved_steam_apps() {
    steam_running && { warn "$(msg steam_close)"; return 3; }
    local id name rc=0
    if [[ "$STEAM_ALL" == 1 ]]; then
        while IFS=$'\t' read -r id name; do
            [[ -n "$id" ]] || continue
            steam_add_game "$id" false || rc=$?
            (( rc == 0 )) || break
        done < <(steam_games_tsv 2>/dev/null || true)
    else
        for id in "${MANAGED_STEAM_APPS[@]:-}"; do
            [[ -n "$id" ]] || continue
            steam_add_game "$id" false || { rc=$?; break; }
        done
    fi
    return "$rc"
}

# ---------------------------------------------------------------------------
# transactional install / upgrade helpers
# ---------------------------------------------------------------------------

manager_lock_acquire() {
    mkdir -p "$(dirname "$MANAGER_LOCK")"
    exec {MANAGER_LOCK_FD}>"$MANAGER_LOCK"
    flock -n "$MANAGER_LOCK_FD" || { err "Another Huawei GPU Manager operation is already running."; return 73; }
}

manager_nvidia_users() {
    local f render="" bdf
    bdf="$(find_dgpu_bdf 2>/dev/null || true)"
    if [[ -n "$bdf" ]]; then render="$(readlink -f "/dev/dri/by-path/pci-${bdf}-render" 2>/dev/null || true)"; fi
    for f in /dev/nvidia0 /dev/nvidiactl /dev/nvidia-modeset /dev/nvidia-uvm /dev/nvidia-uvm-tools /dev/nvidia-caps/* "$render"; do
        [[ -n "$f" && -e "$f" ]] || continue
        fuser "$f" 2>/dev/null || true
    done | tr ' ' '\n' | grep -E '^[0-9]+$' | sort -u
}

show_nvidia_users() {
    local users csv
    users="$(manager_nvidia_users || true)"
    [[ -n "$users" ]] || return 0
    csv="$(tr '\n' ',' <<<"$users" | sed 's/,$//')"
    err "NVIDIA is still in use by PID(s): ${users//$'\n'/ }"
    ps -o pid,user,comm,args -p "$csv" 2>/dev/null >&2 || true
}

normalize_idle_state() {
    local bdf users
    bdf="$(find_dgpu_bdf 2>/dev/null || true)"
    [[ -n "$bdf" ]] || return 0
    info "MX250 is currently enumerated; attempting a safe return to full Integrated idle."

    if [[ -x "$POWER_HELPER" ]]; then sudo "$POWER_HELPER" cleanup >/dev/null 2>&1 || true; fi
    bdf="$(find_dgpu_bdf 2>/dev/null || true)"
    [[ -n "$bdf" ]] || return 0

    if [[ -x "$LEGACY_V1_POWER" ]]; then sudo "$LEGACY_V1_POWER" off >/dev/null 2>&1 || true; fi
    bdf="$(find_dgpu_bdf 2>/dev/null || true)"
    [[ -n "$bdf" ]] || return 0

    users="$(manager_nvidia_users || true)"
    if [[ -n "$users" ]]; then
        show_nvidia_users
        err "Close the NVIDIA workload above and retry. The manager will not kill applications or unload an in-use GPU."
        return 75
    fi

    sudo systemctl stop nvidia-persistenced.service >/dev/null 2>&1 || true
    sudo modprobe -r nvidia_uvm 2>/dev/null || true
    sudo modprobe -r nvidia_drm 2>/dev/null || true
    sudo modprobe -r nvidia_modeset 2>/dev/null || true
    sudo modprobe -r nvidia 2>/dev/null || true

    if lsmod | awk '$1 ~ /^nvidia/ {found=1} END{exit !found}'; then
        show_nvidia_users
        err "NVIDIA kernel modules are still loaded; refusing PCI removal."
        return 75
    fi

    bdf="$(find_dgpu_bdf 2>/dev/null || true)"
    if [[ -n "$bdf" && -w "$SYSFS_PCI_DEVICES/$bdf/remove" ]]; then
        echo 1 | sudo tee "$SYSFS_PCI_DEVICES/$bdf/remove" >/dev/null
        for _ in $(seq 1 30); do
            [[ -z "$(find_dgpu_bdf 2>/dev/null || true)" ]] && break
            sleep 0.1
        done
    fi
    [[ -z "$(find_dgpu_bdf 2>/dev/null || true)" ]] || { err "MX250 PCI removal failed."; return 1; }
    return 0
}

path_requires_root() {
    case "$1" in /etc/*|/usr/*|/opt/*) return 0 ;; *) return 1 ;; esac
}

migration_snapshot_path() {
    local path="$1" manifest="$MIGRATION_DIR/manifest.tsv" backup="$MIGRATION_DIR/files$path"
    [[ -n "$path" ]] || return 0
    if [[ -e "$path" || -L "$path" ]]; then
        printf 'PRESENT\t%s\n' "$path" >> "$manifest"
        mkdir -p "$(dirname "$backup")"
        if path_requires_root "$path"; then sudo cp -a -- "$path" "$backup"
        else cp -a -- "$path" "$backup"
        fi
    else
        printf 'ABSENT\t%s\n' "$path" >> "$manifest"
    fi
}

migration_begin() {
    local stamp path vdf id
    stamp="$(date +%Y%m%d-%H%M%S)-$$"
    MIGRATION_DIR="$MIGRATION_ROOT/$stamp"
    mkdir -p "$MIGRATION_DIR/files"
    : > "$MIGRATION_DIR/manifest.tsv"
    MIGRATION_ACTIVE=1
    MIGRATION_COMMITTED=0

    systemctl is-enabled huawei-matebook-dgpu-off.service >/dev/null 2>&1 && echo 1 > "$MIGRATION_DIR/system-service-enabled" || echo 0 > "$MIGRATION_DIR/system-service-enabled"
    systemctl --user is-enabled huawei-matebook-dgpu-cleanup.timer >/dev/null 2>&1 && echo 1 > "$MIGRATION_DIR/user-timer-enabled" || echo 0 > "$MIGRATION_DIR/user-timer-enabled"

    for path in \
        "$SYSTEM_CONFIG" "$MODPROBE_CONFIG" "$POWER_HELPER" "$RUNNER" "$SUDOERS_FILE" "$BOOT_SERVICE" "$UDEV_RULE" \
        "$KWIN_DROPIN" "$CLEANUP_SERVICE" "$CLEANUP_TIMER" "$LOCAL_APPS/steam.desktop" \
        "$LEGACY_V1_RUNNER" "$LEGACY_V1_POWER" "$LEGACY_V1_SUDOERS" "$LEGACY_V1_UDEV" "$LEGACY_V1_KWIN" "$LEGACY_V1_OLD_KWIN_ENV" \
        "$CONFIG_DIR" "$STATE_DIR" "$LEGACY_V1_STATE_DIR"; do
        migration_snapshot_path "$path"
    done

    for id in "${MANAGED_DESKTOP_APPS[@]:-}"; do
        [[ -n "$id" ]] && migration_snapshot_path "$LOCAL_APPS/$id"
    done
    vdf="$(steam_localconfig 2>/dev/null || true)"
    [[ -n "$vdf" ]] && migration_snapshot_path "$vdf"

    info "Migration snapshot: $MIGRATION_DIR"
}

migration_restore_manifest() {
    local state path backup
    tac "$MIGRATION_DIR/manifest.tsv" | while IFS=$'\t' read -r state path; do
        [[ -n "$path" ]] || continue
        backup="$MIGRATION_DIR/files$path"
        if path_requires_root "$path"; then
            sudo rm -rf -- "$path"
            [[ "$state" == PRESENT ]] && { sudo mkdir -p "$(dirname "$path")"; sudo cp -a -- "$backup" "$path"; }
        else
            rm -rf -- "$path"
            [[ "$state" == PRESENT ]] && { mkdir -p "$(dirname "$path")"; cp -a -- "$backup" "$path"; }
        fi
    done
}

limine_mkinitcpio_active() {
    command -v limine-mkinitcpio >/dev/null 2>&1 || return 1
    [[ -e "$LIMINE_CONFIG" || -e "$LIMINE_BOOT_CONFIG" ]]
}

rebuild_initramfs() {
    # CachyOS/Arch with Limine must use limine-mkinitcpio so the generated
    # initramfs images and Limine kernel entries stay in sync. Calling plain
    # mkinitcpio -P on such systems can have no presets and may trigger an
    # interactive hand-off prompt instead of performing a clean unattended
    # rebuild.
    if limine_mkinitcpio_active; then sudo limine-mkinitcpio
    elif command -v mkinitcpio >/dev/null 2>&1; then sudo mkinitcpio -P
    elif command -v dracut >/dev/null 2>&1; then sudo dracut -f
    elif command -v update-initramfs >/dev/null 2>&1; then sudo update-initramfs -u
    else
        warn "No supported initramfs rebuild tool found; continuing without rebuilding initramfs."
        return 0
    fi
}

migration_rollback() {
    [[ "$MIGRATION_ACTIVE" == 1 && "$MIGRATION_COMMITTED" == 0 && -n "$MIGRATION_DIR" ]] || return 0
    warn "Install/upgrade failed; restoring the pre-migration configuration."
    systemctl --user disable --now huawei-matebook-dgpu-cleanup.timer >/dev/null 2>&1 || true
    sudo systemctl disable --now huawei-matebook-dgpu-off.service >/dev/null 2>&1 || true
    migration_restore_manifest
    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl --user daemon-reload >/dev/null 2>&1 || true
    [[ "$(cat "$MIGRATION_DIR/system-service-enabled" 2>/dev/null || echo 0)" == 1 ]] && sudo systemctl enable huawei-matebook-dgpu-off.service >/dev/null 2>&1 || true
    [[ "$(cat "$MIGRATION_DIR/user-timer-enabled" 2>/dev/null || echo 0)" == 1 ]] && systemctl --user enable --now huawei-matebook-dgpu-cleanup.timer >/dev/null 2>&1 || true
    rebuild_initramfs || true
    MIGRATION_ACTIVE=0
    warn "Rollback completed. Legacy configuration was preserved."
}

migration_commit() {
    mkdir -p "$STATE_DIR"
    python3 - "$STATE_DIR/last-migration.json" "$VERSION" "$STATE_SCHEMA" "$INSTALL_SCHEMA" "$LEGACY_GENERATIONS" <<'PY'
import json,os,sys,tempfile,time
from pathlib import Path
p=Path(sys.argv[1]); p.parent.mkdir(parents=True,exist_ok=True)
obj={'manager_version':sys.argv[2],'state_schema':int(sys.argv[3]),'install_schema':int(sys.argv[4]),
     'legacy_generations':[x for x in sys.argv[5].split() if x], 'committed_at':int(time.time())}
fd,tmp=tempfile.mkstemp(prefix=p.name+'.',dir=p.parent)
try:
    with os.fdopen(fd,'w',encoding='utf-8') as f: json.dump(obj,f,indent=2,sort_keys=True); f.write('\n')
    os.chmod(tmp,0o600); os.replace(tmp,p)
finally:
    if os.path.exists(tmp): os.unlink(tmp)
PY
    MIGRATION_COMMITTED=1
    MIGRATION_ACTIVE=0
}

cleanup_legacy_v1() {
    [[ " $LEGACY_GENERATIONS " == *" v1 "* ]] || return 0
    info "Removing obsolete v1 infrastructure after successful v3 validation."
    local path
    for path in "$LEGACY_V1_RUNNER" "$LEGACY_V1_POWER" "$LEGACY_V1_SUDOERS" "$LEGACY_V1_UDEV"; do
        [[ -n "$path" ]] && sudo rm -f -- "$path"
    done
    for path in "$LEGACY_V1_KWIN" "$LEGACY_V1_OLD_KWIN_ENV"; do
        [[ -n "$path" ]] && rm -f -- "$path"
    done
    [[ -n "$LEGACY_V1_STATE_DIR" ]] && rm -rf -- "$LEGACY_V1_STATE_DIR"
    sudo udevadm control --reload-rules >/dev/null 2>&1 || true
    systemctl --user daemon-reload >/dev/null 2>&1 || true
}

install_reconcile_steps() {
    install_packages || return
    install_system_config || return
    install_modprobe_policy || return
    install_udev_alias || return
    install_kwin_isolation || return
    install_power_helper || return
    install_runner || return
    install_sudoers || return
    install_boot_service || return
    install_cleanup_timer || return
    configure_steam_client_intel || return
    apply_saved_desktop_apps || return
    apply_saved_steam_apps || return
    return 0
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
    manager_lock_acquire || return
    assert_install_schema_compatible || return
    mode_switcher_guard || return
    bold "Huawei MateBook 13 GPU Manager $VERSION — $(msg install_title)"
    line

    bootstrap_user_state
    import_legacy_state
    normalize_idle_state || return
    hardware_discover || return
    migration_begin || return
    sync_persistent_state || { migration_rollback; return 1; }

    local rc
    if install_reconcile_steps; then
        :
    else
        rc=$?
        migration_rollback
        return "$rc"
    fi

    # A legacy upgrade is not committed until the new runtime completes a real
    # NVIDIA render test and returns to full Integrated idle successfully.
    if (( LEGACY_COMPONENTS > 0 )); then
        if smoke_test; then
            :
        else
            rc=$?
            migration_rollback
            return "$rc"
        fi
    fi

    migration_commit
    cleanup_legacy_v1 || warn "Legacy v1 cleanup was incomplete; run doctor for details."
    sync_persistent_state
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
    local current_dgpu
    current_dgpu="$(find_dgpu_bdf 2>/dev/null || true)"
    printf 'CURRENT_DGPU_BDF=%s\n' "${current_dgpu:-ABSENT}"
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
    local out st

    if command -v glxinfo >/dev/null 2>&1; then
        out="$("$RUNNER" glxinfo -B 2>&1)" || { printf '%s\n' "$out"; return 1; }
        printf '%s\n' "$out" | grep -Ei 'direct rendering|OpenGL vendor|OpenGL renderer|OpenGL version' || true
        grep -Eqi 'OpenGL (vendor|string|renderer).*NVIDIA|NVIDIA.*OpenGL|NVIDIA GeForce MX250' <<<"$out" || {
            err "OpenGL PRIME test did not select NVIDIA."
            return 1
        }
    else
        "$RUNNER" true || return
    fi

    if command -v vulkaninfo >/dev/null 2>&1; then
        out="$("$RUNNER" vulkaninfo --summary 2>&1)" || {
            printf '%s\n' "$out"
            err "Vulkan PRIME test failed. The manager does not force VK_LOADER_DRIVERS_SELECT by default because it can conflict with containerized Steam runtimes."
            return 1
        }
        printf '%s\n' "$out" | grep -Ei 'deviceName|driverName|driverInfo|NVIDIA|MX250' | head -30 || true
        grep -Eqi 'NVIDIA|GeForce MX250' <<<"$out" || { err "Vulkan PRIME test did not expose NVIDIA."; return 1; }
    fi

    sleep 1
    sudo -n "$POWER_HELPER" cleanup >/dev/null 2>&1 || sudo "$POWER_HELPER" cleanup >/dev/null 2>&1 || true
    st="$(sudo -n "$POWER_HELPER" status 2>/dev/null || sudo "$POWER_HELPER" status)" || return
    printf '%s\n' "$st"
    grep -q '^GPU_PRESENT=NO$' <<<"$st" || { err "MX250 did not return to PCI-absent idle."; return 1; }
    grep -q '^LEASES=0$' <<<"$st" || { err "Managed GPU leases remain after the test."; return 1; }
    if grep -Eq '^NVIDIA_MODULES=.+[^[:space:]]' <<<"$st"; then
        err "NVIDIA modules remain loaded after the test."
        return 1
    fi
    return 0
}
doctor() {
    local detected_install=0 legacy current version kwin drift=0 gpu_idle="UNKNOWN"
    discover_legacy_generations
    if [[ -r "$SYSTEM_CONFIG" ]]; then
        detected_install="$(sed -n 's/^INSTALL_SCHEMA=//p' "$SYSTEM_CONFIG" | head -n1)"
        [[ "$detected_install" =~ ^[0-9]+$ ]] || detected_install=0
    fi
    current="$(find_dgpu_bdf 2>/dev/null || true)"
    version="$(modinfo -F version nvidia 2>/dev/null | head -n1 || true)"

    if [[ -f "$KWIN_DROPIN" ]] && grep -q "KWIN_DRM_DEVICES=$INTEL_ALIAS" "$KWIN_DROPIN" && grep -q '^Environment=KWIN_RENDER_NODES=$' "$KWIN_DROPIN"; then
        kwin="OK"
    elif plasma_wayland_detected; then kwin="MISSING"
    else kwin="NOT_VALIDATED"
    fi

    # Validate the privileged path functionally. A correctly secured sudoers file
    # is normally root:root 0440 and therefore intentionally unreadable by the
    # invoking user; testing `-r "$SUDOERS_FILE"` would report false drift.
    [[ -x "$POWER_HELPER" && -x "$RUNNER" && -r "$SYSTEM_CONFIG" && -r "$UDEV_RULE" ]] || drift=1
    sudo -n "$POWER_HELPER" status >/dev/null 2>&1 || drift=1
    [[ "$detected_install" == "$INSTALL_SCHEMA" ]] || drift=1
    (( LEGACY_COMPONENTS == 0 )) || drift=1

    if [[ -z "$current" ]] && ! lsmod | grep -q '^nvidia'; then gpu_idle="FULL_INTEGRATED"
    elif [[ -n "$current" ]]; then gpu_idle="NOT_IDLE"
    fi

    printf 'MANAGER_VERSION=%s\n' "$VERSION"
    printf 'STATE_SCHEMA=%s\n' "$STATE_SCHEMA"
    printf 'INSTALL_SCHEMA=%s\n' "$detected_install"
    printf 'LEGACY_COMPONENTS=%s\n' "$LEGACY_COMPONENTS"
    printf 'LEGACY_GENERATIONS=%s\n' "${LEGACY_GENERATIONS:-NONE}"
    printf 'GPU_PRESENT=%s\n' "$([[ -n "$current" ]] && echo YES || echo NO)"
    printf 'NVIDIA_VERSION=%s\n' "${version:-ABSENT}"
    printf 'KWIN_ISOLATION=%s\n' "$kwin"
    printf 'CONFIG_DRIFT=%s\n' "$([[ "$drift" == 0 ]] && echo NO || echo YES)"
    printf 'GPU_IDLE=%s\n' "$gpu_idle"
    return 0
}

list_managed() {
    echo 'Desktop:'
    local x
    for x in "${MANAGED_DESKTOP_APPS[@]:-}"; do [[ -n "$x" ]] && echo "  - $x"; done
    echo 'Steam:'
    echo "  all=$STEAM_ALL"
    for x in "${MANAGED_STEAM_APPS[@]:-}"; do [[ -n "$x" ]] && echo "  - $x"; done
    return 0
}

restore_steam_client() {
    local d="$STATE_DIR/steam-client" dst="$LOCAL_APPS/steam.desktop"
    [[ -f "$d/captured" ]] || return 0
    if [[ "$(cat "$d/had_local" 2>/dev/null || echo 0)" == 1 && -f "$d/original.desktop" ]]; then cp -a "$d/original.desktop" "$dst"; else rm -f "$dst"; fi
    rm -rf "$d"
}

uninstall_core() {
    confirm "Remove the on-demand GPU infrastructure?" || return 0
    manager_lock_acquire || return
    normalize_idle_state || return
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
    rebuild_initramfs || true
    warn "Reboot recommended. NVIDIA packages and portable application state were intentionally left installed."
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
1) Installer / mettre à niveau / réparer
2) Ajouter une application Desktop
3) Retirer une application Desktop
4) Ajouter un jeu Steam
5) Retirer un jeu Steam
6) Tous les jeux Steam -> MX250
7) Réappliquer les applications enregistrées
8) Lister
9) Doctor / diagnostic complet
10) Test GPU à la demande
11) Désinstaller l'infrastructure
0) Quitter
MENU
        else
            cat <<'MENU'
1) Install / upgrade / repair
2) Add a Desktop application
3) Remove a Desktop application
4) Add a Steam game
5) Remove a Steam game
6) All installed Steam games -> MX250
7) Re-apply saved applications
8) List
9) Doctor / full diagnostic
10) Test on-demand GPU
11) Uninstall infrastructure
0) Quit
MENU
        fi
        local c id rc
        read -r -p '> ' c
        case "$c" in
            1)
                if install_core; then :; else rc=$?; warn "Operation failed (rc=$rc). Configuration was not committed unless validation had already succeeded."; fi
                pause ;;
            2)
                if id="$(search_desktop_app)"; then apply_desktop_app "$id" true || warn "Unable to enable GPU management for $id."; fi
                pause ;;
            3)
                if id="$(choose_managed_desktop)"; then remove_desktop_app "$id" || warn "Unable to remove GPU management for $id."; fi
                pause ;;
            4)
                if id="$(choose_steam_game)"; then steam_add_game "$id" true || warn "Unable to update Steam game $id."; fi
                pause ;;
            5)
                if id="$(choose_managed_steam)"; then steam_remove_game "$id" true || warn "Unable to restore Steam game $id."; fi
                pause ;;
            6)
                if [[ "$STEAM_ALL" == 1 ]]; then steam_disable_all true || warn "Unable to restore all Steam launch options."
                else steam_enable_all true || warn "Unable to configure all Steam games."
                fi
                pause ;;
            7)
                apply_saved_desktop_apps || warn "One or more Desktop applications could not be reapplied."
                apply_saved_steam_apps || warn "One or more Steam applications could not be reapplied."
                pause ;;
            8) list_managed; pause ;;
            9) doctor; pause ;;
            10) smoke_test || warn "GPU smoke test failed."; pause ;;
            11) uninstall_core || warn "Uninstall was not completed."; pause ;;
            0) return 0 ;;
        esac
    done
}
usage() {
    cat <<EOF2
Huawei MateBook 13 GPU Manager $VERSION

Usage:
  $0 [--lang en|fr] [--yes] [--no-driver-install] install
  $0 [--lang en|fr] add [APP.desktop]
  $0 [--lang en|fr] remove [APP.desktop]
  $0 steam-add [APPID]
  $0 steam-remove APPID
  $0 steam-all-on
  $0 steam-all-off
  $0 apply
  $0 list
  $0 status
  $0 doctor
  $0 test
  $0 run -- COMMAND [ARGS...]
  $0 uninstall
  $0                 # interactive menu

Upgrade behavior:
  install/repair/upgrade automatically imports supported v1/v2 state and
  converges it transactionally to the current schema before removing legacy
  infrastructure. A newer unknown install schema is never downgraded.

Safety:
  --no-driver-install   require an already installed proprietary NVIDIA R580 driver.
  --force-unsupported   bypasses the Huawei DMI check only; the MX250 PCI ID
                        is still required. Use only for deliberate testing.
EOF2
}

# Source-only mode is used by the regression suite; no CLI dispatch or system mutation.
if [[ "${HUAWEI_GPU_LIB_ONLY:-0}" == 1 ]]; then
    return 0 2>/dev/null || exit 0
fi

# Parse global flags before command.
args=()
while (($#)); do
    case "$1" in
        --lang) LANG_CHOICE="${2:-}"; shift 2 ;;
        --lang=*) LANG_CHOICE="${1#*=}"; shift ;;
        --yes|-y) AUTO_YES=1; shift ;;
        --no-driver-install|--driver-preinstalled) NO_DRIVER_INSTALL=1; shift ;;
        --force-unsupported) FORCE_UNSUPPORTED=1; shift ;;
        --) args+=("$1"); shift; args+=("$@"); break ;;
        *) args+=("$1"); shift ;;
    esac
done
set -- "${args[@]}"
[[ "$LANG_CHOICE" == "" || "$LANG_CHOICE" == en || "$LANG_CHOICE" == fr ]] || { err "--lang must be en or fr"; exit 2; }
choose_language
ensure_dirs
bootstrap_user_state

cmd="${1:-menu}"
case "$cmd" in
    menu) main_menu ;;
    install|repair|upgrade) install_core ;;
    add) if [[ -n "${2:-}" ]]; then apply_desktop_app "$2" true; else id="$(search_desktop_app)"; apply_desktop_app "$id" true; fi ;;
    remove) if [[ -n "${2:-}" ]]; then remove_desktop_app "$2"; else id="$(choose_managed_desktop)"; remove_desktop_app "$id"; fi ;;
    steam-add) id="${2:-}"; [[ -n "$id" ]] || id="$(choose_steam_game)"; steam_add_game "$id" true ;;
    steam-remove) [[ -n "${2:-}" ]] || { err "APPID required"; exit 2; }; steam_remove_game "$2" true ;;
    steam-all-on) steam_enable_all true ;;
    steam-all-off) steam_disable_all true ;;
    apply) apply_saved_desktop_apps; apply_saved_steam_apps ;;
    list) list_managed ;;
    status) status ;;
    doctor) doctor ;;
    test) smoke_test ;;
    run) shift; [[ "${1:-}" == -- ]] && shift; [[ -x "$RUNNER" ]] || { err "Install first"; exit 1; }; exec "$RUNNER" "$@" ;;
    uninstall) uninstall_core ;;
    help|-h|--help) usage ;;
    *) err "Unknown command: $cmd"; usage; exit 2 ;;
esac
