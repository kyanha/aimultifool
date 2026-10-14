@echo off
setlocal enabledelayedexpansion

:: Fetch the components needed to build the llama-cpp-python wheel, from UPSTREAM sources
:: only, never from aimultifool.com:
::   - CPython 3.12 build interpreter  from the astral-sh/python-build-standalone GitHub
::                                     release, SHA-256 pinned in ..\checksums.sha256
::   - llama-cpp-python source         from abetlen/llama-cpp-python at a tag, with the
::                                     clone required to resolve to a pinned commit
:: The Python goes in ..\python_portable\ shared with the run scripts. The source goes in
:: ..\build_deps\. Both are git-ignored.
::
:: Compilers and SDKs are large, need admin rights and licence acceptance. For each missing
:: one this script shows the download size and disk use, then asks before installing it
:: with winget in an ELEVATED process, which triggers the normal Windows UAC prompt.
:: Only components this script itself installed are recorded, in ..\.toolchain_installed.txt,
:: and remove_build_toolchain.bat in this folder uninstalls exactly those.
::
:: Exit status: 0 = everything fetched and the toolchain is present
::              1 = a fetch or verification failed, or the toolchain is incomplete
::
:: Compare errorlevel with "!errorlevel! neq 0" and never "if errorlevel 1", which misses
:: negative exit codes. Comments inside a parenthesized block must not contain a closing
:: parenthesis, because cmd would end the block there.

for %%I in ("%~dp0..") do set "ROOT_DIR=%%~fI"
set "DEPS_DIR=%ROOT_DIR%\build_deps"
set "CHECKSUM_MANIFEST=%ROOT_DIR%\checksums.sha256"
set "STATE_FILE=%ROOT_DIR%\.toolchain_installed.txt"
set "REMOVE_SCRIPT=llama.cpp\remove_build_toolchain.bat"

set "PY_TAR=cpython-3.12.12+20260114-x86_64-pc-windows-msvc-install_only_stripped.tar.gz"
:: Keep this URL free of percent signs and use the raw plus sign, which GitHub accepts.
:: The call command re-expands percent sequences, so a URL-encoded plus sign would be
:: read as a batch argument and the download would give a 404.
set "PY_URL=https://github.com/astral-sh/python-build-standalone/releases/download/20260114/cpython-3.12.12+20260114-x86_64-pc-windows-msvc-install_only_stripped.tar.gz"
:: Shared with run_windows_*.bat: same asset, same pinned hash, one copy on disk.
set "PY_DIR=%ROOT_DIR%\python_portable"
set "PY_TAR_PATH=%PY_DIR%\%PY_TAR%"

set "SRC_REPO=https://github.com/abetlen/llama-cpp-python.git"
set "SRC_TAG=v0.3.16"
set "SRC_COMMIT=c37132bac860fcc333255c36313f89c4f49d4c8d"
set "SRC_DIR=%DEPS_DIR%\llama-cpp-python"

set "TOOLCHAIN_MISSING=0"
set "INSTALLED_ANY=0"
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"

for %%H in (verify_hash.bat download_file.bat) do (
    if not exist "%ROOT_DIR%\%%H" (
        set "DIE_MSG=Required helper script missing: %%H"
        goto :die
    )
)
if not exist "%CHECKSUM_MANIFEST%" (
    set "DIE_MSG=Checksum manifest missing: checksums.sha256"
    goto :die
)

echo ----------------------------------------------------------------
echo   aiMultiFool - fetch wheel build components, upstream sources
echo ----------------------------------------------------------------

if not exist "%DEPS_DIR%" mkdir "%DEPS_DIR%"
if not exist "%DEPS_DIR%" (
    set "DIE_MSG=Could not create directory: build_deps"
    goto :die
)

:: Free space on the system drive, where winget installs by default.
set "FREE_GB="
for /f %%G in ('powershell -NoProfile -Command "[math]::Floor((Get-PSDrive ($env:SystemDrive.Substring(0,1))).Free/1GB)"') do set "FREE_GB=%%G"
if not defined FREE_GB set "FREE_GB=unknown"

