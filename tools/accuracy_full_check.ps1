$ErrorActionPreference = 'Continue'

Write-Output '=== PORT CHECK ==='
foreach ($p in @(8000, 8010, 8011)) {
  Write-Output ("PORT=" + $p)
  try {
    $h = Invoke-RestMethod -Uri ("http://127.0.0.1:$p/health") -TimeoutSec 5
    Write-Output ("HEALTH=" + ($h | ConvertTo-Json -Compress))
  } catch {
    Write-Output ("HEALTH_ERR=" + $_.Exception.Message)
  }
}

Write-Output '=== SYNC CHECK ==='
try {
  $sync = Invoke-RestMethod -Uri 'http://127.0.0.1:8010/api/sync' -Method Post -TimeoutSec 180
  Write-Output ("SYNC=" + ($sync | ConvertTo-Json -Compress -Depth 8))
} catch {
  Write-Output ("SYNC_ERR=" + $_.Exception.Message)
}

Write-Output '=== PROPS DATE/TIME CHECK ==='
try {
  $resp = Invoke-RestMethod -Uri 'http://127.0.0.1:8010/api/props?side=All&tier=All&minConfidence=0&sortBy=time' -TimeoutSec 30
  $props = @($resp.props)
  $today = [DateTime]::Today
  $dates = @()
  foreach ($p in $props) {
    try {
      $dates += [DateTimeOffset]::Parse($p.startTimeUtc).ToLocalTime().DateTime
    } catch {}
  }

  $hasPast = ($dates | Where-Object { $_.Date -lt $today } | Select-Object -First 1) -ne $null
  $sorted = $true
  for ($i = 1; $i -lt $dates.Count; $i++) {
    if ($dates[$i] -lt $dates[$i - 1]) {
      $sorted = $false
      break
    }
  }

  Write-Output ("COUNT=" + $resp.count)
  Write-Output ("HAS_PAST=" + $hasPast)
  Write-Output ("SORTED_ASC_TIME=" + $sorted)
  Write-Output ("FILTERS=" + ($resp.filters | ConvertTo-Json -Compress))
} catch {
  Write-Output ("PROPS_ERR=" + $_.Exception.Message)
}

Write-Output '=== ACCURACY AUDIT ==='
try {
  $audit = Invoke-RestMethod -Uri 'http://127.0.0.1:8010/api/accuracy/audit' -TimeoutSec 30
  Write-Output ("AUDIT=" + ($audit | ConvertTo-Json -Compress -Depth 10))
} catch {
  Write-Output ("AUDIT_ERR=" + $_.Exception.Message)
}
