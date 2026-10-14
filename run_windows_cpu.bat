@echo off
setlocal enabledelayedexpansion

:: Setup script for aiMultiFool console chat app (CPU-only mode, Windows)
::
:: Every step that can fail is checked via its exit status. Failures that have a fallback
:: print a warning and continue; failures that do not go to :die or :setup_failed.
:: Compare errorlevel with "!errorlevel! neq 0" - never "if errorlevel 1", which misses
:: negative exit codes such as 0xC0000135.

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "VENV_DIR=%SCRIPT_DIR%\venv_cpu"
set "VENV_PY=%VENV_DIR%\Scripts\python.exe"
set "PYTHON_PORTABLE_DIR=%SCRIPT_DIR%\python_portable"
set "PYTHON_PORTABLE_TAR=cpython-3.12.12+20260114-x86_64-pc-windows-msvc-install_only_stripped.tar.gz"
set "PYTHON_PORTABLE_URL=https://aimultifool.com/%PYTHON_PORTABLE_TAR%"
set "PYTHON_PORTABLE_TAR_PATH=%PYTHON_PORTABLE_DIR%\%PYTHON_PORTABLE_TAR%"
:: PYTHON_CMD is the executable only; PYTHON_ARGS holds any launcher arguments, so that
:: "%PYTHON_CMD%" stays a single valid quoted path.
set "PYTHON_CMD=py"
set "PYTHON_ARGS="
set "CHECKSUM_MANIFEST=%SCRIPT_DIR%\checksums.sha256"

for %%H in (verify_hash.bat download_file.bat) do (
    if not exist "%SCRIPT_DIR%\%%H" (
        set "DIE_MSG=Required helper script missing: %%H"
        goto :die
    )
)

echo ----------------------------------------------------------------
echo   aiMultiFool Suite - CPU-Only Setup ^& Launch Script v0.1.9 (Windows)
echo ----------------------------------------------------------------

:: 0. Setup Portable Python
if not exist "%PYTHON_PORTABLE_DIR%\python.exe" (
    echo [PYTHON] Portable Python not found. Setting up...

    :: Create python_portable directory
    if not exist "%PYTHON_PORTABLE_DIR%" mkdir "%PYTHON_PORTABLE_DIR%"
    if not exist "%PYTHON_PORTABLE_DIR%" (
        set "DIE_MSG=Could not create directory for portable Python."
        goto :die
    )

    :: If a cached tarball exists, verify it before trusting it. A mismatch means the
    :: cache is bad, corrupted or tampered: remove it and fall through to a fresh download.
    if exist "%PYTHON_PORTABLE_TAR_PATH%" (
        set "VERIFY_RESULT="
        call "%SCRIPT_DIR%\verify_hash.bat" "%PYTHON_PORTABLE_TAR_PATH%" "%PYTHON_PORTABLE_TAR%" "%CHECKSUM_MANIFEST%"
        if "!VERIFY_RESULT!"=="MISMATCH" (
            echo [SECURITY] Cached %PYTHON_PORTABLE_TAR% failed hash verification.
            del "%PYTHON_PORTABLE_TAR_PATH%" 2>nul
            if exist "%PYTHON_PORTABLE_TAR_PATH%" (
                set "DIE_MSG=Could not remove bad cached file. Aborting."
                goto :die
            ) else (
                echo [SECURITY] Removed bad cached file; will re-download.
            )
        ) else if "!VERIFY_RESULT!"=="UNVERIFIED" (
            echo [WARNING] No pinned hash for %PYTHON_PORTABLE_TAR%; skipping integrity check.
        ) else if not "!VERIFY_RESULT!"=="MATCH" (
            set "DIE_MSG=Could not run hash verification on cached portable Python. Aborting."
            goto :die
        )
    )

    :: Download portable Python if tar doesn't exist
    if not exist "%PYTHON_PORTABLE_TAR_PATH%" (
        echo [NETWORK] Downloading portable Python 3.12 ^(~50MB^)...
        echo [SOURCE]  %PYTHON_PORTABLE_URL%

        call "%SCRIPT_DIR%\download_file.bat" "%PYTHON_PORTABLE_URL%" "%PYTHON_PORTABLE_TAR_PATH%"
        if !errorlevel! neq 0 (
            echo [ERROR] Download failed with all available mechanisms ^(curl/PowerShell^).
            echo [FALLBACK] Will use system Python instead.
        )

        :: A freshly downloaded file that fails verification is not recoverable by
        :: retrying - abort rather than loop.
        if exist "%PYTHON_PORTABLE_TAR_PATH%" (
            set "VERIFY_RESULT="
            call "%SCRIPT_DIR%\verify_hash.bat" "%PYTHON_PORTABLE_TAR_PATH%" "%PYTHON_PORTABLE_TAR%" "%CHECKSUM_MANIFEST%"
            if "!VERIFY_RESULT!"=="MISMATCH" (
                del "%PYTHON_PORTABLE_TAR_PATH%" 2>nul
                set "DIE_MSG=Downloaded portable Python failed hash verification. Aborting."
                goto :die
            ) else if "!VERIFY_RESULT!"=="UNVERIFIED" (
                echo [WARNING] No pinned hash for %PYTHON_PORTABLE_TAR%; skipping integrity check.
            ) else if "!VERIFY_RESULT!"=="MATCH" (
                echo [SECURITY] Hash verified.
            ) else (
                set "DIE_MSG=Could not run hash verification on downloaded portable Python. Aborting."
                goto :die
            )
        )
    )

    :: Extract portable Python if tar exists
    if exist "%PYTHON_PORTABLE_TAR_PATH%" (
        echo [EXTRACT] Extracting portable Python...
        :: Use tar, available on Windows 10 1803 and newer
        where tar >nul 2>&1
        if !errorlevel! equ 0 (
            tar -xzf "%PYTHON_PORTABLE_TAR_PATH%" -C "%PYTHON_PORTABLE_DIR%" --strip-components=1
            if !errorlevel! equ 0 (
                if exist "%PYTHON_PORTABLE_DIR%\python.exe" (
                    set "PYTHON_CMD=%PYTHON_PORTABLE_DIR%\python.exe"
                    set "PYTHON_ARGS="
                    echo [SUCCESS] Portable Python ready!
                ) else (
                    echo [WARNING] Extraction completed but python.exe not found. Using system Python.
                )
            ) else (
                echo [ERROR] Extraction failed. Using system Python instead.
                :: Discard the tarball and any partial extraction so the next run starts clean.
                rmdir /s /q "%PYTHON_PORTABLE_DIR%" 2>nul
            )
        ) else (
            echo [ERROR] tar command not found ^(requires Windows 10 1803+^). Please install tar or use system Python.
            echo [FALLBACK] Will use system Python instead.
        )
    )
) else (
    set "PYTHON_CMD=%PYTHON_PORTABLE_DIR%\python.exe"
    set "PYTHON_ARGS="
    echo [PYTHON] Using portable Python: !PYTHON_CMD!
)

