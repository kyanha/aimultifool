#!/bin/bash

# Setup script for aiMultiFool console chat app (CPU-only mode)

# set -e is a backstop only; every step that can fail is also checked explicitly below so
# the user gets a message saying WHICH step was rejected, not just a silent exit.
set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$SCRIPT_DIR/venv_cpu"
VENV_PY="$VENV_DIR/bin/python"
PYTHON_PORTABLE_DIR="$SCRIPT_DIR/python_portable"
PYTHON_PORTABLE_TAR="cpython-3.12.12+20260114-x86_64-unknown-linux-gnu-install_only.tar.gz"
PYTHON_PORTABLE_URL="https://aimultifool.com/$PYTHON_PORTABLE_TAR"
PYTHON_PORTABLE_TAR_PATH="$PYTHON_PORTABLE_DIR/$PYTHON_PORTABLE_TAR"
PYTHON_CMD="python3"
CHECKSUM_MANIFEST="$SCRIPT_DIR/checksums.sha256"

die() {
    echo "[CRITICAL] $*" >&2
    exit 1
}

# A half-built venv is worse than none: the next run would see it, offer to skip setup,
# and launch the app without its dependencies. Remove it so the next run starts clean.
setup_failed() {
    echo "[CRITICAL] $*" >&2
    echo "[CLEANUP] Removing incomplete virtual environment so the next run starts clean." >&2
    rm -rf "$VENV_DIR"
    exit 1
}

# Run the app and hand its exit status back to our caller instead of swallowing it.
run_app() {
    local rc=0
    "$VENV_PY" "$SCRIPT_DIR/aimultifool.py" --cpu || rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "[ERROR] aiMultiFool exited with status $rc." >&2
    fi
    exit "$rc"
}

for helper in verify_hash.sh download_file.sh; do
    [ -f "$SCRIPT_DIR/$helper" ] || die "Required helper script missing: $SCRIPT_DIR/$helper"
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/$helper" || die "Failed to load helper script: $helper"
done

echo "----------------------------------------------------------------"
echo "  aiMultiFool Suite - CPU-Only Setup & Launch Script v0.1.9"
echo "----------------------------------------------------------------"

# 0. Setup Portable Python
if [ ! -f "$PYTHON_PORTABLE_DIR/bin/python3" ]; then
    echo "[PYTHON] Portable Python not found. Setting up..."

    # Create python_portable directory
    mkdir -p "$PYTHON_PORTABLE_DIR" || die "Could not create directory: $PYTHON_PORTABLE_DIR"

    # If a cached tarball exists, verify it before trusting it. A mismatch here means the
    # cache is bad (corrupted or tampered) - remove it and fall through to a fresh download.
    if [ -f "$PYTHON_PORTABLE_TAR_PATH" ]; then
        verify_artifact "$PYTHON_PORTABLE_TAR_PATH" "$PYTHON_PORTABLE_TAR" "$CHECKSUM_MANIFEST"
        case "$VERIFY_RESULT" in
            MATCH) ;;
            MISMATCH)
                echo "[SECURITY] Cached $PYTHON_PORTABLE_TAR failed hash verification."
                if rm -f "$PYTHON_PORTABLE_TAR_PATH"; then
                    echo "[SECURITY] Removed bad cached file; will re-download."
                else
                    die "Could not remove bad cached file. Aborting."
                fi
                ;;
            UNVERIFIED)
                echo "[WARNING] No pinned hash for $PYTHON_PORTABLE_TAR; skipping integrity check."
                ;;
            *)
                die "Could not run hash verification on cached $PYTHON_PORTABLE_TAR. Aborting."
                ;;
        esac
    fi

    # Download portable Python if tar doesn't exist
    if [ ! -f "$PYTHON_PORTABLE_TAR_PATH" ]; then
        echo "[NETWORK] Downloading portable Python 3.12 (~50MB)..."
        echo "[SOURCE]  $PYTHON_PORTABLE_URL"

        if ! download_with_fallback "$PYTHON_PORTABLE_URL" "$PYTHON_PORTABLE_TAR_PATH"; then
            echo "[ERROR] Download failed with all available mechanisms (wget/curl/python3)."
            echo "[FALLBACK] Will use system Python instead."
        fi

        # A freshly downloaded file that fails verification is not recoverable by retrying -
        # abort rather than loop.
        if [ -f "$PYTHON_PORTABLE_TAR_PATH" ]; then
            verify_artifact "$PYTHON_PORTABLE_TAR_PATH" "$PYTHON_PORTABLE_TAR" "$CHECKSUM_MANIFEST"
            case "$VERIFY_RESULT" in
                MATCH) echo "[SECURITY] Hash verified." ;;
                UNVERIFIED) echo "[WARNING] No pinned hash for $PYTHON_PORTABLE_TAR; skipping integrity check." ;;
                MISMATCH)
                    rm -f "$PYTHON_PORTABLE_TAR_PATH" || true
                    die "Downloaded $PYTHON_PORTABLE_TAR failed hash verification. Aborting."
                    ;;
                *)
                    die "Could not run hash verification on downloaded $PYTHON_PORTABLE_TAR. Aborting."
                    ;;
            esac
        fi
    fi

    # Extract portable Python if tar exists
    if [ -f "$PYTHON_PORTABLE_TAR_PATH" ]; then
        echo "[EXTRACT] Extracting portable Python..."
        if tar -xzf "$PYTHON_PORTABLE_TAR_PATH" -C "$PYTHON_PORTABLE_DIR" --strip-components=1; then
            if [ -f "$PYTHON_PORTABLE_DIR/bin/python3" ]; then
                PYTHON_CMD="$PYTHON_PORTABLE_DIR/bin/python3"
                echo "[SUCCESS] Portable Python ready!"
            else
                echo "[WARNING] Extraction completed but bin/python3 not found. Using system Python."
            fi
        else
            echo "[ERROR] Extraction failed. Using system Python instead."
            # Discard the tarball and any partial extraction so the next run starts clean
            # instead of finding a half-extracted tree.
            rm -rf "$PYTHON_PORTABLE_DIR"
        fi
    fi
