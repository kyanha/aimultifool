@echo off
:: Shared download helper for run_windows_*.bat
:: Usage: call download_file.bat "<url>" "<output_path>"
:: Tries every available mechanism in turn (curl, PowerShell, certutil) instead of
:: stopping at the first one found, in case that one fails at runtime.
:: Exit code 0 = success (non-empty file produced), 1 = all mechanisms failed.

setlocal enabledelayedexpansion
set "DL_URL=%~1"
set "DL_OUT=%~2"
set "DL_OK=0"

where curl >nul 2>&1
if !errorlevel! equ 0 (
    echo [NETWORK] Trying curl...
    curl -f -L --progress-bar -o "%DL_OUT%" "%DL_URL%"
    call :check_size
)

if "!DL_OK!"=="0" (
    if exist "%DL_OUT%" del "%DL_OUT%" 2>nul
    where powershell >nul 2>&1
    if !errorlevel! equ 0 (
        echo [WARNING] curl unavailable or failed. Trying PowerShell...
        powershell -Command "& { $ProgressPreference = 'Continue'; Invoke-WebRequest -Uri '%DL_URL%' -OutFile '%DL_OUT%' }"
        call :check_size
    )
)

if "!DL_OK!"=="0" (
    if exist "%DL_OUT%" del "%DL_OUT%" 2>nul
    where certutil >nul 2>&1
    if !errorlevel! equ 0 (
        echo [WARNING] PowerShell unavailable or failed. Trying certutil...
        certutil -urlcache -split -f "%DL_URL%" "%DL_OUT%" >nul
        call :check_size
    )
)

if "!DL_OK!"=="0" (
    if exist "%DL_OUT%" del "%DL_OUT%" 2>nul
    endlocal & exit /b 1
) else (
    endlocal & exit /b 0
)

:check_size
if exist "%DL_OUT%" (
    for %%Z in ("%DL_OUT%") do if %%~zZ gtr 0 set "DL_OK=1"
)
exit /b 0
