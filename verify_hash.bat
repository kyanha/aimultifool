@echo off
:: Shared SHA-256 verification helper for run_windows_*.bat
:: Usage: call verify_hash.bat "<file>" "<manifest_key>" "<manifest_path>"
:: Sets VERIFY_RESULT in the caller's environment to MATCH | MISMATCH | UNVERIFIED

setlocal disabledelayedexpansion
set "VH_FILE=%~1"
set "VH_KEY=%~2"
set "VH_MANIFEST=%~3"

set "VH_EXPECTED="
for /f "usebackq tokens=1,* delims==" %%A in ("%VH_MANIFEST%") do (
    if "%%A"=="%VH_KEY%" set "VH_EXPECTED=%%B"
)

if not defined VH_EXPECTED (
    endlocal & set "VERIFY_RESULT=UNVERIFIED" & exit /b 0
)
if /i "%VH_EXPECTED%"=="UNVERIFIED" (
    endlocal & set "VERIFY_RESULT=UNVERIFIED" & exit /b 0
)

set "VH_ACTUAL="
for /f "skip=1 tokens=1" %%H in ('certutil -hashfile "%VH_FILE%" SHA256') do (
    if not defined VH_ACTUAL set "VH_ACTUAL=%%H"
)

if /i "%VH_ACTUAL%"=="%VH_EXPECTED%" (
    endlocal & set "VERIFY_RESULT=MATCH" & exit /b 0
) else (
    endlocal & set "VERIFY_RESULT=MISMATCH" & exit /b 0
)
