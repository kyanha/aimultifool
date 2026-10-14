#!/bin/bash
# Shared SHA-256 verification helper for run_linux_*.sh.
# Sourced, not executed. Sets $VERIFY_RESULT to one of:
#   MATCH       - hash computed and equals the pinned value
#   MISMATCH    - hash computed and differs from the pinned value
#   UNVERIFIED  - no pinned hash exists for this key (or manifest absent)
#   ERROR       - a pinned hash exists but the file's hash could not be computed
# ERROR is deliberately distinct from MISMATCH: "I could not check" must never be
# reported as "the file is bad" (callers delete files on MISMATCH).
# The function always returns 0; callers must branch on $VERIFY_RESULT and treat any
# value other than the four above as ERROR.

verify_artifact() {
    local file="$1" key="$2" manifest="$3"
    local expected actual

    VERIFY_RESULT="ERROR"

    if [ ! -r "$manifest" ]; then
        echo "[WARNING] Checksum manifest not readable: $manifest" >&2
        VERIFY_RESULT="UNVERIFIED"
        return 0
    fi

    if ! expected=$(awk -F'=' -v k="$key" '$1==k{print $2; exit}' "$manifest"); then
        echo "[ERROR] Failed to read checksum manifest: $manifest" >&2
        return 0
    fi
    expected="${expected%$'\r'}"

    if [ -z "$expected" ] || [ "$expected" = "UNVERIFIED" ]; then
        VERIFY_RESULT="UNVERIFIED"
        return 0
    fi

    if command -v sha256sum &> /dev/null; then
        actual=$(sha256sum "$file") || actual=""
    elif command -v shasum &> /dev/null; then
        actual=$(shasum -a 256 "$file") || actual=""
    else
        echo "[ERROR] Neither sha256sum nor shasum is available to verify $file" >&2
        return 0
    fi
    actual="${actual%% *}"

    if [ -z "$actual" ]; then
        echo "[ERROR] Could not compute SHA-256 of $file" >&2
        return 0
    fi

    if [ "$actual" = "$expected" ]; then
        VERIFY_RESULT="MATCH"
    else
        VERIFY_RESULT="MISMATCH"
    fi
    return 0
}
