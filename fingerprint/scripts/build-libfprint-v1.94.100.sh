#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FP_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd -- "$FP_DIR/.." && pwd)"
DRIVER_DIR="$FP_DIR/driver/goodix51a0"

LIBFPRINT_TAG="v1.94.100"
MESON_VERSION="1.12.0"
NINJA_VERSION="1.13.2"

BUILD_ROOT="${GXFP51A0_BUILD_ROOT:-$REPO_ROOT/../temp/gxfp51a0-public-build}"
TOOLS_VENV="$BUILD_ROOT/build-tools-venv"
SRC_DIR="$BUILD_ROOT/libfprint-$LIBFPRINT_TAG"
BUILD_DIR="$BUILD_ROOT/libfprint-build"

KEEP_BUILD=1
CLEAN_FIRST=1

usage() {
  cat <<'EOF'
Usage: build-libfprint-v1.94.100.sh [--no-clean] [--clean-after]

Builds the public GXFP51A0 candidate against libfprint v1.94.100.
This script performs no fingerprint hardware I/O, no GPIO writes and no
firmware operation.

Environment:
  GXFP51A0_BUILD_ROOT  Override the build workspace. By default it is created
                       outside the repository under ../temp/.
EOF
}

while (($#)); do
  case "$1" in
    --no-clean) CLEAN_FIRST=0 ;;
    --clean-after) KEEP_BUILD=0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR=UNKNOWN_ARGUMENT:$1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

say() { printf '%s\n' "$*"; }
die() { say "ERROR=$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "MISSING_COMMAND:$1"
}

say "========================================================================"
say " GXFP51A0 — REPRODUCIBLE LIBFPRINT BUILD"
say " NO SENSOR I/O / NO GPIO WRITE / NO FIRMWARE ACTION"
say "========================================================================"

for cmd in git python3 cc pkg-config sha256sum nm strings ar; do
  require_cmd "$cmd"
done

[[ -d "$DRIVER_DIR" ]] || die "DRIVER_DIRECTORY_NOT_FOUND:$DRIVER_DIR"
[[ -f "$DRIVER_DIR/libfprint-v1.94.100.patch" ]] || die "INTEGRATION_PATCH_MISSING"
[[ -f "$DRIVER_DIR/SOURCE_MANIFEST.sha256" ]] || die "SOURCE_MANIFEST_MISSING"

say "REPO_ROOT=$REPO_ROOT"
say "BUILD_ROOT=$BUILD_ROOT"
say "LIBFPRINT_TAG=$LIBFPRINT_TAG"
say "MESON_VERSION=$MESON_VERSION"
say "NINJA_VERSION=$NINJA_VERSION"

mkdir -p "$BUILD_ROOT"

if ((CLEAN_FIRST)); then
  rm -rf -- "$SRC_DIR" "$BUILD_DIR"
fi

say ""
say "===== 1. SOURCE MANIFEST ====="
(
  cd "$DRIVER_DIR"
  sha256sum -c SOURCE_MANIFEST.sha256
)
say "SOURCE_MANIFEST=PASS"

say ""
say "===== 2. BUILD DEPENDENCIES ====="
required_pc=(
  glib-2.0
  gio-unix-2.0
  gobject-2.0
  gmodule-2.0
  gusb
  cairo
  gudev-1.0
  openssl
  udev
)
missing=()
for dep in "${required_pc[@]}"; do
  if ! pkg-config --exists "$dep"; then
    missing+=("$dep")
  fi