:: ---------------------------------------------------------------- 1. build Python
echo.
echo [1/3] Build Python, python-build-standalone with pinned hash
if exist "%PY_DIR%\python.exe" (
    "%PY_DIR%\python.exe" --version >nul 2>&1
    if !errorlevel! equ 0 (
        echo [FOUND] Build Python already present.
        goto :python_done
    )
    echo [WARNING] Existing build Python does not run; re-fetching.
    rmdir /s /q "%PY_DIR%" 2>nul
    if exist "%PY_DIR%" (
        set "DIE_MSG=Could not remove broken build Python directory."
        goto :die
    )
)

if not exist "%PY_DIR%" mkdir "%PY_DIR%"
if not exist "%PY_DIR%" (
    set "DIE_MSG=Could not create directory: python_portable"
    goto :die
)

:: A cached tarball is only trusted if it matches the pin; anything else is discarded.
if exist "%PY_TAR_PATH%" (
    set "VERIFY_RESULT="
    call "%ROOT_DIR%\verify_hash.bat" "%PY_TAR_PATH%" "%PY_TAR%" "%CHECKSUM_MANIFEST%"
    if not "!VERIFY_RESULT!"=="MATCH" (
        echo [SECURITY] Cached tarball did not verify, result !VERIFY_RESULT!; discarding.
        del "%PY_TAR_PATH%" 2>nul
        if exist "%PY_TAR_PATH%" (
            set "DIE_MSG=Could not remove unverified cached tarball."
            goto :die
        )
    )
)

if not exist "%PY_TAR_PATH%" (
    echo [NETWORK] Downloading %PY_TAR%, about 21 MB
    echo [SOURCE]  %PY_URL%
    call "%ROOT_DIR%\download_file.bat" "%PY_URL%" "%PY_TAR_PATH%"
    if !errorlevel! neq 0 (
        set "DIE_MSG=Download failed with all available mechanisms."
        goto :die
    )
    :: Antivirus can delete a file right after a successful download. Say so plainly
    :: and do not retry or work around it.
    if not exist "%PY_TAR_PATH%" (
        set "DIE_MSG=Download reported success but the file disappeared, likely blocked or quarantined by antivirus. Not retrying."
        goto :die
    )
)

:: Fail closed: the build interpreter must MATCH its pinned hash. UNVERIFIED is not enough.
set "VERIFY_RESULT="
call "%ROOT_DIR%\verify_hash.bat" "%PY_TAR_PATH%" "%PY_TAR%" "%CHECKSUM_MANIFEST%"
if not "!VERIFY_RESULT!"=="MATCH" (
    del "%PY_TAR_PATH%" 2>nul
    set "DIE_MSG=Build Python tarball did not match its pinned SHA-256, result: !VERIFY_RESULT!. Discarded."
    goto :die
)
echo [SECURITY] Hash verified.

where tar >nul 2>&1
if !errorlevel! neq 0 (
    set "DIE_MSG=tar not found, it requires Windows 10 1803 or newer."
    goto :die
)
echo [EXTRACT] Extracting build Python...
tar -xzf "%PY_TAR_PATH%" -C "%PY_DIR%" --strip-components=1
if !errorlevel! neq 0 (
    rmdir /s /q "%PY_DIR%" 2>nul
    set "DIE_MSG=Extraction of build Python failed."
    goto :die
)
"%PY_DIR%\python.exe" --version
if !errorlevel! neq 0 (
    rmdir /s /q "%PY_DIR%" 2>nul
    set "DIE_MSG=Extracted build Python does not run."
    goto :die
)
:python_done

:: ---------------------------------------------------------------- 2. toolchain
echo.
echo [2/3] Toolchain check, with an offer to install anything missing
echo       Free space on %SystemDrive% is !FREE_GB! GB. Installs go there by default.

:: ---- git
where git >nul 2>&1
if !errorlevel! equ 0 (
    echo [OK]      git
) else (
    echo [MISSING] git
    set "OFFER_ID=Git.Git"
    set "OFFER_NAME=Git for Windows"
    set "OFFER_DL=62 MB, measured for Git 2.55"
    set "OFFER_PEAK=under 0.5 GB of temporary space, estimate"
    set "OFFER_DISK=about 0.4 GB, estimate"
    set "OFFER_ARGS="
    call :offer_install
    if "!OFFER_RESULT!"=="installed" (
        set "GIT_NEW=1"
    ) else (
        set "TOOLCHAIN_MISSING=1"
    )
)
:: A fresh git install is not on PATH in this session yet, so add it for the source step.
if defined GIT_NEW if exist "%ProgramFiles%\Git\cmd\git.exe" set "PATH=%ProgramFiles%\Git\cmd;%PATH%"

