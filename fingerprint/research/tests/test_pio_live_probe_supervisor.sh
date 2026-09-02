#!/bin/bash
set -euo pipefail

research_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
wrapper="$research_dir/linux/pio_live_probe_supervisor.sh"

base_tmp=${TMPDIR:-/tmp}
case_dir="$base_tmp/gxfp-pio-live-supervisor-test-$$"
trap 'rm -rf -- "$case_dir"' EXIT HUP INT TERM

mkdir -p "$case_dir/bin"

preflight_log="$case_dir/preflight.log"
base_log="$case_dir/base.log"
: >"$preflight_log"
: >"$base_log"

cat >"$case_dir/bin/preflight-ok" <<PREFLIGHT
#!/bin/bash
echo called >> '$preflight_log'
echo 'PIO_PREFLIGHT=PASS'
exit 0
PREFLIGHT
chmod +x "$case_dir/bin/preflight-ok"

cat >"$case_dir/bin/preflight-fail" <<PREFLIGHT
#!/bin/bash
echo called >> '$preflight_log'
echo 'ABORT=PIO_NOT_PROVEN'
exit 77
PREFLIGHT
chmod +x "$case_dir/bin/preflight-fail"

cat >"$case_dir/bin/base" <<BASE
#!/bin/bash
set -euo pipefail
echo "confirm=\${GXFP_LIVE_PROBE_CONFIRM:-}" >> '$base_log'
echo "args=\$*" >> '$base_log'
exit 3
BASE
chmod +x "$case_dir/bin/base"

: >"$case_dir/probe"
: >"$case_dir/restore"
chmod +x "$case_dir/probe" "$case_dir/restore"

set +e
GXFP_PIO_TEST_MODE=1 \
GXFP_PIO_PREFLIGHT_BIN="$case_dir/bin/preflight-ok" \
GXFP_PIO_BASE_SUPERVISOR="$case_dir/bin/base" \
GXFP_PIO_LIVE_CONFIRM='GXFP51A0_REVIEWED_PIO_20260902' \
"$wrapper" \
    "$case_dir/probe" \
    "$case_dir/restore" \
    "$case_dir/probe.log" \
    >"$case_dir/pass.out" 2>&1
rc=$?
set -e

test "$rc" -eq 3
grep -Fxq 'PIO_GATE=PASS' "$case_dir/pass.out"
grep -Fxq 'confirm=GXFP51A0_REVIEWED_COMMON_INIT_20260902' "$base_log"
grep -Fq "$case_dir/probe $case_dir/restore $case_dir/probe.log" "$base_log"

: >"$base_log"
: >"$preflight_log"

set +e
GXFP_PIO_TEST_MODE=1 \
GXFP_PIO_PREFLIGHT_BIN="$case_dir/bin/preflight-fail" \
GXFP_PIO_BASE_SUPERVISOR="$case_dir/bin/base" \
GXFP_PIO_LIVE_CONFIRM='GXFP51A0_REVIEWED_PIO_20260902' \
"$wrapper" \
    "$case_dir/probe" \
    "$case_dir/restore" \
    "$case_dir/probe.log" \
    >"$case_dir/fail.out" 2>&1
rc=$?
set -e

test "$rc" -eq 77
test ! -s "$base_log"

set +e
GXFP_PIO_TEST_MODE=1 \
GXFP_PIO_PREFLIGHT_BIN="$case_dir/bin/preflight-ok" \
GXFP_PIO_BASE_SUPERVISOR="$case_dir/bin/base" \
GXFP_PIO_LIVE_CONFIRM='WRONG_TOKEN' \
"$wrapper" \
    "$case_dir/probe" \
    "$case_dir/restore" \
    "$case_dir/probe.log" \
    >"$case_dir/token.out" 2>&1
rc=$?
set -e

test "$rc" -eq 65
grep -Fq 'ABORT: PIO live-probe confirmation token missing' "$case_dir/token.out"

echo 'test_pio_live_probe_supervisor: OK'
