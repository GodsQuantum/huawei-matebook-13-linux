#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FP_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd -- "$FP_DIR/.." && pwd)"

DO_BUILD=1

usage() {
  cat <<'EOF'
Usage: verify-software-baseline.sh [--no-build]

Runs all safe software-only GXFP51A0 validation gates.
Default behavior also builds the candidate against libfprint v1.94.100.

No sensor SPI transfer, GPIO write, MMIO write or firmware action is performed.
EOF
}

while (($#)); do
  case "$1" in
    --no-build) DO_BUILD=0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR=UNKNOWN_ARGUMENT:$1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

echo "========================================================================"
echo " GXFP51A0 — ONE-SHOT SOFTWARE BASELINE VERIFICATION"
echo "========================================================================"

echo ""
echo "===== 1. SHELL SYNTAX ====="
while IFS= read -r -d '' script; do
  bash -n "$script"
done < <(find "$SCRIPT_DIR" "$FP_DIR/research" -type f -name '*.sh' -print0)
echo "BASH_SYNTAX=PASS"

echo ""
echo "===== 2. FIRST-CONTACT SOURCE REGRESSION ====="
python3 "$REPO_ROOT/tests/test-goodix51a0-first-contact.py"
echo "FIRST_CONTACT_SOURCE_TEST=PASS"

echo ""
echo "===== 3. RESEARCH UNIT / SAFETY SUITE ====="
make -C "$FP_DIR/research" test
echo "RESEARCH_TESTS=PASS"

echo ""
echo "===== 4. DRIVER SOURCE MANIFEST ====="
(
  cd "$FP_DIR/driver/goodix51a0"
  sha256sum -c SOURCE_MANIFEST.sha256
)
echo "SOURCE_MANIFEST=PASS"

if ((DO_BUILD)); then
  echo ""
  echo "===== 5. REPRODUCIBLE LIBFPRINT BUILD ====="
  "$SCRIPT_DIR/build-libfprint-v1.94.100.sh"
else
  echo "LIBFPRINT_BUILD=SKIPPED_BY_USER"
fi

echo ""
echo "========================================================================"
echo " FINAL STATE"
echo "========================================================================"
echo "SOFTWARE_BASELINE=PASS"
echo "ACTIVE_SENSOR_IO=NONE"
echo "GPIO_WRITES=NONE"
echo "MMIO_WRITES=NONE"
echo "FIRMWARE_ACTIONS=NONE"