:: ---- CUDA toolkit
set "NVCC_FOUND="
where nvcc >nul 2>&1
if !errorlevel! equ 0 set "NVCC_FOUND=on PATH"
if not defined NVCC_FOUND for /d %%D in ("%ProgramFiles%\NVIDIA GPU Computing Toolkit\CUDA\v*") do if exist "%%D\bin\nvcc.exe" set "NVCC_FOUND=%%D"
if defined NVCC_FOUND (
    echo [OK]      CUDA toolkit, nvcc found: !NVCC_FOUND!
) else (
    echo [MISSING] CUDA toolkit, nvcc
    set "OFFER_ID=Nvidia.CUDA"
    set "OFFER_NAME=NVIDIA CUDA Toolkit"
    set "OFFER_DL=3.6 GB, measured for CUDA 13.4.1"
    set "OFFER_PEAK=roughly another 4 to 8 GB in TEMP while it extracts, estimate"
    set "OFFER_DISK=about 6 to 8 GB, estimate"
    set "OFFER_ARGS="
    call :offer_install
    if not "!OFFER_RESULT!"=="installed" set "TOOLCHAIN_MISSING=1"
)

:: ---- Visual Studio C++ build tools
call :detect_msvc
if defined VS_FOUND (
    echo [OK]      Visual Studio C++ build tools
) else (
    echo [MISSING] Visual Studio C++ build tools, MSVC
    set "OFFER_ID=Microsoft.VisualStudio.2022.BuildTools"
    set "OFFER_NAME=Visual Studio 2022 Build Tools, C++ workload"
    set "OFFER_DL=4 MB bootstrapper, then roughly 2 to 3 GB of packages, estimate"
    set "OFFER_PEAK=several GB in TEMP and the package cache, estimate"
    set "OFFER_DISK=about 6 to 9 GB, estimate"
    set OFFER_ARGS=--override "--add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --passive --norestart"
    call :offer_install
    if not "!OFFER_RESULT!"=="installed" set "TOOLCHAIN_MISSING=1"
)

echo.
echo CMake and Ninja are installed automatically by the build, as PyPI build requirements.

:: ---------------------------------------------------------------- 3. source
echo.
echo [3/3] llama-cpp-python source %SRC_TAG%, pinned commit
where git >nul 2>&1
if !errorlevel! neq 0 (
    echo [SKIPPED] git is not available, so the source was not fetched.
    set "TOOLCHAIN_MISSING=1"
    goto :source_done
)

if exist "%SRC_DIR%\.git" (
    set "ACTUAL_COMMIT="
    for /f "delims=" %%C in ('git -C "%SRC_DIR%" rev-parse HEAD 2^>nul') do set "ACTUAL_COMMIT=%%C"
    if not defined ACTUAL_COMMIT (
        set "DIE_MSG=Existing source directory is not a readable git checkout. Delete build_deps\llama-cpp-python and re-run."
        goto :die
    )
    if /i not "!ACTUAL_COMMIT!"=="%SRC_COMMIT%" (
        set "DIE_MSG=Existing source is at !ACTUAL_COMMIT!, not the pinned %SRC_COMMIT%. Delete build_deps\llama-cpp-python and re-run."
        goto :die
    )
    echo [FOUND] Source already at pinned commit; making sure submodules are present...
    git -C "%SRC_DIR%" submodule update --init --recursive
    if !errorlevel! neq 0 (
        set "DIE_MSG=git submodule update failed."
        goto :die
    )
    goto :source_done
)

if exist "%SRC_DIR%" (
    set "DIE_MSG=%SRC_DIR% exists but is not a git checkout. Delete it and re-run."
    goto :die
)

echo [NETWORK] Cloning %SRC_REPO% at %SRC_TAG% with submodules...
git clone --branch "%SRC_TAG%" --recurse-submodules --shallow-submodules --depth 1 "%SRC_REPO%" "%SRC_DIR%"
if !errorlevel! neq 0 (
    rmdir /s /q "%SRC_DIR%" 2>nul
    set "DIE_MSG=git clone failed."
    goto :die
)

