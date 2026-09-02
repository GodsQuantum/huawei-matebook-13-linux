#!/bin/bash
set -euo pipefail

CONFIRM_TOKEN='GXFP51A0_REVIEWED_COMMON_INIT_20260902'
DEVICE_NAME='spi-GXFP51A0:00'
DEFAULT_SYSFS_DEVICE='/sys/bus/spi/devices/spi-GXFP51A0:00'
DEFAULT_SPIDEV_DRIVER='/sys/bus/spi/drivers/spidev'
DEFAULT_SPIDEV_MODULE_DIR='/sys/module/spidev'
DEFAULT_TIMEOUT_S=20

if [ "$#" -ne 3 ]; then
    echo "usage: $0 <probe-binary> <restore-binary> <probe-log>" >&2
    exit 64
fi

PROBE_BIN=$1
RESTORE_BIN=$2
PROBE_LOG=$3
TEST_MODE=${GXFP_TEST_MODE:-0}

if [ "${GXFP_LIVE_PROBE_CONFIRM:-}" != "$CONFIRM_TOKEN" ]; then
    echo 'ABORT: live-probe confirmation token missing' >&2
    exit 65
fi

if [ "$TEST_MODE" = 1 ]; then
    SYSFS_DEVICE=${GXFP_TEST_SYSFS_DEVICE:?}
    SPIDEV_DRIVER=${GXFP_TEST_SPIDEV_DRIVER:?}
    SPIDEV_MODULE_DIR=${GXFP_TEST_SPIDEV_MODULE_DIR:?}
    PROBE_TIMEOUT_S=${GXFP_TEST_PROBE_TIMEOUT_S:-1}
else
    SYSFS_DEVICE=$DEFAULT_SYSFS_DEVICE
    SPIDEV_DRIVER=$DEFAULT_SPIDEV_DRIVER
    SPIDEV_MODULE_DIR=$DEFAULT_SPIDEV_MODULE_DIR
    PROBE_TIMEOUT_S=$DEFAULT_TIMEOUT_S
    if [ "${EUID:-$(id -u)}" -ne 0 ]; then
        echo 'ABORT: supervisor must run as root' >&2
        exit 66
    fi
fi

for f in "$PROBE_BIN" "$RESTORE_BIN"; do
    if [ ! -x "$f" ]; then
        echo "ABORT: executable missing: $f" >&2
        exit 67
    fi
done
if [ ! -d "$SYSFS_DEVICE" ] || [ ! -f "$SYSFS_DEVICE/driver_override" ]; then
    echo 'ABORT: target SPI sysfs device missing' >&2
    exit 68
fi
for cmd in timeout setsid; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "ABORT: required command missing: $cmd" >&2
        exit 69
    }
done
if [ "$TEST_MODE" != 1 ]; then
    command -v modprobe >/dev/null 2>&1 || {
        echo 'ABORT: modprobe missing' >&2
        exit 69
    }
fi

mkdir -p -- "$(dirname -- "$PROBE_LOG")"
: > "$PROBE_LOG"

bound_by_wrapper=0
override_touched=0
module_loaded_by_wrapper=0
probe_started=0
cleanup_confirmed=0
restore_failed=0
unbind_failed=0
supervised_pid=0

run_modprobe() {
    if [ "$TEST_MODE" = 1 ]; then
        if [ -z "${GXFP_TEST_MODPROBE:-}" ] || [ ! -x "$GXFP_TEST_MODPROBE" ]; then
            echo 'ABORT: test modprobe hook missing' >&2
            return 1
        fi
        "$GXFP_TEST_MODPROBE" "$@"
    else
        modprobe "$@"
    fi
}

terminate_supervised() {
    local i

    if [ "$supervised_pid" -le 0 ]; then
        return
    fi

    if kill -0 -- "-$supervised_pid" 2>/dev/null; then
        kill -TERM -- "-$supervised_pid" 2>/dev/null || true
        for i in $(seq 1 20); do
            if ! kill -0 -- "-$supervised_pid" 2>/dev/null; then
                break
            fi
            sleep 0.1
        done
        if kill -0 -- "-$supervised_pid" 2>/dev/null; then
            kill -KILL -- "-$supervised_pid" 2>/dev/null || true
        fi
    fi
    wait "$supervised_pid" 2>/dev/null || true
    supervised_pid=0
}

on_signal() {
    local code=$1
    trap - INT TERM
    echo "SUPERVISOR_SIGNAL=$code" >&2
    terminate_supervised
    exit "$code"
}

