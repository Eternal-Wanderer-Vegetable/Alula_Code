$ErrorActionPreference = 'Stop'

$root = 'E:\alula_code'
$profile = Join-Path $root 'app\build\p00.4-vscode-rust-idle-profile'
$extensions = Join-Path $root 'app\build\p00.4-vscode-rust-idle-extensions'
$fixture = Join-Path $root 'tests\fixtures\rust-mini'
$code = Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\Code.exe'
$outJson = Join-Path $root 'docs\diagnostics\2026-10-28-p00\p00.4-windows-vscode-rust-lsp-idle.json'
$outMarkdown = Join-Path $root 'docs\diagnostics\2026-10-28-p00\p00.4-windows-vscode-rust-lsp-idle.md'
$durationSeconds = 600
$intervalMilliseconds = 1000

if (!(Test-Path $code)) { throw "VS Code executable not found: $code" }
if (!(Test-Path $profile)) { throw "Isolated user-data directory not found: $profile" }
if (!(Test-Path $extensions)) { throw "Isolated extension directory not found: $extensions" }
if (!(Test-Path $fixture)) { throw "Rust fixture not found: $fixture" }
if ((Test-Path $outJson) -or (Test-Path $outMarkdown)) { throw 'Refusing to overwrite an existing report' }

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class P00Window {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
}
"@

function Get-TreeNodes([int] $RootPid) {
  $all = @(Get-CimInstance -ClassName Win32_Process)
  $ids = @($RootPid)
  do {
    $previousCount = $ids.Count
    $children = @($all | Where-Object { $ids -contains [int]$_.ParentProcessId } | ForEach-Object { [int]$_.ProcessId })
    $ids = @($ids + $children | Sort-Object -Unique)
  } while ($ids.Count -gt $previousCount)
  return @($all | Where-Object { $ids -contains [int]$_.ProcessId })
}

function Get-TreeMemory([int] $RootPid) {
  $nodes = @(Get-TreeNodes $RootPid)
  $items = @()
  foreach ($node in $nodes) {
    $process = Get-Process -Id ([int]$node.ProcessId) -ErrorAction SilentlyContinue
    if ($process) {
      $items += [pscustomobject]@{
        pid = [int]$node.ProcessId
        ppid = [int]$node.ParentProcessId
        name = [string]$node.Name
        executable_path = [string]$node.ExecutablePath
        private = [long]$process.PrivateMemorySize64
        working_set = [long]$process.WorkingSet64
      }
    }
  }
  return ,$items
}

function Stop-Tree([int] $RootPid) {
  $nodes = @(Get-TreeNodes $RootPid)
  $ordered = @($nodes | Where-Object { [int]$_.ProcessId -ne $RootPid }) + @($nodes | Where-Object { [int]$_.ProcessId -eq $RootPid })
  foreach ($node in $ordered) {
    Stop-Process -Id ([int]$node.ProcessId) -Force -ErrorAction SilentlyContinue
  }
}

$foregroundBefore = [P00Window]::GetForegroundWindow()
$startedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss UTC')
$arguments = @('--new-window', "--user-data-dir=$profile", "--extensions-dir=$extensions", '--disable-workspace-trust', $fixture)
$quotedArguments = @($arguments | ForEach-Object { '"' + $_.Replace('"', '\"') + '"' })
$commandLine = '"' + $code + '" ' + ($quotedArguments -join ' ')
$shell = New-Object -ComObject WScript.Shell
[void]$shell.Run($commandLine, 7, $false) # SW_SHOWMINNOACTIVE: minimized without activation.
Start-Sleep -Milliseconds 500
$rootNodes = @(Get-CimInstance -ClassName Win32_Process | Where-Object {
  $_.Name -eq 'Code.exe' -and $_.CommandLine -like "*--new-window*" -and $_.CommandLine -like "*--user-data-dir=$profile*"
})
if ($rootNodes.Count -eq 0) { throw 'Could not locate the isolated VS Code root process.' }
$rootPid = [int]$rootNodes[0].ProcessId
$focusStayedStable = $true
for ($i = 0; $i -lt 50; $i++) {
  Start-Sleep -Milliseconds 100
  if ([P00Window]::GetForegroundWindow() -ne $foregroundBefore) {
    $focusStayedStable = $false
    [void][P00Window]::SetForegroundWindow($foregroundBefore)
    break
  }
}
if (!$focusStayedStable) {
  Stop-Tree $rootPid
  throw 'Aborted: minimized VS Code changed the foreground window; the prior foreground was restored.'
}

$timer = [System.Diagnostics.Stopwatch]::StartNew()
$samples = @()
$observedPids = @()
$rustAnalyzerPaths = @()
$rustAnalyzerObserved = $false
for ($i = 0; $i -lt $durationSeconds; $i++) {
  $sampleStart = [System.Diagnostics.Stopwatch]::StartNew()
  $items = @(Get-TreeMemory $rootPid)
  if ($items.Count -eq 0) { throw "VS Code process tree disappeared at sample $i" }
  $observedPids = @($observedPids + @($items | ForEach-Object { [int]$_.pid }) | Sort-Object -Unique)
  $serviceItems = @($items | Where-Object { $_.name -eq 'rust-analyzer.exe' })
  if ($serviceItems.Count -gt 0) { $rustAnalyzerObserved = $true }
  $rustAnalyzerPaths = @($rustAnalyzerPaths + @($serviceItems | ForEach-Object { $_.executable_path }) | Where-Object { $_ } | Sort-Object -Unique)
  $totalPrivate = [long](($items | Measure-Object -Property private -Sum).Sum)
  $totalWorkingSet = [long](($items | Measure-Object -Property working_set -Sum).Sum)
  $samples += [pscustomobject]@{
    t = [Math]::Round($timer.Elapsed.TotalSeconds, 3)
    total_private = $totalPrivate
    total_working_set = $totalWorkingSet
    n_processes = $items.Count
  }
  if ($i -lt ($durationSeconds - 1)) {
    $remaining = $intervalMilliseconds - [int]$sampleStart.ElapsedMilliseconds
    if ($remaining -gt 0) { Start-Sleep -Milliseconds $remaining }
  }
}