else
    PYTHON_CMD="$PYTHON_PORTABLE_DIR/bin/python3"
    echo "[PYTHON] Using portable Python: $PYTHON_CMD"
fi

# A marker file exists from venv creation until setup fully succeeds. If it is still
# there, a previous setup was interrupted or failed, so that venv cannot be trusted.
if [ -e "$VENV_DIR/.setup_incomplete" ]; then
    echo "[STATUS] A previous setup did not finish. Discarding that environment."
    rm -rf "$VENV_DIR"
    [ ! -e "$VENV_DIR" ] || die "Could not remove incomplete environment: $VENV_DIR"
fi

# Check if venv already exists
if [ -d "$VENV_DIR" ]; then
    echo "[STATUS] Virtual environment detected."
    echo "[INFO]   It is recommended to reinstall (y) if you just updated to a new version."
    # read returns non-zero on EOF (e.g. piped/non-interactive); treat that as "no".
    read -r -p "Do you want to reinstall the environment? [y/N] (Default: n): " choice || choice="n"
    if [[ "$choice" =~ ^[yY]$ ]]; then
        echo "[ACTION] Reinstalling environment..."
        rm -rf "$VENV_DIR"
        [ ! -e "$VENV_DIR" ] || die "Could not remove existing environment: $VENV_DIR"
    else
        echo "[SKIP] Skipping environment setup."
        [ -f "$VENV_DIR/bin/activate" ] || die "Existing environment is incomplete (no activate script). Re-run and choose 'y' to reinstall."
        # shellcheck source=/dev/null
        source "$VENV_DIR/bin/activate" || die "Failed to activate virtual environment."
        echo "[LAUNCH] Starting aiMultiFool TUI (CPU mode)..."
        echo ""
        run_app
    fi
fi

# The interpreter that will build the venv must actually run. Prefer what we have, but
# if the portable one is broken, try the system one before giving up.
if ! "$PYTHON_CMD" --version &> /dev/null; then
    if [ "$PYTHON_CMD" != "python3" ] && python3 --version &> /dev/null; then
        echo "[WARNING] $PYTHON_CMD is not usable; falling back to system python3."
        PYTHON_CMD="python3"
    else
        die "No usable Python interpreter found ($PYTHON_CMD). Install Python 3.12+ and re-run."
    fi
fi

# Create virtual environment
echo "[STEP 1/3] Creating fresh virtual environment (venv_cpu)..."
"$PYTHON_CMD" -m venv "$VENV_DIR" || setup_failed "Failed to create virtual environment with $PYTHON_CMD."
[ -x "$VENV_PY" ] || setup_failed "Virtual environment was created but $VENV_PY is missing."
# Mark the environment as unfinished until setup succeeds.
touch "$VENV_DIR/.setup_incomplete" || setup_failed "Could not write the setup marker file in the new environment."

# Activate virtual environment
echo "[STEP 2/3] Activating environment..."
# shellcheck source=/dev/null
source "$VENV_DIR/bin/activate" || setup_failed "Failed to activate virtual environment."

# Upgrade pip. A stale pip is survivable, so this is a warning rather than a rejection.
echo "[STEP 3/3] Upgrading pip to latest version..."
"$VENV_PY" -m pip install -q --upgrade pip || echo "[WARNING] pip upgrade failed; continuing with the bundled pip."

# Install llama-cpp-python (CPU-only, no CUDA)
echo "[INSTALL] Installing llama-cpp-python (CPU-only)..."
# Prefer a prebuilt binary wheel: quick, and fails fast if there is none for this platform.
if ! "$VENV_PY" -m pip install -q --only-binary=:all: llama-cpp-python; then
    echo ""
    echo "[NOTICE] No pre-built llama-cpp-python wheel is available for this platform."
    echo "         The only remaining option is to COMPILE it from source. This can take"
    echo "         10-20 minutes, uses most of your CPU, and needs a C/C++ compiler and CMake."
    echo "         You can stop here safely."
    # read returns non-zero on EOF (non-interactive); treat that as "no" so an unattended
    # run never starts a long compile.
    read -r -p "Compile from source now? [y/N] (Default: n): " build_ok || build_ok="n"
    if [[ ! "$build_ok" =~ ^[yY]$ ]]; then
        setup_failed "Source build declined. No llama-cpp-python backend was installed."
    fi
    echo "[BUILD] Compiling from source. pip output is shown so you can follow progress..."
    "$VENV_PY" -m pip install llama-cpp-python || setup_failed "Failed to install llama-cpp-python."
fi

# Install other dependencies
echo "[FINISHING] Finalizing remaining dependencies..."
if [ -f "$SCRIPT_DIR/requirements.txt" ]; then
    "$VENV_PY" -m pip install -q -r "$SCRIPT_DIR/requirements.txt" || setup_failed "Failed to install dependencies from requirements.txt."
else
    "$VENV_PY" -m pip install -q rich requests tqdm textual || setup_failed "Failed to install fallback dependencies."
fi

# Setup succeeded: drop the marker so this environment is trusted from now on.
rm -f "$VENV_DIR/.setup_incomplete" || echo "[WARNING] Could not remove the setup marker; the next run will rebuild this environment." >&2

echo "[DONE] Setup complete! Launching in CPU mode..."
echo ""
run_app
