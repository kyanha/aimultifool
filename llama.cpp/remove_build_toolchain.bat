@echo off
setlocal enabledelayedexpansion

:: Uninstall the build toolchain components that fetch_build_deps.bat installed.
::
:: Only components recorded in ..\.toolchain_installed.txt are considered. That file lists
:: just what fetch_build_deps.bat itself installed because it was missing, so anything you
:: installed yourself is never touched. Each component is confirmed separately, default no,
:: and removed with winget in an ELEVATED process which triggers the Windows UAC prompt.
::
:: Exit status: 0 = nothing failed, 1 = at least one uninstall failed
::
:: Comments inside a parenthesized block must not contain a closing parenthesis, because
:: cmd would end the block there.

for %%I in ("%~dp0..") do set "ROOT_DIR=%%~fI"
set "STATE_FILE=%ROOT_DIR%\.toolchain_installed.txt"
set "NEW_FILE=%ROOT_DIR%\.toolchain_installed.txt.new"
set "ANY_FAILED=0"

echo ----------------------------------------------------------------
echo   aiMultiFool - remove build toolchain installed by fetch_build_deps.bat
echo ----------------------------------------------------------------

if not exist "%STATE_FILE%" (
    echo Nothing to remove. No components are recorded as installed by fetch_build_deps.bat.
    endlocal & exit /b 0
)

where winget >nul 2>&1
if !errorlevel! neq 0 (
    echo [ERROR] winget was not found, so nothing can be uninstalled from here. 1>&2
    echo         Uninstall the listed components from Windows Settings, Installed apps instead: 1>&2
    type "%STATE_FILE%" 1>&2
    endlocal & exit /b 1
)

echo The following components were installed by fetch_build_deps.bat:
type "%STATE_FILE%"
echo.
echo Other software may have started to depend on them since, for example git. You will be
echo asked about each one separately. The default is to keep it.

if exist "%NEW_FILE%" del "%NEW_FILE%" 2>nul

for /f "usebackq delims=" %%L in ("%STATE_FILE%") do call :remove_one "%%L"

:: Whatever was kept or failed stays recorded; everything removed drops off the list.
if exist "%NEW_FILE%" (
    move /y "%NEW_FILE%" "%STATE_FILE%" >nul
    if !errorlevel! neq 0 (
        echo [WARNING] Could not update %STATE_FILE%. Edit it by hand if it is out of date. 1>&2
        set "ANY_FAILED=1"
    )
) else (
    del "%STATE_FILE%" 2>nul
)

echo.
if "!ANY_FAILED!"=="1" (
    echo [INCOMPLETE] At least one component could not be removed. See the messages above.
    endlocal & exit /b 1
)
echo [DONE]
endlocal & exit /b 0

:: ================================================================ subroutines

:remove_one
set "RM_ID=%~1"
if "!RM_ID!"=="" exit /b 0
set "RM_NAME=!RM_ID!"
set "RM_FREES=an unknown amount of disk space"
if /i "!RM_ID!"=="Git.Git" (
    set "RM_NAME=Git for Windows"
    set "RM_FREES=about 0.4 GB, estimate"
)
if /i "!RM_ID!"=="Nvidia.CUDA" (
    set "RM_NAME=NVIDIA CUDA Toolkit"
    set "RM_FREES=about 6 to 8 GB, estimate"
)
if /i "!RM_ID!"=="Microsoft.VisualStudio.2022.BuildTools" (
    set "RM_NAME=Visual Studio 2022 Build Tools"
    set "RM_FREES=about 6 to 9 GB, estimate"
)

echo.
echo   Component : !RM_NAME!, winget id !RM_ID!
echo   Frees     : !RM_FREES!
set "RM_ANS="
set /p "RM_ANS=  Uninstall it now? [y/N] (Default: n): "
if /i not "!RM_ANS!"=="y" (
    echo   [KEPT] !RM_NAME!
    >>"%NEW_FILE%" echo !RM_ID!
    exit /b 0
)

set "WG_ARGS=uninstall --id !RM_ID! -e --silent --accept-source-agreements"
echo   [UNINSTALL] winget !WG_ARGS!
powershell -NoProfile -Command "try { $p = Start-Process -FilePath cmd.exe -ArgumentList ('/c winget ' + $env:WG_ARGS) -Verb RunAs -Wait -PassThru; exit $p.ExitCode } catch { Write-Host ('Elevation failed or was declined: ' + $_.Exception.Message); exit 1223 }"
set "WG_RC=!errorlevel!"
if not "!WG_RC!"=="0" (
    echo   [FAILED] winget exited with status !WG_RC!. If you declined the UAC prompt that is expected.
    echo            To try by hand, run this in an Administrator terminal:  winget !WG_ARGS!
    >>"%NEW_FILE%" echo !RM_ID!
    set "ANY_FAILED=1"
    exit /b 0
)
echo   [REMOVED] !RM_NAME!
exit /b 0