done
if ((${#missing[@]})); then
  printf 'MISSING_PKG_CONFIG_DEPENDENCIES=%s\n' "${missing[*]}" >&2
  cat >&2 <<'EOF'
Install the development packages for the missing pkg-config modules.
Typical Debian/Ubuntu packages:
  build-essential git python3 python3-venv pkg-config
  libglib2.0-dev libgusb-dev libcairo2-dev libgudev-1.0-dev
  libssl-dev libudev-dev
EOF
  exit 3
fi
say "PKG_CONFIG_DEPENDENCIES=PASS"

say ""
say "===== 3. PINNED MESON / NINJA TOOL ENV ====="
if [[ ! -x "$TOOLS_VENV/bin/python3" ]]; then
  rm -rf -- "$TOOLS_VENV"
  python3 -m venv "$TOOLS_VENV"
fi
"$TOOLS_VENV/bin/python3" -m pip install \
  --disable-pip-version-check --no-input \
  "meson==$MESON_VERSION" "ninja==$NINJA_VERSION"

MESON="$TOOLS_VENV/bin/meson"
NINJA="$TOOLS_VENV/bin/ninja"
export PATH="$TOOLS_VENV/bin:$PATH"
export NINJA

say "MESON=$("$MESON" --version)"
say "NINJA=$("$NINJA" --version)"
say "BUILD_TOOLS=PASS"

say ""
say "===== 4. FETCH EXACT LIBFPRINT TAG ====="
git clone --depth 1 --branch "$LIBFPRINT_TAG" \
  https://gitlab.freedesktop.org/libfprint/libfprint.git "$SRC_DIR"

actual_tag="$(git -C "$SRC_DIR" describe --tags --exact-match HEAD 2>/dev/null || true)"
[[ "$actual_tag" == "$LIBFPRINT_TAG" ]] || die "LIBFPRINT_TAG_MISMATCH:$actual_tag"
say "LIBFPRINT_SOURCE_TAG=$actual_tag"

say ""
say "===== 5. APPLY INTEGRATION PATCH ====="
git -C "$SRC_DIR" apply --check "$DRIVER_DIR/libfprint-v1.94.100.patch"
git -C "$SRC_DIR" apply "$DRIVER_DIR/libfprint-v1.94.100.patch"
say "LIBFPRINT_PATCH=PASS"

say ""
say "===== 6. INJECT REVIEWED CANDIDATE SOURCES ====="
target="$SRC_DIR/libfprint/drivers/goodix51a0"
mkdir -p "$target"

sources=(
  goodix51a0.c
  goodix51a0.h
  goodix_tls.c
  goodix_tls.h
  goodix_sift.c
  goodix_sift.h
  gx51_transport.c
  gx51_transport.h
)
for file in "${sources[@]}"; do
  [[ -f "$DRIVER_DIR/$file" ]] || die "CANDIDATE_SOURCE_MISSING:$file"
  install -m 0644 "$DRIVER_DIR/$file" "$target/$file"
done
say "CANDIDATE_SOURCE_INJECTION=PASS"

say ""
say "===== 7. MESON CONFIGURE ====="
"$MESON" setup "$BUILD_DIR" "$SRC_DIR" \
  -Ddrivers=goodix51a0 \
  -Dintrospection=false \
  -Ddoc=false \
  -Dinstalled-tests=false
say "MESON_CONFIGURE=PASS"

say ""
say "===== 8. NINJA BUILD ====="
"$NINJA" -C "$BUILD_DIR"
say "LIBFPRINT_BUILD=PASS"

say ""
say "===== 9. ARTIFACT GATES ====="
driver_obj="$(find "$BUILD_DIR/libfprint" -type f -name '*drivers_goodix51a0_goodix51a0.c.o' -print -quit)"
[[ -n "$driver_obj" ]] || die "GOODIX51A0_OBJECT_NOT_FOUND"
archive="$BUILD_DIR/libfprint/libfprint-drivers.a"
[[ -f "$archive" ]] || die "LIBFPRINT_DRIVER_ARCHIVE_NOT_FOUND"

object_nm_dump="$BUILD_ROOT/goodix51a0-object.nm.txt"
object_strings_dump="$BUILD_ROOT/goodix51a0-object.strings.txt"
archive_nm_dump="$BUILD_ROOT/libfprint-drivers.nm.txt"
archive_members_dump="$BUILD_ROOT/libfprint-drivers.members.txt"

# Validate the exact compiled object first. This proves both the GObject type
# and the ACPI target literal survived compilation.
nm "$driver_obj" >"$object_nm_dump"
grep -Fq 'fpi_device_goodix51a0_get_type' "$object_nm_dump" \
  || die "GOODIX51A0_TYPE_SYMBOL_NOT_FOUND_IN_OBJECT"

strings "$driver_obj" >"$object_strings_dump"
grep -Fq 'GXFP51A0' "$object_strings_dump" \
  || die "GOODIX51A0_ACPI_ID_NOT_FOUND_IN_OBJECT"

# Then prove the same driver is integrated into libfprint-drivers.a.
# Do not use strings(1) on the archive itself: archive formats (especially
# thin archives) need not expose member literals to strings.
nm "$archive" >"$archive_nm_dump"
grep -Fq 'fpi_device_goodix51a0_get_type' "$archive_nm_dump" \
  || die "GOODIX51A0_TYPE_SYMBOL_NOT_FOUND_IN_ARCHIVE"

ar t "$archive" >"$archive_members_dump"
grep -Fq 'drivers_goodix51a0_goodix51a0.c.o' "$archive_members_dump" \
  || die "GOODIX51A0_OBJECT_NOT_LISTED_IN_ARCHIVE"

say "GOODIX51A0_OBJECT_COMPILED=YES"
say "GOODIX51A0_TYPE_SYMBOL_IN_OBJECT=YES"
say "GOODIX51A0_ACPI_ID_IN_OBJECT=YES"
say "GOODIX51A0_OBJECT_IN_DRIVER_ARCHIVE=YES"
say "GOODIX51A0_TYPE_SYMBOL_IN_DRIVER_ARCHIVE=YES"
say "SOFTWARE_BUILD_READY=YES"

say ""
say "========================================================================"
say " FINAL STATE"
say "========================================================================"
say "LIBFPRINT_TAG=$LIBFPRINT_TAG"
say "SOURCE_MANIFEST=PASS"
say "LIBFPRINT_PATCH=PASS"
say "MESON_CONFIGURE=PASS"
say "LIBFPRINT_BUILD=PASS"
say "GOODIX51A0_OBJECT_COMPILED=YES"
say "GOODIX51A0_ACPI_ID_IN_OBJECT=YES"
say "GOODIX51A0_OBJECT_IN_DRIVER_ARCHIVE=YES"
say "GOODIX51A0_TYPE_SYMBOL_IN_DRIVER_ARCHIVE=YES"
say "SOFTWARE_BUILD_READY=YES"
say "ACTIVE_SENSOR_IO=NONE"
say "GPIO_WRITES=NONE"
say "MMIO_WRITES=NONE"
say "FIRMWARE_ACTIONS=NONE"
say "BUILD_DIR=$BUILD_DIR"

if ((!KEEP_BUILD)); then
  rm -rf -- "$SRC_DIR" "$BUILD_DIR"
  say "BUILD_ARTIFACTS_REMOVED=YES"
fi