finalize() {
    local original_rc=$?
    local final_rc=$original_rc
    local restore_rc
    trap - EXIT
    set +e

    terminate_supervised

    if [ "$probe_started" -eq 1 ] && [ "$cleanup_confirmed" -eq 0 ]; then
        echo 'EXTERNAL_RESTORE=BEGIN'
        "$RESTORE_BIN"
        restore_rc=$?
        echo "EXTERNAL_RESTORE_RC=$restore_rc"
        if [ "$restore_rc" -ne 0 ]; then
            restore_failed=1
            final_rc=90
        else
            echo 'EXTERNAL_RESTORE=OK'
        fi
    else
        echo 'EXTERNAL_RESTORE=NOT_NEEDED'
    fi

    if [ "$bound_by_wrapper" -eq 1 ]; then
        if ! printf '%s\n' "$DEVICE_NAME" > "$SPIDEV_DRIVER/unbind"; then
            echo 'SAFETY_FAILURE: spidev unbind failed' >&2
            unbind_failed=1
            if [ "$restore_failed" -eq 0 ]; then
                final_rc=91
            fi
        elif [ "$TEST_MODE" != 1 ] && [ -e "$SYSFS_DEVICE/driver" ]; then
            echo 'SAFETY_FAILURE: target driver still bound after unbind' >&2
            unbind_failed=1
            if [ "$restore_failed" -eq 0 ]; then
                final_rc=91
            fi
        else
            echo 'SPIDEV_UNBIND=OK'
        fi
    fi

    if [ "$override_touched" -eq 1 ]; then
        if ! printf '\n' > "$SYSFS_DEVICE/driver_override" ||
           [ -n "$(cat -- "$SYSFS_DEVICE/driver_override")" ]; then
            echo 'SAFETY_FAILURE: driver_override clear failed' >&2
            if [ "$restore_failed" -eq 0 ] && [ "$unbind_failed" -eq 0 ]; then
                final_rc=92
            fi
        else
            echo 'DRIVER_OVERRIDE_CLEAR=OK'
        fi
    fi

    if [ "$module_loaded_by_wrapper" -eq 1 ]; then
        if run_modprobe -r spidev; then
            echo 'SPIDEV_MODULE_RESTORE=UNLOADED'
        else
            echo 'WARNING: could not restore spidev module to unloaded state' >&2
            if [ "$restore_failed" -eq 0 ] && [ "$unbind_failed" -eq 0 ]; then
                final_rc=93
            fi
        fi
    fi

    echo "SUPERVISOR_FINAL_RC=$final_rc"
    exit "$final_rc"
}
trap finalize EXIT
trap 'on_signal 130' INT
trap 'on_signal 143' TERM

if [ -e "$SYSFS_DEVICE/driver" ]; then
    echo 'ABORT: target SPI device already has a bound driver' >&2
    exit 70
fi
if [ -n "$(cat -- "$SYSFS_DEVICE/driver_override")" ]; then
    echo 'ABORT: target SPI driver_override is not empty' >&2
    exit 73
fi

if [ ! -d "$SPIDEV_MODULE_DIR" ]; then
    run_modprobe spidev
    module_loaded_by_wrapper=1
    echo 'SPIDEV_MODULE_LOAD=OK'
fi

if [ ! -d "$SPIDEV_DRIVER" ] || [ ! -f "$SPIDEV_DRIVER/bind" ] || [ ! -f "$SPIDEV_DRIVER/unbind" ]; then
    echo 'ABORT: spidev sysfs driver missing after module load' >&2
    exit 71
fi

echo 'SUPERVISOR_BEGIN'
echo "DEVICE=$DEVICE_NAME"
echo "PROBE_TIMEOUT_S=$PROBE_TIMEOUT_S"

echo spidev > "$SYSFS_DEVICE/driver_override"
override_touched=1
echo 'DRIVER_OVERRIDE=spidev'

printf '%s\n' "$DEVICE_NAME" > "$SPIDEV_DRIVER/bind"
bound_by_wrapper=1
echo 'SPIDEV_BIND=OK'

if [ "$TEST_MODE" != 1 ]; then
    if [ ! -L "$SYSFS_DEVICE/driver" ] || [ "$(basename -- "$(readlink -f "$SYSFS_DEVICE/driver")")" != spidev ]; then
        echo 'ABORT: spidev bind not reflected by sysfs' >&2
        exit 72
    fi
fi

probe_started=1
set +e
setsid timeout --signal=TERM --kill-after=2s "${PROBE_TIMEOUT_S}s" "$PROBE_BIN" >"$PROBE_LOG" 2>&1 &
supervised_pid=$!
wait "$supervised_pid"
probe_rc=$?
supervised_pid=0
set -e

cat "$PROBE_LOG"
echo "PROBE_EXIT_RC=$probe_rc"

if grep -Fxq 'CLEANUP_RESULT=0' "$PROBE_LOG" &&
   grep -Fxq 'GPIO264_AFTER=0' "$PROBE_LOG"; then
    cleanup_confirmed=1
    echo 'PROBE_CLEANUP_CONFIRMED=YES'
else
    echo 'PROBE_CLEANUP_CONFIRMED=NO'
fi

exit "$probe_rc"
