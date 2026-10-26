$ErrorActionPreference = 'Continue'
$code = 'C:\Users\Vegetable\AppData\Local\Programs\Microsoft VS Code\Code.exe'
$fixture = 'E:\Alula_Code\tests\fixtures\rust-mini'
$probe = 'E:\Alula_Code\target\release\mem-probe.exe'

function Test-Run($label, $extDir, $outPrefix) {
  Write-Host ('=== ' + $label + ' ===')
  $profileDir = "$env:TEMP\vsdiag-$label-profile"
  New-Item -ItemType Directory -Force -Path $profileDir | Out-Null

  & $probe watch --exe $code `
    --arg "--user-data-dir=$profileDir" `
    --arg "--extensions-dir=$extDir" `
    --arg $fixture `
    --duration 45 --interval 1 `
    --label $outPrefix `
    --out "E:\Alula_Code\docs\diagnostics\2026-10-26-vscode-ab\$outPrefix.json" `
    --md "E:\Alula_Code\docs\diagnostics\2026-10-26-vscode-ab\$outPrefix.md"
  if ($LASTEXITCODE -ne 0) { Write-Host 'probe failed' }

  $inst = Get-Process Code -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowTitle -ne '' } | Select-Object -First 1
  if ($inst) {
    $hung = 0; $total = 0
    1..10 | ForEach-Object {
      $inst.Refresh()
      $total++
      if (-not $inst.Responding) { $hung++ }
      Start-Sleep -Milliseconds 500
    }
    Write-Host ('responsiveness: ' + ($total - $hung) + '/' + $total + ' samples OK')
    taskkill /PID $inst.Id /T /F 2>$null | Out-Null
  } else {
    Write-Host 'no active window found'
  }
  Start-Sleep -Seconds 3
}

New-Item -ItemType Directory -Force -Path 'E:\Alula_Code\docs\diagnostics\2026-10-26-vscode-ab' | Out-Null
New-Item -ItemType Directory -Force -Path "$env:TEMP\vsdiag-empty-ext" | Out-Null

Test-Run 'A-ext' "$env:USERPROFILE\.vscode\extensions" 'vscode-A-extensions'
Test-Run 'B-noext' "$env:TEMP\vsdiag-empty-ext" 'vscode-B-noext'

Write-Host '=== compare ==='
python E:\Alula_Code\tools\bench\bench.py compare `
  E:\Alula_Code\docs\diagnostics\2026-10-26-vscode-ab\vscode-A-extensions.json `
  E:\Alula_Code\docs\diagnostics\2026-10-26-vscode-ab\vscode-B-noext.json
