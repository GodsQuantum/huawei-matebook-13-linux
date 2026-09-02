#!/bin/bash
set -euo pipefail

PIO_CONFIRM_TOKEN='GXFP51A0_REVIEWED_PIO_20260902'
COMMON_INIT_CONFIRM_TOKEN='GXFP51A0_REVIEWED_COMMON_INIT_20260902'

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

TEST_MODE=${GXFP_PIO_TEST_MODE:-0}

if [ "$TEST_MODE" = 1 ]; then
    PREFLIGHT=${GXFP_PIO_PREFLIGHT_BIN:?}
    BASE_SUPERVISOR=${GXFP_PIO_BASE_SUPERVISOR:?}
else
    PREFLIGHT="$HERE/pio_preflight.sh"
    BASE_SUPERVISOR="$HERE/live_probe_supervisor.sh"

    if [ "${EUID:-$(id -u)}" -ne 0 ]; then
        echo 'ABORT: PIO supervisor must run as root' >&2
        exit 66
    fi
fi

if [ "$#" -ne 3 ]; then
    echo "usage: $0 <probe-binary> <restore-binary> <probe-log>" >&2
    exit 64
fi

if [ "${GXFP_PIO_LIVE_CONFIRM:-}" != "$PIO_CONFIRM_TOKEN" ]; then
    echo 'ABORT: PIO live-probe confirmation token missing' >&2
    exit 65
fi

[ -x "$PREFLIGHT" ] || {
    echo 'ABORT: PIO preflight executable missing' >&2
    exit 67
}

[ -x "$BASE_SUPERVISOR" ] || {
    echo 'ABORT: base live supervisor executable missing' >&2
    exit 68
}

"$PREFLIGHT"

echo 'PIO_GATE=PASS'
echo 'PIO_EXPERIMENT_VARIABLE=CONTROLLER_DATAPATH_ONLY'
echo 'PIO_PROTOCOL_MODEL=UNCHANGED_WINDOWS_FAITHFUL_COMMON_INIT'

export GXFP_LIVE_PROBE_CONFIRM="$COMMON_INIT_CONFIRM_TOKEN"

exec "$BASE_SUPERVISOR" "$1" "$2" "$3"
