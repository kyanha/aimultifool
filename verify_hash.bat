@echo off
:: Shared SHA-256 verification helper for run_windows_*.bat
:: Usage: call verify_hash.bat "<file>" "<manifest_key>" "<manifest_path>"
:: Sets VERIFY_RESULT in the caller's environment to one of:
::   MATCH       - hash computed and equals the pinned value
::   MISMATCH    - hash computed and differs from the pinned value
::   UNVERIFIED  - no pinned hash exists for this key (or manifest absent)
::   ERROR       - a pinned hash exists but the file's hash could not be computed
:: ERROR is deliberately distinct from MISMATCH: "I could not check" must never be
:: reported as "the file is bad" (callers delete files on MISMATCH).
:: Always exits 0; callers must branch on VERIFY_RESULT and treat any value other than
:: the four above (including empty) as ERROR.

setlocal disabledelayedexpansion
set "VH_FILE=%~1"
set "VH_KEY=%~2"
set "VH_MANIFEST=%~3"

if not exist "%VH_MANIFEST%" goto :no_manifest
type "%VH_MANIFEST%" >nul 2>&1
:: Compare exactly (not "if errorlevel N", which means >= N and misses negative codes).
if not "%errorlevel%"=="0" goto :manifest_error

set "VH_EXPECTED="
for /f "usebackq tokens=1,* delims==" %%A in ("%VH_MANIFEST%") do (
    if "%%A"=="%VH_KEY%" set "VH_EXPECTED=%%B"
)

if not defined VH_EXPECTED goto :unverified
if /i "%VH_EXPECTED%"=="UNVERIFIED" goto :unverified

:: Capture certutil's exit status directly (a for /f over the command would discard it).
set "VH_TMP=%TEMP%\vh_%RANDOM%%RANDOM%.txt"
certutil -hashfile "%VH_FILE%" SHA256 >"%VH_TMP%" 2>&1
if not "%errorlevel%"=="0" goto :hash_error

set "VH_ACTUAL="
for /f "usebackq skip=1 tokens=1" %%H in ("%VH_TMP%") do (
    if not defined VH_ACTUAL set "VH_ACTUAL=%%H"
)
del "%VH_TMP%" >nul 2>&1

:: A SHA-256 digest is exactly 64 characters; anything else is not a hash.
if not defined VH_ACTUAL goto :hash_error
set "VH_TAIL=%VH_ACTUAL:~63%"
set "VH_OVER=%VH_ACTUAL:~64%"
if not defined VH_TAIL goto :hash_error
if defined VH_OVER goto :hash_error

if /i "%VH_ACTUAL%"=="%VH_EXPECTED%" (
    endlocal & set "VERIFY_RESULT=MATCH" & exit /b 0
) else (
    endlocal & set "VERIFY_RESULT=MISMATCH" & exit /b 0
)

:unverified
endlocal & set "VERIFY_RESULT=UNVERIFIED" & exit /b 0

:no_manifest
echo [WARNING] Checksum manifest not found: %VH_MANIFEST% 1>&2
endlocal & set "VERIFY_RESULT=UNVERIFIED" & exit /b 0

:manifest_error
echo [ERROR] Checksum manifest could not be read: %VH_MANIFEST% 1>&2
endlocal & set "VERIFY_RESULT=ERROR" & exit /b 0

:hash_error
if defined VH_TMP del "%VH_TMP%" >nul 2>&1
echo [ERROR] Could not compute SHA-256 of %VH_FILE% 1>&2
endlocal & set "VERIFY_RESULT=ERROR" & exit /b 0
