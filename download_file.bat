@echo off
:: Shared download helper for run_windows_*.bat
:: Usage: call download_file.bat "<url>" "<output_path>"
:: Tries every available mechanism in turn (curl, PowerShell) instead of stopping at the
:: first one found, in case that one fails at runtime.
:: certutil -urlcache is deliberately NOT used: it is a well-known malware download
:: technique and Windows Defender flags the command line (Trojan:Win32/Ceprolad.A).
:: A mechanism only counts as successful if it exited 0 AND produced a non-empty file;
:: a non-empty file alone proves nothing (an interrupted download leaves a partial file).
:: Exit code 0 = success, 1 = all mechanisms failed, 2 = bad usage.

setlocal enabledelayedexpansion
if "%~1"=="" goto :usage
if "%~2"=="" goto :usage
set "DL_URL=%~1"
set "DL_OUT=%~2"
set "DL_OK=0"

where curl >nul 2>&1
if !errorlevel! equ 0 (
    echo [NETWORK] Trying curl...
    curl -f -L --progress-bar -o "%DL_OUT%" "%DL_URL%"
    set "DL_RC=!errorlevel!"
    if "!DL_RC!"=="0" (
        call :check_size
    ) else (
        echo [WARNING] curl exited with status !DL_RC!.
    )
)

if "!DL_OK!"=="0" (
    if exist "%DL_OUT%" del "%DL_OUT%" 2>nul
    where powershell >nul 2>&1
    if !errorlevel! equ 0 (
        echo [WARNING] curl unavailable or failed. Trying PowerShell...
        powershell -NoProfile -Command "$ErrorActionPreference='Stop'; try { Invoke-WebRequest -Uri '%DL_URL%' -OutFile '%DL_OUT%' } catch { Write-Host $_.Exception.Message; exit 1 }"
        set "DL_RC=!errorlevel!"
        if "!DL_RC!"=="0" (
            call :check_size
        ) else (
            echo [WARNING] PowerShell exited with status !DL_RC!.
        )
    )
)

if "!DL_OK!"=="0" (
    if exist "%DL_OUT%" del "%DL_OUT%" 2>nul
    endlocal & exit /b 1
) else (
    endlocal & exit /b 0
)

:usage
echo Usage: call download_file.bat "<url>" "<output_path>" 1>&2
exit /b 2

:check_size
if exist "%DL_OUT%" (
    for %%Z in ("%DL_OUT%") do if %%~zZ gtr 0 set "DL_OK=1"
)
exit /b 0
