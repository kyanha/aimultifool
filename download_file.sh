#!/bin/bash
# Shared download helper for run_linux_*.sh.
# Sourced, not executed. Tries every available mechanism in turn (wget, curl,
# python3 urllib) instead of stopping at the first one found, in case that one
# fails at runtime (missing TLS certs, blocked protocol, transient network issue).
#
# Usage: download_with_fallback <url> <output_path>
# Returns 0 if any mechanism produced a non-empty file, 1 if all failed.

download_with_fallback() {
    local url="$1" out="$2"

    if command -v wget &> /dev/null; then
        echo "[NETWORK] Trying wget..."
        if wget --show-progress -O "$out" "$url" && [ -s "$out" ]; then
            return 0
        fi
        echo "[WARNING] wget failed. Trying next mechanism..."
        rm -f "$out"
    fi

    if command -v curl &> /dev/null; then
        echo "[NETWORK] Trying curl..."
        if curl -f -L -# -o "$out" "$url" && [ -s "$out" ]; then
            return 0
        fi
        echo "[WARNING] curl failed. Trying next mechanism..."
        rm -f "$out"
    fi

    if command -v python3 &> /dev/null; then
        echo "[NETWORK] Trying python3 urllib..."
        if python3 -c "import urllib.request,sys; urllib.request.urlretrieve(sys.argv[1], sys.argv[2])" "$url" "$out" && [ -s "$out" ]; then
            return 0
        fi
        echo "[WARNING] python3 download failed."
        rm -f "$out"
    fi

    return 1
}
