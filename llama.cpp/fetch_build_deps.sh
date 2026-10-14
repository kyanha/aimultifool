#!/bin/bash

# Fetch the components needed to build the llama-cpp-python wheel, from UPSTREAM sources
# only (no aimultifool.com):
#   - CPython 3.12 build interpreter  <- astral-sh/python-build-standalone GitHub release,
#                                        SHA-256 pinned in ../checksums.sha256 (must MATCH)
#   - llama-cpp-python source          <- abetlen/llama-cpp-python at a tag, with the clone
#                                        required to resolve to a pinned commit
# The Python goes in ../python_portable/ (shared with the run scripts); the source goes
# in ../build_deps/. Both are git-ignored.
#
# Compilers and SDKs (git, CUDA toolkit, gcc/g++) are large and need root, so they are
# CHECKED and the official install hint is printed, not auto-installed.
#
# Exit status: 0 = everything fetched and toolchain present
#              1 = a fetch/verification failed, or the toolchain is incomplete

set -e
set -o pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$HERE/.." && pwd)"
DEPS_DIR="$ROOT_DIR/build_deps"
CHECKSUM_MANIFEST="$ROOT_DIR/checksums.sha256"

PY_TAR="cpython-3.12.12+20260114-x86_64-unknown-linux-gnu-install_only.tar.gz"
PY_URL="https://github.com/astral-sh/python-build-standalone/releases/download/20260114/cpython-3.12.12%2B20260114-x86_64-unknown-linux-gnu-install_only.tar.gz"
# Shared with run_linux_*.sh: same asset, same pinned hash, one copy on disk.
PY_DIR="$ROOT_DIR/python_portable"
PY_TAR_PATH="$PY_DIR/$PY_TAR"

SRC_REPO="https://github.com/abetlen/llama-cpp-python.git"
SRC_TAG="v0.3.16"
SRC_COMMIT="c37132bac860fcc333255c36313f89c4f49d4c8d"
SRC_DIR="$DEPS_DIR/llama-cpp-python"

TOOLCHAIN_MISSING=0

die() {
    echo "[CRITICAL] $*" >&2
    exit 1
}

for helper in verify_hash.sh download_file.sh; do
    [ -f "$ROOT_DIR/$helper" ] || die "Required helper script missing: $ROOT_DIR/$helper"
    # shellcheck source=/dev/null
    source "$ROOT_DIR/$helper" || die "Failed to load helper script: $helper"
done
[ -f "$CHECKSUM_MANIFEST" ] || die "Checksum manifest missing: $CHECKSUM_MANIFEST"

echo "----------------------------------------------------------------"
echo "  aiMultiFool - fetch wheel build components (upstream sources)"
echo "----------------------------------------------------------------"

mkdir -p "$DEPS_DIR" || die "Could not create directory: $DEPS_DIR"

# ---------------------------------------------------------------- 1. build Python
echo ""
echo "[1/3] Build Python (python-build-standalone, pinned hash)"
if [ -x "$PY_DIR/bin/python3" ] && "$PY_DIR/bin/python3" --version &> /dev/null; then
    echo "[FOUND] Build Python already present."
else
    if [ -e "$PY_DIR" ]; then
        echo "[WARNING] Existing build Python does not run; re-fetching."
        rm -rf "$PY_DIR"
        [ ! -e "$PY_DIR" ] || die "Could not remove broken build Python directory."
    fi

    mkdir -p "$PY_DIR" || die "Could not create directory: $PY_DIR"

    # A cached tarball is only trusted if it matches the pin; anything else is discarded.
    if [ -f "$PY_TAR_PATH" ]; then
        verify_artifact "$PY_TAR_PATH" "$PY_TAR" "$CHECKSUM_MANIFEST"
        if [ "$VERIFY_RESULT" != "MATCH" ]; then
            echo "[SECURITY] Cached tarball did not verify ($VERIFY_RESULT); discarding."
            rm -f "$PY_TAR_PATH" || die "Could not remove unverified cached tarball."
        fi
    fi

    if [ ! -f "$PY_TAR_PATH" ]; then
        echo "[NETWORK] Downloading $PY_TAR"
        echo "[SOURCE]  $PY_URL"
        download_with_fallback "$PY_URL" "$PY_TAR_PATH" || die "Download failed with all available mechanisms (wget/curl/python3)."
        [ -f "$PY_TAR_PATH" ] || die "Download reported success but the file disappeared - likely removed by antivirus. Not retrying."
    fi

    # Fail closed: the build interpreter must MATCH its pinned hash. UNVERIFIED is not enough.
    verify_artifact "$PY_TAR_PATH" "$PY_TAR" "$CHECKSUM_MANIFEST"
    if [ "$VERIFY_RESULT" != "MATCH" ]; then
        rm -f "$PY_TAR_PATH" || true
        die "Build Python tarball did not match its pinned SHA-256 (result: $VERIFY_RESULT). Discarded."
    fi
    echo "[SECURITY] Hash verified."

    echo "[EXTRACT] Extracting build Python..."
    if ! tar -xzf "$PY_TAR_PATH" -C "$PY_DIR" --strip-components=1; then
        rm -rf "$PY_DIR"
        die "Extraction of build Python failed."
    fi
    if ! "$PY_DIR/bin/python3" --version; then
        rm -rf "$PY_DIR"
        die "Extracted build Python does not run."
    fi