:: A marker file exists from venv creation until setup fully succeeds. If it is still
:: there, a previous setup was interrupted or failed, so that venv cannot be trusted.
if exist "%VENV_DIR%\.setup_incomplete" (
    echo [STATUS] A previous setup did not finish. Discarding that environment.
    rmdir /s /q "%VENV_DIR%"
    if exist "%VENV_DIR%" (
        set "DIE_MSG=Could not remove incomplete environment."
        goto :die
    )
)

:: Check if venv already exists
if exist "%VENV_DIR%" (
    echo [STATUS] Virtual environment detected.
    echo [INFO]   It is recommended to reinstall ^(y^) if you just updated to a new version.
    :: Clear first: set /p leaves the variable untouched on EOF, e.g. when non-interactive.
    set "choice="
    set /p "choice=Do you want to reinstall the environment? [y/N] (Default: n): "
    if /i "!choice!"=="y" (
        echo [ACTION] Reinstalling environment...
        rmdir /s /q "%VENV_DIR%"
        if exist "%VENV_DIR%" (
            set "DIE_MSG=Could not remove existing environment."
            goto :die
        )
    ) else (
        echo [SKIP] Skipping environment setup.
        if not exist "%VENV_DIR%\Scripts\activate.bat" (
            set "DIE_MSG=Existing environment is incomplete. Re-run and choose y to reinstall."
            goto :die
        )
        :: activate.bat's own exit status is not reliable. Clear VIRTUAL_ENV, which may be
        :: inherited from the parent shell, and check that activation set it instead.
        set "VIRTUAL_ENV="
        call "%VENV_DIR%\Scripts\activate.bat"
        if not defined VIRTUAL_ENV (
            set "DIE_MSG=Failed to activate virtual environment."
            goto :die
        )
        echo [LAUNCH] Starting aiMultiFool TUI ^(CPU mode^)...
        echo.
        goto :run_app
    )
)

