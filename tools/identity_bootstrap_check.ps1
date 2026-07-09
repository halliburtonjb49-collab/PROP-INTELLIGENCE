$ErrorActionPreference = 'Continue'

$boot = Invoke-RestMethod -Uri 'http://127.0.0.1:8010/api/identity/bootstrap?sourceProvider=odds-api' -Method Post -TimeoutSec 30
Write-Output ('BOOT=' + ($boot | ConvertTo-Json -Compress -Depth 8))

$unresolved = Invoke-RestMethod -Uri 'http://127.0.0.1:8010/api/identity/unresolved?sourceProvider=odds-api&limit=25' -TimeoutSec 30
Write-Output ('UNRESOLVED=' + ($unresolved | ConvertTo-Json -Compress -Depth 8))

$identityMap = Invoke-RestMethod -Uri 'http://127.0.0.1:8010/api/identity/map' -TimeoutSec 30
$providerSize = @($identityMap.providers.'odds-api'.PSObject.Properties).Count
Write-Output ('IDENTITY_PROVIDER_SIZE=' + $providerSize)

$availability = Invoke-RestMethod -Uri 'http://127.0.0.1:8010/api/player-availability' -TimeoutSec 30
$availabilityCount = @($availability.players.PSObject.Properties).Count
Write-Output ('AVAILABILITY_SIZE=' + $availabilityCount)

$audit = Invoke-RestMethod -Uri 'http://127.0.0.1:8010/api/accuracy/audit' -TimeoutSec 30
Write-Output ('AUDIT=' + ($audit | ConvertTo-Json -Compress -Depth 10))
