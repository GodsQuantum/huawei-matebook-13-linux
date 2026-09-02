#!/bin/bash
set -euo pipefail

research_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
supervisor="$research_dir/linux/live_probe_supervisor.sh"
grep -q "CONFIRM_TOKEN='GXFP51A0_REVIEWED_COMMON_INIT_20260902'" "$supervisor"
grep -q 'DEFAULT_TIMEOUT_S=20' "$supervisor"
base_tmp=${TMPDIR:-/tmp}
case_dir="$base_tmp/gxfp-supervisor-test-$$"
trap 'rm -rf -- "$case_dir"' EXIT HUP INT TERM
mkdir -p "$case_dir"

run_case() {
    local name=$1
    local probe_mode=$2
    local restore_rc=$3
    local expected_rc=$4
    local expected_restore_calls=$5
    local root="$case_dir/$name"
    local sysdev="$root/sys/device"
    local driver="$root/sys/driver"
    local module="$root/sys/module/spidev"
    local bin="$root/bin"
    local probe_log="$root/probe.log"
    local restore_log="$root/restore.log"
    local out="$root/out.log"
    local rc

    mkdir -p "$sysdev" "$driver" "$module" "$bin"
    : > "$sysdev/driver_override"
    : > "$driver/bind"
    : > "$driver/unbind"
    : > "$restore_log"

    cat > "$bin/probe" <<PROBE
#!/bin/bash
set -euo pipefail
case '$probe_mode' in
  clean)
    echo 'PROBE_BEGIN'
    echo 'CLEANUP_RESULT=0'
    echo 'GPIO264_AFTER=0'
    exit 3
    ;;
  crash)
    echo 'PROBE_BEGIN'
    exit 77
    ;;
  timeout)
    echo 'PROBE_BEGIN'
    sleep 5
    ;;
esac
PROBE
    chmod +x "$bin/probe"

    cat > "$bin/restore" <<RESTORE
#!/bin/bash
set -euo pipefail
echo call >> '$restore_log'
echo 'EXTERNAL_RESET_RESULT=$restore_rc'
exit '$restore_rc'
RESTORE
    chmod +x "$bin/restore"

    set +e
    GXFP_TEST_MODE=1 \
    GXFP_TEST_SYSFS_DEVICE="$sysdev" \
    GXFP_TEST_SPIDEV_DRIVER="$driver" \
    GXFP_TEST_SPIDEV_MODULE_DIR="$module" \
    GXFP_TEST_PROBE_TIMEOUT_S=1 \
    GXFP_LIVE_PROBE_CONFIRM='GXFP51A0_REVIEWED_COMMON_INIT_20260902' \
    "$supervisor" "$bin/probe" "$bin/restore" "$probe_log" >"$out" 2>&1
    rc=$?
    set -e

    if [ "$rc" -ne "$expected_rc" ]; then
        echo "$name: rc=$rc expected=$expected_rc" >&2
        cat "$out" >&2
        return 1
    fi

    test "$(wc -l < "$restore_log")" -eq "$expected_restore_calls"
    test "$(cat "$sysdev/driver_override")" = ''
    grep -q '^spi-GXFP51A0:00$' "$driver/unbind"
}

run_case clean clean 0 3 0
run_case crash crash 0 77 1
run_case timeout timeout 0 124 1
run_case restore_failure crash 9 90 1

