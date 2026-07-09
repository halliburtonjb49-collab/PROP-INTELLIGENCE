$ErrorActionPreference = 'Continue'

$outPath = 'c:\Users\theda\Projects\The-Daily-Spin\python_backend\data\identity_unresolved_grouped.json'

$payload = Invoke-RestMethod -Uri 'http://127.0.0.1:8010/api/identity/unresolved-grouped?sourceProvider=odds-api&limit=5000' -TimeoutSec 30
$json = $payload | ConvertTo-Json -Depth 12
Set-Content -Path $outPath -Value $json -Encoding UTF8

Write-Output ('EXPORTED=' + $outPath)
Write-Output ('COUNT=' + $payload.count)
Write-Output ('SPORTS=' + (($payload.sports.PSObject.Properties | Select-Object -ExpandProperty Name) -join ','))
