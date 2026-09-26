#!/bin/bash
# Shared SHA-256 verification helper for run_linux_*.sh.
# Sourced, not executed. Sets $VERIFY_RESULT to MATCH | MISMATCH | UNVERIFIED.

verify_artifact() {
    local file="$1" key="$2" manifest="$3"
    local expected actual

    expected=$(awk -F'=' -v k="$key" '$1==k{print $2; exit}' "$manifest" 2>/dev/null)

    if [ -z "$expected" ] || [ "$expected" = "UNVERIFIED" ]; then
        VERIFY_RESULT="UNVERIFIED"
        return 0
    fi

    actual=$(sha256sum "$file" | cut -d' ' -f1)
    if [ "$actual" = "$expected" ]; then
        VERIFY_RESULT="MATCH"
    else
        VERIFY_RESULT="MISMATCH"
    fi
}