run_interrupt_case() {
    local root="$case_dir/interrupt"
    local sysdev="$root/sys/device"
    local driver="$root/sys/driver"
    local module="$root/sys/module/spidev"
    local bin="$root/bin"
    local probe_log="$root/probe.log"
    local restore_log="$root/restore.log"
    local probe_pid_file="$root/probe.pid"
    local out="$root/out.log"
    local supervisor_pid rc i

    mkdir -p "$sysdev" "$driver" "$module" "$bin"
    : > "$sysdev/driver_override"
    : > "$driver/bind"
    : > "$driver/unbind"
    : > "$restore_log"

    cat > "$bin/probe" <<PROBE
#!/bin/bash
set -euo pipefail
echo \$\$ > '$probe_pid_file'
trap '' TERM INT
sleep 5
PROBE
    chmod +x "$bin/probe"

    cat > "$bin/restore" <<RESTORE
#!/bin/bash
set -euo pipefail
echo call >> '$restore_log'
if [ -s '$probe_pid_file' ] && kill -0 \"\$(cat '$probe_pid_file')\" 2>/dev/null; then
    echo 'restore saw live probe' >&2
    exit 9
fi
exit 0
RESTORE
    chmod +x "$bin/restore"

    set +e
    GXFP_TEST_MODE=1 \
    GXFP_TEST_SYSFS_DEVICE="$sysdev" \
    GXFP_TEST_SPIDEV_DRIVER="$driver" \
    GXFP_TEST_SPIDEV_MODULE_DIR="$module" \
    GXFP_TEST_PROBE_TIMEOUT_S=10 \
    GXFP_LIVE_PROBE_CONFIRM='GXFP51A0_REVIEWED_COMMON_INIT_20260902' \
    "$supervisor" "$bin/probe" "$bin/restore" "$probe_log" >"$out" 2>&1 &
    supervisor_pid=$!
    set -e

    for i in $(seq 1 30); do
        [ -s "$probe_pid_file" ] && break
        sleep 0.05
    done
    test -s "$probe_pid_file"

    kill -TERM "$supervisor_pid"
    set +e
    wait "$supervisor_pid"
    rc=$?
    set -e

    if [ "$rc" -ne 143 ]; then
        echo "interrupt: rc=$rc expected=143" >&2
        cat "$out" >&2
        return 1
    fi
    test "$(wc -l < "$restore_log")" -eq 1
    test "$(cat "$sysdev/driver_override")" = ''
    grep -q '^spi-GXFP51A0:00$' "$driver/unbind"
}

run_interrupt_case

run_module_load_case() {
    local root="$case_dir/module_load"
    local sysdev="$root/sys/device"
    local driver="$root/sys/driver"
    local module="$root/sys/module/spidev"
    local bin="$root/bin"
    local probe_log="$root/probe.log"
    local modprobe_log="$root/modprobe.log"
    local out="$root/out.log"
    local rc

    mkdir -p "$sysdev" "$bin"
    : > "$sysdev/driver_override"
    : > "$modprobe_log"

    cat > "$bin/probe" <<'PROBE'
#!/bin/bash
set -euo pipefail
echo 'CLEANUP_RESULT=0'
echo 'GPIO264_AFTER=0'
exit 3
PROBE
    chmod +x "$bin/probe"

    cat > "$bin/restore" <<'RESTORE'
#!/bin/bash
exit 0
RESTORE
    chmod +x "$bin/restore"

    cat > "$bin/modprobe" <<MODPROBE
#!/bin/bash
set -euo pipefail
echo "\$*" >> '$modprobe_log'
if [ "\${1:-}" = '-r' ]; then
    rm -rf '$module'
    exit 0
fi
mkdir -p '$module' '$driver'
: > '$driver/bind'
: > '$driver/unbind'
MODPROBE
    chmod +x "$bin/modprobe"

    set +e
    GXFP_TEST_MODE=1 \
    GXFP_TEST_SYSFS_DEVICE="$sysdev" \
    GXFP_TEST_SPIDEV_DRIVER="$driver" \
    GXFP_TEST_SPIDEV_MODULE_DIR="$module" \
    GXFP_TEST_MODPROBE="$bin/modprobe" \
    GXFP_TEST_PROBE_TIMEOUT_S=1 \
    GXFP_LIVE_PROBE_CONFIRM='GXFP51A0_REVIEWED_COMMON_INIT_20260902' \
    "$supervisor" "$bin/probe" "$bin/restore" "$probe_log" >"$out" 2>&1
    rc=$?
    set -e

    if [ "$rc" -ne 3 ]; then
        echo "module_load: rc=$rc expected=3" >&2
        cat "$out" >&2
        return 1
    fi
    grep -Fxq 'spidev' "$modprobe_log"
    grep -Fxq -- '-r spidev' "$modprobe_log"
    test ! -d "$module"
}

run_module_load_case

echo 'test_live_probe_supervisor: OK'
