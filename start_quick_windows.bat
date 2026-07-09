@echo off
setlocal
cd /d "%~dp0"

set "SAFE_RENDER=%~1"
if /I "%SAFE_RENDER%"=="safe" (
  set "RENDER_FLAGS=--enable-software-rendering"
  echo [Daily Spin] Quick Windows start (SAFE software rendering)...
) else (
  set "RENDER_FLAGS="
  echo [Daily Spin] Quick Windows start...
)

where flutter >nul 2>nul
if errorlevel 1 (
  echo Flutter is not on PATH. Open a terminal where Flutter is configured.
  pause
  exit /b 1
)

flutter pub get
if errorlevel 1 (
  echo flutter pub get failed.
  pause
  exit /b 1
)

echo Launching app (debug) %RENDER_FLAGS% ...
flutter run -d windows --debug %RENDER_FLAGS%
endlocal
