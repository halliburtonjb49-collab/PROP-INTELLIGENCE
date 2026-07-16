$ErrorActionPreference = 'Continue'

taskkill /IM python.exe /F | Out-Null
Start-Sleep -Milliseconds 300

Push-Location 'c:\Users\theda\Projects\PROP INTELLIGENCE\prop_intelligence\python_backend'
Start-Process -WindowStyle Hidden -FilePath '.\.venv\Scripts\python.exe' -ArgumentList @('-m', 'uvicorn', 'main:app', '--host', '127.0.0.1', '--port', '8010')
Pop-Location

Start-Sleep -Seconds 2
try {
  $h = Invoke-RestMethod -Uri 'http://127.0.0.1:8010/health' -TimeoutSec 5
  Write-Output ('HEALTH=' + ($h | ConvertTo-Json -Compress))
} catch {
  Write-Output ('HEALTH_ERR=' + $_.Exception.Message)
}