fi

# ---------------------------------------------------------------- 2. source
echo ""
echo "[2/3] llama-cpp-python source $SRC_TAG (pinned commit)"
if ! command -v git &> /dev/null; then
    echo "[MISSING] git - cannot fetch source."
    TOOLCHAIN_MISSING=1
elif [ -d "$SRC_DIR/.git" ]; then
    ACTUAL_COMMIT=$(git -C "$SRC_DIR" rev-parse HEAD 2>/dev/null) || ACTUAL_COMMIT=""
    [ -n "$ACTUAL_COMMIT" ] || die "Existing source directory is not a readable git checkout. Delete $SRC_DIR and re-run."
    [ "$ACTUAL_COMMIT" = "$SRC_COMMIT" ] || die "Existing source is at $ACTUAL_COMMIT, not the pinned $SRC_COMMIT. Delete $SRC_DIR and re-run."
    echo "[FOUND] Source already at pinned commit; making sure submodules are present..."
    git -C "$SRC_DIR" submodule update --init --recursive || die "git submodule update failed."
else
    [ ! -e "$SRC_DIR" ] || die "$SRC_DIR exists but is not a git checkout. Delete it and re-run."
    echo "[NETWORK] Cloning $SRC_REPO at $SRC_TAG (with submodules)..."
    if ! git clone --branch "$SRC_TAG" --recurse-submodules --shallow-submodules --depth 1 "$SRC_REPO" "$SRC_DIR"; then
        rm -rf "$SRC_DIR"
        die "git clone failed."
    fi
    # The tag name is not trusted on its own - the commit it resolves to must match the pin.
    ACTUAL_COMMIT=$(git -C "$SRC_DIR" rev-parse HEAD 2>/dev/null) || ACTUAL_COMMIT=""
    if [ -z "$ACTUAL_COMMIT" ]; then
        rm -rf "$SRC_DIR"
        die "Could not read the commit of the fresh clone. Discarded."
    fi
    if [ "$ACTUAL_COMMIT" != "$SRC_COMMIT" ]; then
        rm -rf "$SRC_DIR"
        die "Tag $SRC_TAG resolved to $ACTUAL_COMMIT, expected $SRC_COMMIT. Clone discarded."
    fi
    echo "[SECURITY] Source commit verified: $ACTUAL_COMMIT"
fi

# ---------------------------------------------------------------- 3. toolchain check
echo ""
echo "[3/3] Toolchain check (not auto-installed: large, needs root)"

check_tool() {
    local cmd="$1" label="$2" hint="$3"
    if command -v "$cmd" &> /dev/null; then
        echo "[OK]      $label"
    else
        echo "[MISSING] $label"
        echo "          $hint"
        TOOLCHAIN_MISSING=1
    fi
}

check_tool git  "git"                 "sudo apt install git"
check_tool nvcc "CUDA toolkit (nvcc)" "sudo apt install nvidia-cuda-toolkit   (or the NVIDIA CUDA repo for a newer release)"
check_tool gcc  "gcc"                 "sudo apt install build-essential"
check_tool g++  "g++"                 "sudo apt install build-essential"

echo ""
echo "CMake and Ninja are installed automatically by the build (PyPI build requirements)."

if [ "$TOOLCHAIN_MISSING" -eq 1 ]; then
    echo ""
    echo "[INCOMPLETE] Downloads are done, but the toolchain above is incomplete."
    exit 1
fi

echo ""
echo "[DONE] Build components are ready in: $DEPS_DIR"
echo "       Source : $SRC_DIR"
echo "       Python : $PY_DIR/bin/python3"
