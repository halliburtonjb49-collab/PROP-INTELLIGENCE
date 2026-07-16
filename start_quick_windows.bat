@echo off
setlocal
cd /d "%~dp0"

set "SAFE_RENDER=%~1"
set "SUPABASE_FLAGS="
if exist "%~dp0supabase.local.json" (
  set "SUPABASE_FLAGS=--dart-define-from-file=supabase.local.json"
) else (
  echo [PROP INTELLIGENCE] Supabase disabled: copy supabase.example.json to supabase.local.json and add the current public key.
)
if /I "%SAFE_RENDER%"=="safe" (
  set "RENDER_FLAGS=--enable-software-rendering"
  echo [PROP INTELLIGENCE] Quick Windows start (SAFE software rendering)...
) else (
  set "RENDER_FLAGS="
  echo [PROP INTELLIGENCE] Quick Windows start...
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
flutter run -d windows --debug %RENDER_FLAGS% %SUPABASE_FLAGS%
endlocal
