param(
  [Parameter(Mandatory = $true)]
  [string]$ProbePath,
  [Parameter(Mandatory = $true)]
  [string]$OutputDirectory,
  [Parameter(Mandatory = $true)]
  [string]$MemProbePath
)

if (-not (Test-Path $OutputDirectory)) {
  New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}
if (-not (Test-Path $ProbePath)) { throw "Probe executable not found: $ProbePath" }
if (-not (Test-Path $MemProbePath)) { throw "mem-probe executable not found: $MemProbePath" }

Get-Process -Name web_engine_probe -ErrorAction SilentlyContinue |
  Stop-Process -Force
Start-Sleep -Milliseconds 500

$phasePath = Join-Path $env:TEMP 'p00.4-web-probe-phase.txt'
$initialPng = Join-Path $env:TEMP 'p00.4-web-initial-render.png'
$mhtmlPng = Join-Path $env:TEMP 'p00.4-web-mhtml-render.png'
Remove-Item $phasePath, $initialPng, $mhtmlPng -Force -ErrorAction SilentlyContinue

$previousAuto = $env:P00_4_WEB_AUTO
$env:P00_4_WEB_AUTO = '1'
$process = Start-Process -FilePath $ProbePath -PassThru
if ($null -eq $previousAuto) {
  Remove-Item Env:P00_4_WEB_AUTO
} else {
  $env:P00_4_WEB_AUTO = $previousAuto
}

for ($attempt = 0; $attempt -lt 80; $attempt++) {
  $process.Refresh()
  if ($process.MainWindowHandle -ne 0) { break }
  if ($process.HasExited) { throw "Probe exited during startup with code $($process.ExitCode)" }
  Start-Sleep -Milliseconds 250
}
if ($process.MainWindowHandle -eq 0) { throw "Probe window did not appear" }
Write-Output "started_pid=$($process.Id) auto_mode=1"

function Save-Memory([string]$name) {
  $raw = & $MemProbePath tree --pid $process.Id
  if ($LASTEXITCODE -ne 0) { throw "mem-probe failed at $name with exit $LASTEXITCODE" }
  $path = Join-Path $OutputDirectory $name
  [System.IO.File]::WriteAllText($path, ($raw -join [Environment]::NewLine))
  Write-Output "saved=$path"
}

function Wait-ForPhase([string]$expected, [int]$timeoutSeconds = 45) {
  $deadline = (Get-Date).AddSeconds($timeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    $process.Refresh()
    if ($process.HasExited) { throw "Probe exited before phase '$expected'" }
    if ((Test-Path $phasePath) -and ([System.IO.File]::ReadAllText($phasePath) -eq $expected)) {
      Write-Output "phase=$expected"
      return
    }
    Start-Sleep -Milliseconds 250
  }
  throw "Timed out waiting for probe phase '$expected'"
}

function Copy-RenderedPng([string]$source, [string]$name) {
  if (-not (Test-Path $source)) { throw "CDP screenshot missing: $source" }
  $destination = Join-Path $OutputDirectory $name
  Copy-Item $source $destination -Force
  Write-Output "saved=$destination"
}

Start-Sleep -Seconds 1
Save-Memory 'p00.4-web-before.json'

Wait-ForPhase 'initial-loaded'
Copy-RenderedPng $initialPng 'p00.4-web-open.png'
Save-Memory 'p00.4-web-open.json'

Wait-ForPhase 'mhtml-loaded'
Copy-RenderedPng $mhtmlPng 'p00.4-web-mhtml-opened.png'
Save-Memory 'p00.4-web-mhtml-open.json'

Wait-ForPhase 'webview-destroyed'
Start-Sleep -Seconds 2
Save-Memory 'p00.4-web-destroyed.json'
Start-Sleep -Seconds 30
Save-Memory 'p00.4-web-destroyed-30s.json'

Stop-Process -Id $process.Id -Force
Start-Sleep -Seconds 3
$remaining = Get-Process -Id $process.Id -ErrorAction SilentlyContinue
Write-Output "probe_process_after_close=$($null -ne $remaining)"
