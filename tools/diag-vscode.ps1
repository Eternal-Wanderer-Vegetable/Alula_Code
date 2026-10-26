$ErrorActionPreference = 'SilentlyContinue'

Write-Host '=== WER 1001 (Code.exe, last 90 days) ==='
Get-WinEvent -FilterHashtable @{LogName='Application'; Id=1001; StartTime=(Get-Date).AddDays(-90)} |
  Where-Object { $_.Message -match 'Code\.exe' } |
  Select-Object -First 4 | ForEach-Object {
    Write-Host ('---- ' + $_.TimeCreated.ToString('yyyy-MM-dd HH:mm'))
    $_.Message -split "`n" | Where-Object {
      $_ -match 'App|Faulting|Exception|P1|P2' } |
      Select-Object -First 6 | ForEach-Object { Write-Host ('   ' + $_.Trim()) }
  }

Write-Host ''
Write-Host '=== App Error 1000 (Code.exe, last 90 days) ==='
Get-WinEvent -FilterHashtable @{LogName='Application'; Id=1000; StartTime=(Get-Date).AddDays(-90)} |
  Where-Object { $_.Message -match 'Code\.exe' } |
  Select-Object -First 6 | ForEach-Object {
    Write-Host ('---- ' + $_.TimeCreated.ToString('yyyy-MM-dd HH:mm'))
    $_.Message -split "`n" | Select-Object -First 8 | ForEach-Object { Write-Host ('   ' + $_.Trim()) }
  }

Write-Host ''
Write-Host '=== Resource exhaustion 2004 (last 90 days) ==='
$events = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-Resource-Exhaustion-Detector'; StartTime=(Get-Date).AddDays(-90)}
if ($events) {
  Write-Host ('total: ' + $events.Count)
  $events | Select-Object -First 5 | ForEach-Object { Write-Host ('   ' + $_.TimeCreated.ToString('yyyy-MM-dd HH:mm')) }
} else {
  Write-Host '   none'
}

Write-Host ''
Write-Host '=== Display/DWM/GPU driver errors (last 30 days) ==='
$disp = Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2,3; StartTime=(Get-Date).AddDays(-30)} |
  Where-Object { $_.ProviderName -match 'Display|nvlddmkm|amd|Dwm' }
if ($disp) {
  Write-Host ('total: ' + $disp.Count)
  $disp | Select-Object -First 8 | ForEach-Object {
    Write-Host ('   ' + $_.TimeCreated.ToString('MM-dd HH:mm') + ' [' + $_.ProviderName + '] ' + (($_.Message -split "`n")[0])) }
} else {
  Write-Host '   none'
}
