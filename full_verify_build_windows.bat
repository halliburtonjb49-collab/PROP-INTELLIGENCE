@echo off
setlocal
cd /d "%~dp0"

echo [PROP INTELLIGENCE] Full verify + build (slow) ...
flutter clean
if errorlevel 1 goto :fail
flutter pub get
if errorlevel 1 goto :fail
dart format lib
if errorlevel 1 goto :fail
flutter analyze
if errorlevel 1 goto :fail
flutter test
if errorlevel 1 goto :fail
set "SUPABASE_FLAGS="
if exist "%~dp0supabase.local.json" set "SUPABASE_FLAGS=--dart-define-from-file=supabase.local.json"
flutter build windows --debug %SUPABASE_FLAGS%
if errorlevel 1 goto :fail

echo Done.
endlocal
exit /b 0

:fail
echo Build pipeline failed.
pause
endlocal
exit /b 1
