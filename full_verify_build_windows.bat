@echo off
setlocal
cd /d "%~dp0"

echo [Daily Spin] Full verify + build (slow) ...
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
flutter build windows --debug
if errorlevel 1 goto :fail

echo Done.
endlocal
exit /b 0

:fail
echo Build pipeline failed.
pause
endlocal
exit /b 1
