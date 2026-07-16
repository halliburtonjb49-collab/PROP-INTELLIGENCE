@echo off
setlocal

set "ROOT=%~dp0"
set "ISCC1=C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
set "ISCC2=C:\Program Files\Inno Setup 6\ISCC.exe"
set "ISCC3=%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe"

if exist "%ISCC1%" (
  set "ISCC=%ISCC1%"
) else if exist "%ISCC2%" (
  set "ISCC=%ISCC2%"
) else if exist "%ISCC3%" (
  set "ISCC=%ISCC3%"
) else (
  where iscc >nul 2>nul
  if %ERRORLEVEL%==0 (
    for /f "delims=" %%I in ('where iscc') do (
      set "ISCC=%%I"
      goto :compile
    )
  )
  echo Inno Setup compiler not found.
  echo Install Inno Setup 6 and rerun this script.
  exit /b 1
)

:compile
echo Using ISCC: %ISCC%
"%ISCC%" "%ROOT%installer.iss"
if %ERRORLEVEL% neq 0 (
  echo Installer build failed.
  exit /b %ERRORLEVEL%
)

echo Installer created in dist\

powershell -NoProfile -Command "$desktop=[Environment]::GetFolderPath('Desktop'); $dist='%ROOT%dist'; $all=Get-ChildItem -Path $dist -Filter 'PROP-INTELLIGENCE-Setup-*.exe' | Sort-Object LastWriteTime -Descending; $src=$all | Select-Object -First 1; if(-not $src){ Write-Output 'No installer exe found in dist after build.'; exit 2 }; $base=[System.IO.Path]::GetFileNameWithoutExtension($src.Name); $ext=[System.IO.Path]::GetExtension($src.Name); $stamp=Get-Date -Format 'yyyyMMdd-HHmmss'; $dest=Join-Path $desktop ($base + '-' + $stamp + $ext); Copy-Item -Path $src.FullName -Destination $dest -Force; $stale=$all | Select-Object -Skip 1; if($stale){ $stale | Remove-Item -Force; Write-Output ('Pruned old installers in dist: ' + $stale.Count) }; Write-Output ('Installer copied to Desktop: ' + $dest)"
if %ERRORLEVEL% neq 0 (
  echo Warning: Installer was built but Desktop copy failed.
)

exit /b 0
