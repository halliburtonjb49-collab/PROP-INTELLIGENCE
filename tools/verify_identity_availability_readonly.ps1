$ErrorActionPreference = 'Continue'

$map = Invoke-RestMethod -Uri 'http://127.0.0.1:8010/api/identity/map' -TimeoutSec 20
$providerSize = @($map.providers.'odds-api'.PSObject.Properties).Count
Write-Output ('IDENTITY_PROVIDER_SIZE=' + $providerSize)

$avail = Invoke-RestMethod -Uri 'http://127.0.0.1:8010/api/player-availability' -TimeoutSec 20
$availabilitySize = @($avail.players.PSObject.Properties).Count
Write-Output ('AVAILABILITY_SIZE=' + $availabilitySize)

$grouped = Invoke-RestMethod -Uri 'http://127.0.0.1:8010/api/identity/unresolved-grouped?sourceProvider=odds-api&limit=5000' -TimeoutSec 30
Write-Output ('UNRESOLVED_GROUPED_COUNT=' + $grouped.count)
Write-Output ('UNRESOLVED_SPORTS=' + (($grouped.sports.PSObject.Properties | Select-Object -ExpandProperty Name) -join ','))
