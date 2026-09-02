#!/bin/sh
set -eu

research_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
base_tmp=${TMPDIR:-/tmp}
case_dir="$base_tmp/gxfp make path with spaces $$"
build_dir="$case_dir/build output"
trap 'rm -rf -- "$case_dir"' EXIT HUP INT TERM
mkdir -p -- "$case_dir"

make -s -C "$research_dir" BUILD_DIR="$build_dir" test_irq_logic >/dev/null

test -x "$build_dir/test_irq_logic"
echo "test_makefile_space_build_dir: OK"