:: The interpreter that will build the venv must actually run. Prefer what we have, but
:: if it is broken, try plain "python" on PATH before giving up.
"%PYTHON_CMD%" %PYTHON_ARGS% --version >nul 2>&1
if !errorlevel! neq 0 (
    python --version >nul 2>&1
    if !errorlevel! equ 0 (
        echo [WARNING] "%PYTHON_CMD%" is not usable; falling back to python on PATH.
        set "PYTHON_CMD=python"
        set "PYTHON_ARGS="
    ) else (
        set "DIE_MSG=No usable Python interpreter found. Install Python 3.12 or newer and re-run."
        goto :die
    )
)

:: Create virtual environment
echo [STEP 1/3] Creating fresh virtual environment ^(venv_cpu^)...
"%PYTHON_CMD%" %PYTHON_ARGS% -m venv "%VENV_DIR%"
if !errorlevel! neq 0 (
    set "DIE_MSG=Failed to create virtual environment."
    goto :setup_failed
)
if not exist "%VENV_PY%" (
    set "DIE_MSG=Virtual environment was created but its python.exe is missing."
    goto :setup_failed
)
:: Mark the environment as unfinished until setup succeeds.
type nul > "%VENV_DIR%\.setup_incomplete"
if not exist "%VENV_DIR%\.setup_incomplete" (
    set "DIE_MSG=Could not write the setup marker file in the new environment."
    goto :setup_failed
)

:: Activate virtual environment
echo [STEP 2/3] Activating environment...
set "VIRTUAL_ENV="
call "%VENV_DIR%\Scripts\activate.bat"
if not defined VIRTUAL_ENV (
    set "DIE_MSG=Failed to activate virtual environment."
    goto :setup_failed
)

:: Upgrade pip. A stale pip is survivable, so this is a warning rather than a rejection.
echo [STEP 3/3] Upgrading pip to latest version...
"%VENV_PY%" -m pip install -q --upgrade pip
if !errorlevel! neq 0 echo [WARNING] pip upgrade failed; continuing with the bundled pip.

:: Install llama-cpp-python (CPU-only, no CUDA)
echo [INSTALL] Installing llama-cpp-python ^(CPU-only^)...
:: Prefer a prebuilt binary wheel: quick, and it fails fast if there is none for this platform.
"%VENV_PY%" -m pip install -q --only-binary=:all: llama-cpp-python
if !errorlevel! neq 0 (
    echo.
    echo [NOTICE] No pre-built llama-cpp-python wheel is available for this platform.
    echo          The only remaining option is to COMPILE it from source. This can take
    echo          10 to 20 minutes, uses most of your CPU, and needs the Visual Studio C++
    echo          build tools. You can stop here safely.
    set "BUILD_OK="
    set /p "BUILD_OK=Compile from source now? [y/N] (Default: n): "
    if /i not "!BUILD_OK!"=="y" (
        set "DIE_MSG=Source build declined. No llama-cpp-python backend was installed."
        goto :setup_failed
    )
    echo [BUILD] Compiling from source. pip output is shown so you can follow progress...
    "%VENV_PY%" -m pip install llama-cpp-python
    if !errorlevel! neq 0 (
        set "DIE_MSG=Failed to install llama-cpp-python."
        goto :setup_failed
    )
)

:: Install other dependencies
echo [FINISHING] Finalizing remaining dependencies...
if exist "%SCRIPT_DIR%\requirements.txt" (
    "%VENV_PY%" -m pip install -q -r "%SCRIPT_DIR%\requirements.txt"
) else (
    "%VENV_PY%" -m pip install -q rich requests tqdm textual
)
if !errorlevel! neq 0 (
    set "DIE_MSG=Failed to install application dependencies."
    goto :setup_failed
)

:: Setup succeeded: drop the marker so this environment is trusted from now on.
del "%VENV_DIR%\.setup_incomplete" 2>nul
if exist "%VENV_DIR%\.setup_incomplete" (
    echo [WARNING] Could not remove the setup marker; the next run will rebuild this environment. 1>&2
)

echo [DONE] Setup complete! Launching in CPU mode...
echo.

:run_app
:: Hand the app's exit status back to our caller instead of swallowing it.
"%VENV_PY%" "%SCRIPT_DIR%\aimultifool.py" --cpu
set "APP_RC=!errorlevel!"
if not "!APP_RC!"=="0" echo [ERROR] aiMultiFool exited with status !APP_RC!. 1>&2
endlocal & exit /b %APP_RC%

:setup_failed
:: A half-built venv is worse than none: the next run would offer to skip setup and
:: launch the app without its dependencies. Remove it so the next run starts clean.
echo [CLEANUP] Removing incomplete virtual environment so the next run starts clean. 1>&2
rmdir /s /q "%VENV_DIR%" 2>nul

:die
echo [CRITICAL] !DIE_MSG! 1>&2
endlocal & exit /b 1
