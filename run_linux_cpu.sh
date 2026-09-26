#!/bin/bash

# Setup script for aiMultiFool console chat app (CPU-only mode)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$SCRIPT_DIR/venv_cpu"
PYTHON_PORTABLE_DIR="$SCRIPT_DIR/python_portable"
PYTHON_PORTABLE_TAR="cpython-3.12.12+20260114-x86_64-unknown-linux-gnu-install_only.tar.gz"
PYTHON_PORTABLE_URL="https://aimultifool.com/$PYTHON_PORTABLE_TAR"
PYTHON_PORTABLE_TAR_PATH="$PYTHON_PORTABLE_DIR/$PYTHON_PORTABLE_TAR"
PYTHON_CMD="python3"
CHECKSUM_MANIFEST="$SCRIPT_DIR/checksums.sha256"
source "$SCRIPT_DIR/verify_hash.sh"
source "$SCRIPT_DIR/download_file.sh"

echo "----------------------------------------------------------------"
echo "  aiMultiFool Suite - CPU-Only Setup & Launch Script v0.1.9"
echo "----------------------------------------------------------------"

# 0. Setup Portable Python
if [ ! -f "$PYTHON_PORTABLE_DIR/bin/python3" ]; then
    echo "[PYTHON] Portable Python not found. Setting up..."

    # Create python_portable directory
    mkdir -p "$PYTHON_PORTABLE_DIR"

    # If a cached tarball exists, verify it before trusting it. A mismatch here means the
    # cache is bad (corrupted or tampered) - remove it and fall through to a fresh download.
    if [ -f "$PYTHON_PORTABLE_TAR_PATH" ]; then
        verify_artifact "$PYTHON_PORTABLE_TAR_PATH" "$PYTHON_PORTABLE_TAR" "$CHECKSUM_MANIFEST"
        case "$VERIFY_RESULT" in
            MISMATCH)
                echo "[SECURITY] Cached $PYTHON_PORTABLE_TAR failed hash verification."
                if rm -f "$PYTHON_PORTABLE_TAR_PATH"; then
                    echo "[SECURITY] Removed bad cached file; will re-download."
                else
                    echo "[CRITICAL] Could not remove bad cached file. Aborting."
                    exit 1
                fi
                ;;
            UNVERIFIED)
                echo "[WARNING] No pinned hash for $PYTHON_PORTABLE_TAR; skipping integrity check."
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
                    echo "[CRITICAL] Downloaded $PYTHON_PORTABLE_TAR failed hash verification. Aborting."
                    rm -f "$PYTHON_PORTABLE_TAR_PATH"
                    exit 1
                    ;;
            esac
        fi
    fi

    # Extract portable Python if tar exists
    if [ -f "$PYTHON_PORTABLE_TAR_PATH" ]; then
        echo "[EXTRACT] Extracting portable Python..."
        tar -xzf "$PYTHON_PORTABLE_TAR_PATH" -C "$PYTHON_PORTABLE_DIR" --strip-components=1
        if [ -f "$PYTHON_PORTABLE_DIR/bin/python3" ]; then
            PYTHON_CMD="$PYTHON_PORTABLE_DIR/bin/python3"
            echo "[SUCCESS] Portable Python ready!"
        else
            echo "[WARNING] Extraction may have failed. Using system Python."
        fi
    fi
else
    PYTHON_CMD="$PYTHON_PORTABLE_DIR/bin/python3"
    echo "[PYTHON] Using portable Python: $PYTHON_CMD"
fi

# Check if venv already exists
if [ -d "$VENV_DIR" ]; then
    echo "[STATUS] Virtual environment detected."
    echo "[INFO]   It is recommended to reinstall (y) if you just updated to a new version."
    read -p "Do you want to reinstall the environment? [y/N] (Default: n): " choice
    if [[ "$choice" =~ ^[yY]$ ]]; then
        echo "[ACTION] Reinstalling environment..."
        rm -rf "$VENV_DIR"
    else
        echo "[SKIP] Skipping environment setup."
        source "$VENV_DIR/bin/activate"
        echo "[LAUNCH] Starting aiMultiFool TUI (CPU mode)..."
        echo ""
        python "$SCRIPT_DIR/aimultifool.py" --cpu
        exit 0
    fi
fi

# Create virtual environment
echo "[STEP 1/3] Creating fresh virtual environment (venv_cpu)..."
"$PYTHON_CMD" -m venv "$VENV_DIR"

# Activate virtual environment
echo "[STEP 2/3] Activating environment..."
source "$VENV_DIR/bin/activate"

# Upgrade pip
echo "[STEP 3/3] Upgrading pip to latest version..."
pip install -q --upgrade pip

# Install llama-cpp-python (CPU-only, no CUDA)
echo "[INSTALL] Installing llama-cpp-python (CPU-only)..."
pip install -q llama-cpp-python

# Install other dependencies
echo "[FINISHING] Finalizing remaining dependencies..."
if [ -f "$SCRIPT_DIR/requirements.txt" ]; then
    pip install -q -r "$SCRIPT_DIR/requirements.txt"
else
    pip install -q rich requests tqdm textual
fi

echo "[DONE] Setup complete! Launching in CPU mode..."
echo ""
python "$SCRIPT_DIR/aimultifool.py" --cpu
