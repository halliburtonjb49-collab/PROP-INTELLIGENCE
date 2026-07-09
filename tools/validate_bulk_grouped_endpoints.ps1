$ErrorActionPreference = 'Continue'

$m = Invoke-RestMethod -Uri 'http://127.0.0.1:8010/api/identity/map' -TimeoutSec 20
$providers = @($m.providers.PSObject.Properties | Select-Object -ExpandProperty Name)
Write-Output ('MAP_PROVIDERS=' + ($providers -join ','))

$u = Invoke-RestMethod -Uri 'http://127.0.0.1:8010/api/identity/unresolved-grouped?sourceProvider=odds-api&limit=2000' -TimeoutSec 20
Write-Output ('UNRESOLVED_GROUPED_COUNT=' + $u.count)
Write-Output ('UNRESOLVED_SPORTS=' + (($u.sports.PSObject.Properties | Select-Object -ExpandProperty Name) -join ','))

$bulkAvailabilityBody = @{
  players = @{
    'manual:test-player' = @{
      injury_status = 'questionable'
      lineup_status = 'bench'
      notes = 'test'
    }
  }
} | ConvertTo-Json -Depth 6

$b = Invoke-RestMethod -Uri 'http://127.0.0.1:8010/api/player-availability/bulk?mode=merge' -Method Post -ContentType 'application/json' -Body $bulkAvailabilityBody -TimeoutSec 20
Write-Output ('BULK_AVAIL=' + ($b | ConvertTo-Json -Compress))

$identityBulkBody = @{
  providers = @{
    'odds-api' = @{
      'manual-source-id-1' = @{
        canonical_player_id = 'manual:sample-player'
        full_name = 'Sample Player'
        aliases = @('Sample P.')
      }
    }
  }
} | ConvertTo-Json -Depth 8

$i = Invoke-RestMethod -Uri 'http://127.0.0.1:8010/api/identity/map/bulk?mode=merge' -Method Post -ContentType 'application/json' -Body $identityBulkBody -TimeoutSec 20
Write-Output ('BULK_IDENTITY=' + ($i | ConvertTo-Json -Compress))
