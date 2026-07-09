@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "ROOT=%~dp0"
set "BACKEND_URL=http://127.0.0.1:8000/health"
set "PROPS_URL=http://127.0.0.1:8000/api/props"
set "MIN_PROP_COUNT=5"
set "BACKEND_DIR=%ROOT%python_backend"
set "APP_EXE="
set "PYTHON_EXE="

if exist "%ROOT%..\python_backend\main.py" (
  set "BACKEND_DIR=%ROOT%..\python_backend"
)

call :resolve_app_exe
if not defined APP_EXE goto :no_app

call :backend_ready
if errorlevel 1 (
  call :resolve_python
  if not defined PYTHON_EXE goto :no_python

  echo [Daily Spin] Starting backend...
  start "Daily Spin Backend" /min /D "%BACKEND_DIR%" "%PYTHON_EXE%" -m uvicorn main:app --host 127.0.0.1 --port 8000

  call :wait_for_backend
  if errorlevel 1 goto :backend_failed
) else (
  echo [Daily Spin] Backend already running.
)

echo [Daily Spin] Launching desktop app...
start "" "%APP_EXE%"
exit /b 0

:resolve_app_exe
if exist "%ProgramFiles%\The Daily Spin\daily_spin_flutter.exe" (
  set "APP_EXE=%ProgramFiles%\The Daily Spin\daily_spin_flutter.exe"
  goto :eof
)
if defined ProgramFiles(x86) if exist "%ProgramFiles(x86)%\The Daily Spin\daily_spin_flutter.exe" (
  set "APP_EXE=%ProgramFiles(x86)%\The Daily Spin\daily_spin_flutter.exe"
  goto :eof
)
if exist "%ROOT%build\windows\x64\runner\Release\daily_spin_flutter.exe" (
  set "APP_EXE=%ROOT%build\windows\x64\runner\Release\daily_spin_flutter.exe"
  goto :eof
)
if exist "%ROOT%build\windows\x64\runner\Debug\daily_spin_flutter.exe" (
  set "APP_EXE=%ROOT%build\windows\x64\runner\Debug\daily_spin_flutter.exe"
)
goto :eof

:resolve_python
if exist "%BACKEND_DIR%\.venv\Scripts\python.exe" (
  set "PYTHON_EXE=%BACKEND_DIR%\.venv\Scripts\python.exe"
  goto :eof
)

for /f "usebackq delims=" %%I in (`python -c "import sys, uvicorn, fastapi; print(sys.executable)" 2^>nul`) do (
  set "PYTHON_EXE=%%I"
)
if defined PYTHON_EXE goto :eof

for %%V in (3.14 3.13 3.12 3.11 3.10 3.9) do (
  for /f "usebackq delims=" %%I in (`py -%%V -c "import sys, uvicorn, fastapi; print(sys.executable)" 2^>nul`) do (
    set "PYTHON_EXE=%%I"
  )
  if defined PYTHON_EXE goto :eof
)
goto :eof

:backend_ready
powershell -NoProfile -Command "try { $health = Invoke-RestMethod -Uri '%BACKEND_URL%' -TimeoutSec 2; if ($health.status -ne 'ok') { exit 1 }; $props = Invoke-RestMethod -Uri '%PROPS_URL%' -TimeoutSec 5; if (($props.props | Measure-Object).Count -ge %MIN_PROP_COUNT%) { exit 0 } } catch { }; exit 1" >nul 2>nul
exit /b %ERRORLEVEL%

:wait_for_backend
powershell -NoProfile -Command "$deadline=(Get-Date).AddSeconds(30); while((Get-Date) -lt $deadline){ try { $health = Invoke-RestMethod -Uri '%BACKEND_URL%' -TimeoutSec 2; if ($health.status -eq 'ok') { $props = Invoke-RestMethod -Uri '%PROPS_URL%' -TimeoutSec 5; if (($props.props | Measure-Object).Count -ge %MIN_PROP_COUNT%) { exit 0 } } } catch { }; Start-Sleep -Milliseconds 500 }; exit 1"
exit /b %ERRORLEVEL%

:no_app
echo [Daily Spin] No desktop app executable was found.
echo Install the app, or build Windows first, then rerun this launcher.
echo Development fallback: use start_quick_windows.bat
exit /b 1

:no_python
echo [Daily Spin] Could not find a Python interpreter with FastAPI and Uvicorn installed.
echo Install backend dependencies, then rerun this launcher.
exit /b 1

:backend_failed
echo [Daily Spin] Backend did not become healthy on port 8000.
echo Check the "Daily Spin Backend" window for startup errors.
exit /b 1