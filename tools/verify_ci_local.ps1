$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

function Invoke-CheckedNativeCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Label,
        [Parameter(Mandatory = $true)]
        [scriptblock]$Command
    )

    Write-Host "[verify] $Label"
    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw "[verify] $Label failed with exit code $LASTEXITCODE"
    }
}

if ($env:PI_VERIFY_CI_SELF_TEST -eq '1') {
    Invoke-CheckedNativeCommand -Label 'native failure self-test' -Command {
        & $env:ComSpec /d /c exit 17
    }
    throw '[verify] native failure self-test unexpectedly continued'
}

Invoke-CheckedNativeCommand -Label 'flutter pub get' -Command {
    flutter pub get
}

Invoke-CheckedNativeCommand -Label 'flutter analyze' -Command {
    flutter analyze
}

Invoke-CheckedNativeCommand -Label 'flutter test' -Command {
    flutter test
}

$venvPython = Join-Path $repoRoot '.venv\Scripts\python.exe'
if (Test-Path $venvPython) {
    Invoke-CheckedNativeCommand -Label 'python -m pytest (venv)' -Command {
        & $venvPython -m pytest
    }
} else {
    Invoke-CheckedNativeCommand -Label 'pytest' -Command {
        pytest
    }
}

Write-Host "[verify] all checks passed"
