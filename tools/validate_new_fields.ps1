$ErrorActionPreference = 'Continue'

$sync = Invoke-RestMethod -Uri 'http://127.0.0.1:8010/api/sync' -Method Post -TimeoutSec 180
Write-Output ('SYNC=' + ($sync | ConvertTo-Json -Compress -Depth 8))

$props = Invoke-RestMethod -Uri 'http://127.0.0.1:8010/api/props?side=All&tier=All&minConfidence=0&sortBy=time' -TimeoutSec 30
$first = @($props.props | Select-Object -First 3 player,playerId,sourcePlayerId,canonicalPlayerId,playerIdentityConfidence,injuryStatus,lineupStatus,openingLine,currentLine,lineMovedAtUtc,lastUpdatedUtc,sourceProvider,recommendedSide,confidence,edgeSigned)
Write-Output ('FIRST=' + ($first | ConvertTo-Json -Compress))

$movement = @(
  $props.props |
    Where-Object {
      $_.openingLine -ne $null -and
      $_.currentLine -ne $null -and
      [math]::Abs([double]$_.openingLine - [double]$_.currentLine) -ge 0.01
    } |
    Select-Object -First 5 player,market,openingLine,currentLine,lineMovedAtUtc
)
Write-Output ('MOVEMENT_SAMPLE=' + ($movement | ConvertTo-Json -Compress))

$audit = Invoke-RestMethod -Uri 'http://127.0.0.1:8010/api/accuracy/audit' -TimeoutSec 30
Write-Output ('AUDIT=' + ($audit | ConvertTo-Json -Compress -Depth 10))