$finalItems = @(Get-TreeMemory $rootPid)
$privateValues = @($samples | ForEach-Object { [double]$_.total_private })
$sorted = @($privateValues | Sort-Object)
$tailStart = [int][Math]::Floor($sorted.Count * 0.6)
$tail = @($sorted[$tailStart..($sorted.Count - 1)])
$stable = ($tail | Measure-Object -Average).Average
# Median of the sorted tail, matching mem-probe's tail-stable definition.
$middle = [int][Math]::Floor($tail.Count / 2)
if (($tail.Count % 2) -eq 0) { $stable = ($tail[$middle - 1] + $tail[$middle]) / 2.0 } else { $stable = $tail[$middle] }
$closePids = @($observedPids + @($finalItems | ForEach-Object { [int]$_.pid }) | Sort-Object -Unique)
$finalPrivate = [long]$samples[-1].total_private
$finalWorkingSet = [long]$samples[-1].total_working_set
$peakPrivate = [long](($samples | Measure-Object -Property total_private -Maximum).Maximum)

Stop-Tree $rootPid
Start-Sleep -Seconds 30
$stillAlive = @()
foreach ($id in $closePids) {
  if (Get-Process -Id $id -ErrorAction SilentlyContinue) { $stillAlive += [int]$id }
}
$closeCheck = [pscustomobject]@{
  wait_seconds = 30
  checked_at = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss UTC')
  all_recorded_pids_exited = ($stillAlive.Count -eq 0)
  still_alive_pids = $stillAlive
}

$report = [ordered]@{
  label = 'vscode-rust-lsp-idle-10min'
  product = 'Microsoft VS Code 1.142.0 Stable'
  exe = $code
  args = @('--new-window', "--user-data-dir=$profile", "--extensions-dir=$extensions", '--disable-workspace-trust', $fixture)
  extension = 'rust-lang.rust-analyzer 0.3.3089'
  rust_analyzer_server = 'C:\Users\Vegetable\.cargo\bin\rust-analyzer.exe (rust-analyzer 1.97.1)'
  rust_analyzer_observed = $rustAnalyzerObserved
  rust_analyzer_process_paths = $rustAnalyzerPaths
  fixture = $fixture
  isolated_profile = $profile
  isolated_extensions = $extensions
  duration_s = [double]$durationSeconds
  interval_s = 1.0
  root_pid = $rootPid
  captured_at = $startedAt
  foreground_stayed_stable = $focusStayedStable
  samples = $samples
  final_processes = $finalItems
  summary = [ordered]@{
    peak_private = $peakPrivate
    stable_private = [long][Math]::Round($stable)
    final_private = $finalPrivate
    final_working_set = $finalWorkingSet
  }
  close_check = $closeCheck
}
$jsonText = $report | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText($outJson, $jsonText, [System.Text.UTF8Encoding]::new($false))
$miB = 1048576.0
$lines = @(
  '# Memory sample: vscode-rust-lsp-idle-10min',
  '',
  '- Product: Microsoft VS Code 1.142.0 Stable; comparison only, not the pinned Code-OSS 1.145.0 reference.',
  '- Runtime: Windows process-tree Private Bytes; minimized window; isolated user-data and extension directories; no account sign-in or sync.',
  "- Language service: $($report.extension), configured to use the same rust-analyzer 1.97.1 executable as Alula.",
  "- Rust Analyzer observed in the process tree: $rustAnalyzerObserved; executable paths: $($rustAnalyzerPaths -join ', ').",
  "- Sampling: $durationSeconds seconds, 1-second interval, $($samples.Count) samples.",
  "- Foreground window stayed unchanged: $focusStayedStable.",
  '',
  '| Metric | Private (MiB) | Working Set (MiB) |',
  '|---|---:|---:|',
  "| Peak | $([Math]::Round($peakPrivate / $miB, 2)) | — |",
  "| Stable (tail 40% median) | $([Math]::Round($stable / $miB, 2)) | — |",
  "| Final | $([Math]::Round($finalPrivate / $miB, 2)) | $([Math]::Round($finalWorkingSet / $miB, 2)) |",
  '',
  "Close check after 30 seconds: all recorded PIDs exited = $($closeCheck.all_recorded_pids_exited).",
  '',
  'Limits: This is a local same-rust-analyzer supplementary comparison on VS Code 1.142.0 Stable. The pinned reference is Code-OSS 1.145.0-dev; this run is not a version-matched or full-feature-set VS Code comparison.'
)
[System.IO.File]::WriteAllLines($outMarkdown, [string[]]$lines, [System.Text.UTF8Encoding]::new($false))
Write-Output "JSON report: $outJson"
Write-Output "Markdown report: $outMarkdown"
Write-Output "Summary: peak $([Math]::Round($peakPrivate / $miB, 1)) MiB / stable $([Math]::Round($stable / $miB, 1)) MiB / final $([Math]::Round($finalPrivate / $miB, 1)) MiB ($($finalItems.Count) processes); foreground unchanged=$focusStayedStable; close+30s exited=$($closeCheck.all_recorded_pids_exited)"
