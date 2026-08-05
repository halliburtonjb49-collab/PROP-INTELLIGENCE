$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

Write-Host "[verify] flutter pub get"
flutter pub get

Write-Host "[verify] flutter analyze"
flutter analyze

Write-Host "[verify] flutter test"
flutter test

$venvPython = Join-Path $repoRoot '.venv\Scripts\python.exe'
if (Test-Path $venvPython) {
    Write-Host "[verify] python -m pytest (venv)"
    & $venvPython -m pytest
} else {
    Write-Host "[verify] pytest"
    pytest
}

Write-Host "[verify] all checks passed"