:: The tag name is not trusted on its own. The commit it resolves to must match the pin.
set "ACTUAL_COMMIT="
for /f "delims=" %%C in ('git -C "%SRC_DIR%" rev-parse HEAD 2^>nul') do set "ACTUAL_COMMIT=%%C"
if not defined ACTUAL_COMMIT (
    rmdir /s /q "%SRC_DIR%" 2>nul
    set "DIE_MSG=Could not read the commit of the fresh clone. Discarded."
    goto :die
)
if /i not "!ACTUAL_COMMIT!"=="%SRC_COMMIT%" (
    rmdir /s /q "%SRC_DIR%" 2>nul
    set "DIE_MSG=Tag %SRC_TAG% resolved to !ACTUAL_COMMIT!, expected %SRC_COMMIT%. Clone discarded."
    goto :die
)
echo [SECURITY] Source commit verified: !ACTUAL_COMMIT!
:source_done

:: ---------------------------------------------------------------- summary
if exist "%STATE_FILE%" (
    echo.
    echo [UNINSTALL] This script installed the components listed in .toolchain_installed.txt
    echo             To remove them later, run:  %REMOVE_SCRIPT%
)

if "!TOOLCHAIN_MISSING!"=="1" (
    echo.
    echo [INCOMPLETE] Downloads are done, but the toolchain above is incomplete.
    endlocal & exit /b 1
)

echo.
echo [DONE] Build components are ready.
echo        Source : %SRC_DIR%
echo        Python : %PY_DIR%\python.exe
if "!INSTALLED_ANY!"=="1" (
    echo [ACTION] Open a NEW terminal before building so the newly installed tools are on PATH.
)
endlocal & exit /b 0

:: ================================================================ subroutines

:detect_msvc
set "VS_FOUND="
if exist "%VSWHERE%" (
    for /f "usebackq delims=" %%P in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VS_FOUND=%%P"
)
if not defined VS_FOUND (
    where cl >nul 2>&1
    if !errorlevel! equ 0 set "VS_FOUND=cl.exe on PATH"
)
exit /b 0

:offer_install
:: In:  OFFER_ID OFFER_NAME OFFER_DL OFFER_PEAK OFFER_DISK OFFER_ARGS
:: Out: OFFER_RESULT = installed, declined, failed or unavailable
set "OFFER_RESULT=declined"
echo.
echo   Component    : %OFFER_NAME%, winget id %OFFER_ID%
echo   Download     : %OFFER_DL%
echo   Temporary    : %OFFER_PEAK%
echo   Installed    : %OFFER_DISK%
echo   Free on %SystemDrive%   : !FREE_GB! GB
echo   It will be installed with winget in an elevated process, so Windows will show a UAC
echo   prompt. You can remove it again later with %REMOVE_SCRIPT%
where winget >nul 2>&1
if !errorlevel! neq 0 (
    echo   [UNAVAILABLE] winget was not found, so it cannot be installed from here.
    set "OFFER_RESULT=unavailable"
    exit /b 0
)
set "OFFER_ANS="
set /p "OFFER_ANS=  Install %OFFER_NAME% now? [y/N] (Default: n): "
if /i not "!OFFER_ANS!"=="y" (
    echo   [SKIPPED] Not installing %OFFER_NAME%.
    exit /b 0
)

set "WG_ARGS=install --id %OFFER_ID% -e --accept-package-agreements --accept-source-agreements %OFFER_ARGS%"
echo   [INSTALL] winget !WG_ARGS!
powershell -NoProfile -Command "try { $p = Start-Process -FilePath cmd.exe -ArgumentList ('/c winget ' + $env:WG_ARGS) -Verb RunAs -Wait -PassThru; exit $p.ExitCode } catch { Write-Host ('Elevation failed or was declined: ' + $_.Exception.Message); exit 1223 }"
set "WG_RC=!errorlevel!"
if not "!WG_RC!"=="0" (
    echo   [FAILED] winget exited with status !WG_RC!. If you declined the UAC prompt that is expected.
    echo            To try by hand, run this in an Administrator terminal:  winget !WG_ARGS!
    set "OFFER_RESULT=failed"
    exit /b 0
)

:: Record only what this script itself installed, so the removal script never touches
:: anything the user already had.
>>"%STATE_FILE%" echo %OFFER_ID%
set "INSTALLED_ANY=1"
set "OFFER_RESULT=installed"
echo   [SUCCESS] %OFFER_NAME% installed and recorded for later removal.
exit /b 0

:die
echo [CRITICAL] !DIE_MSG! 1>&2
endlocal & exit /b 1
