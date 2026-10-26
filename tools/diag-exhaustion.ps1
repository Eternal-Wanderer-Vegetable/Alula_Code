$ErrorActionPreference = 'SilentlyContinue'

Write-Host '=== Resource exhaustion 2004 full messages (last 30 days) ==='
Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-Resource-Exhaustion-Detector'; StartTime=(Get-Date).AddDays(-30)} |
  Select-Object -First 3 | ForEach-Object {
    Write-Host ('---- ' + $_.TimeCreated.ToString('yyyy-MM-dd HH:mm'))
    $_.Message -split "`n" | Select-Object -First 14 | ForEach-Object { Write-Host ('   ' + $_.Trim()) }
  }

Write-Host ''
Write-Host '=== nvlddmkm event detail (09-26) ==='
Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='nvlddmkm'; StartTime=(Get-Date).AddDays(-30)} |
  Select-Object -First 1 | ForEach-Object {
    Write-Host ('time: ' + $_.TimeCreated.ToString('yyyy-MM-dd HH:mm'))
    Write-Host ('level: ' + $_.Level)
    $_.Message -split "`n" | Select-Object -First 6 | ForEach-Object { Write-Host ('   ' + $_.Trim()) }
  }

Write-Host ''
Write-Host '=== Code.exe WER crash P-params (10-08) ==='
Get-WinEvent -FilterHashtable @{LogName='Application'; Id=1001; StartTime=(Get-Date).AddDays(-90)} |
  Where-Object { $_.Message -match 'Code\.exe' -and $_.TimeCreated -match '10-08' } |
  Select-Object -First 1 | ForEach-Object {
    $_.Message -split "`n" | Where-Object { $_ -match '^P[0-9]|Signature|problem|Problem' } |
      Select-Object -First 12 | ForEach-Object { Write-Host ('   ' + $_.Trim()) }
  }
