param(
    [Parameter(Mandatory = $false)]
    [string]$OwnerJwt = "",
    [Parameter(Mandatory = $false)]
    [string]$ApiBase = "https://api.propsintell.com",
    [Parameter(Mandatory = $false)]
    [string]$DatabaseUrl = "",
    [Parameter(Mandatory = $false)]
    [int]$PerformanceDays = 30
)

$ErrorActionPreference = "Stop"

if (-not $DatabaseUrl) {
    if (-not $env:DATABASE_URL) {
        throw "Set \$env:DATABASE_URL or pass -DatabaseUrl."
    }
} else {
    $env:DATABASE_URL = $DatabaseUrl
}

if (-not (Test-Path ".venv\Scripts\python.exe")) {
    throw "Python virtualenv not found at .venv\Scripts\python.exe"
}

Write-Host "1) Running Supabase migrations..." -ForegroundColor Cyan
.venv\Scripts\python.exe python_backend\scripts\apply_supabase_migrations.py

if (-not $OwnerJwt) {
    $OwnerJwt = Read-Host "Paste OWNER_JWT for operations endpoints"
}

if (-not $OwnerJwt) {
    throw "OWNER_JWT is required for smoke checks."
}

Write-Host "2) Running prop-learning snapshot endpoint..." -ForegroundColor Cyan
curl.exe -s -X POST -H "Authorization: Bearer $OwnerJwt" "$ApiBase/api/operations/prop-learning/snapshot" | Write-Output

Write-Host "3) Running prop-learning grade endpoint..." -ForegroundColor Cyan
curl.exe -s -X POST -H "Authorization: Bearer $OwnerJwt" "$ApiBase/api/operations/prop-learning/grade" | Write-Output

Write-Host "4) Running prop-learning performance endpoint..." -ForegroundColor Cyan
curl.exe -s -H "Authorization: Bearer $OwnerJwt" "$ApiBase/api/operations/prop-learning/performance?days=$PerformanceDays" | Write-Output

Write-Host "5) Committing and pushing changes..." -ForegroundColor Cyan
git add supabase_prop_learning_system.sql python_backend/services/prop_learning_service.py python_backend/services/sync_service.py python_backend/routers/operations.py python_backend/scripts/apply_supabase_migrations.py README.md docs/PROP_LEARNING_SYSTEM_ROLLBACK_AND_ROLLFORWARD_RUNBOOK.md
git commit -m "Add closed-loop prop learning rollout hardening and docs"
git push

Write-Host "6) Trigger your deploy manually in your platform (Render/CI) from this branch/commit." -ForegroundColor Yellow
Write-Host "Done."
