$ErrorActionPreference = 'Stop'

$root = 'E:\alula_code'
$runTag = (Get-Date).ToString('yyyyMMdd-HHmmssfff')
$profile = Join-Path $root "app\build\p00.4-vscode-rust-idle-profile-$runTag"
$extensions = Join-Path $root "app\build\p00.4-vscode-rust-idle-extensions-$runTag"
$sharedData = Join-Path $root "app\build\p00.4-vscode-rust-idle-shared-$runTag"
$fixture = Join-Path $root 'tests\fixtures\rust-mini'
$code = Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\Code.exe'
$extensionSource = Join-Path $env:USERPROFILE '.vscode\extensions\rust-lang.rust-analyzer-0.3.3089-win32-x64'
$rustAnalyzer = Join-Path $env:USERPROFILE '.cargo\bin\rust-analyzer.exe'
$outJson = Join-Path $root "docs\diagnostics\2026-10-28-p00\p00.4-windows-vscode-rust-lsp-idle-rerun3-$runTag.json"
$outMarkdown = Join-Path $root "docs\diagnostics\2026-10-28-p00\p00.4-windows-vscode-rust-lsp-idle-rerun3-$runTag.md"
$runLog = Join-Path $root "docs\diagnostics\2026-10-28-p00\p00.4-windows-vscode-rust-lsp-idle-$runTag.log"
$durationSeconds = 600
$intervalMilliseconds = 1000
$rootPid = 0

if (!(Test-Path $code)) { throw "VS Code executable not found: $code" }
if (!(Test-Path $extensionSource)) { throw "Installed Rust Analyzer extension not found: $extensionSource" }
if (!(Test-Path $rustAnalyzer)) { throw "Rust Analyzer server not found: $rustAnalyzer" }
if (!(Test-Path $fixture)) { throw "Rust fixture not found: $fixture" }
if ((Test-Path $outJson) -or (Test-Path $outMarkdown)) { throw 'Refusing to overwrite an existing report' }
if (Test-Path $runLog) { throw "Refusing to overwrite run log: $runLog" }
$extensionManifest = Get-Content -LiteralPath (Join-Path $extensionSource 'package.json') -Raw | ConvertFrom-Json
if ("$($extensionManifest.publisher).$($extensionManifest.name)@$($extensionManifest.version)" -ne 'rust-lang.rust-analyzer@0.3.3089') { throw 'Unexpected Rust Analyzer extension package.' }
$rustAnalyzerVersion = (& $rustAnalyzer --version | Select-Object -First 1).Trim()
if ($rustAnalyzerVersion -notmatch '^rust-analyzer 1\.97\.1(\s|$)') { throw "Unexpected rust-analyzer server: $rustAnalyzerVersion" }
$codeVersion = (Get-Item -LiteralPath $code).VersionInfo.ProductVersion
if ($codeVersion -ne '1.142.0') { throw "Unexpected Microsoft VS Code version: $codeVersion" }

trap {
  $failureText = $_.ToString()
  try { [System.IO.File]::AppendAllText($runLog, "failed=$failureText`n", [System.Text.UTF8Encoding]::new($false)) } catch {}
  try {
    if ($rootPid -gt 0) { Stop-Tree $rootPid }
    else {
      $failedRoots = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -eq 'Code.exe' -and $_.CommandLine -like "*--user-data-dir=$profile*"
      })
      foreach ($failedRoot in $failedRoots) { Stop-Tree ([int]$failedRoot.ProcessId) }
    }
  } catch {}
  foreach ($path in @($profile, $extensions, $sharedData)) {
    Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
  }
  throw
}

New-Item -ItemType Directory -Path (Join-Path $profile 'User'), $extensions, $sharedData -Force | Out-Null
$extensionDestination = Join-Path $extensions (Split-Path -Leaf $extensionSource)
Copy-Item -LiteralPath $extensionSource -Destination $extensionDestination -Recurse
$settings = [ordered]@{
  'telemetry.telemetryLevel' = 'off'
  'update.mode' = 'none'
  'extensions.autoUpdate' = $false
  'extensions.autoCheckUpdates' = $false
  'security.workspace.trust.enabled' = $false
  'rust-analyzer.server.path' = $rustAnalyzer
}
$settingsPath = Join-Path (Join-Path $profile 'User') 'settings.json'
[System.IO.File]::WriteAllText($settingsPath, ($settings | ConvertTo-Json -Depth 4), [System.Text.UTF8Encoding]::new($false))
$extensionPackageHash = (Get-FileHash -LiteralPath (Join-Path $extensionDestination 'package.json') -Algorithm SHA256).Hash
$settingsHash = (Get-FileHash -LiteralPath $settingsPath -Algorithm SHA256).Hash

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class P00Window {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int command);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
  [DllImport("user32.dll")] public static extern void keybd_event(byte key, byte scan, uint flags, UIntPtr extra);
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
  return $items
}

function Stop-Tree([int] $RootPid) {
  $nodes = @(Get-TreeNodes $RootPid)
  $ordered = @($nodes | Where-Object { [int]$_.ProcessId -ne $RootPid }) + @($nodes | Where-Object { [int]$_.ProcessId -eq $RootPid })
  foreach ($node in $ordered) {
    Stop-Process -Id ([int]$node.ProcessId) -Force -ErrorAction SilentlyContinue
  }
}

function Get-IsolatedWindowHandles([int] $RootPid) {
  $handles = @()
  foreach ($node in @(Get-TreeNodes $RootPid)) {
    $process = Get-Process -Id ([int]$node.ProcessId) -ErrorAction SilentlyContinue
    if ($process -and $process.MainWindowHandle -ne 0) {
      $handles += [long]$process.MainWindowHandle
    }
  }
  return @($handles | Sort-Object -Unique)
}

function Restore-IsolatedForeground {
  $handles = @(Get-IsolatedWindowHandles $rootPid)
  $foreground = [P00Window]::GetForegroundWindow()
  if ($handles -notcontains $foreground.ToInt64()) { return }

  $capturedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss.fff UTC')
  if ($foregroundBefore -eq [IntPtr]::Zero -or ![P00Window]::IsWindow($foregroundBefore)) {
    Stop-Tree $rootPid
    throw 'The isolated VS Code window became foreground, but the prior foreground window no longer exists; stopped the isolated run.'
  }

  [void][P00Window]::SetForegroundWindow($foregroundBefore)
  foreach ($handle in $handles) {
    [void][P00Window]::ShowWindow([IntPtr]$handle, 6) # SW_MINIMIZE, yielding activation to the previous window.
  }
  Start-Sleep -Milliseconds 50
  if ([P00Window]::GetForegroundWindow() -ne $foregroundBefore) {
    $previousForegroundProcessId = [uint32]0
    [void][P00Window]::GetWindowThreadProcessId($foregroundBefore, [ref]$previousForegroundProcessId)
    [P00Window]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero) # Alt permits foreground activation on Windows.
    try {
      if ($previousForegroundProcessId -ne 0) { [void]$shell.AppActivate([int]$previousForegroundProcessId) }
      [void][P00Window]::BringWindowToTop($foregroundBefore)
      [void][P00Window]::SetForegroundWindow($foregroundBefore)
      Start-Sleep -Milliseconds 50
    } finally {
      [P00Window]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)
    }
  }
  $restoredForeground = [P00Window]::GetForegroundWindow()
  if ($restoredForeground -ne $foregroundBefore) {
    Stop-Tree $rootPid
    throw 'Could not move the isolated VS Code window behind the prior foreground window; stopped the isolated run.'
  }

  [void]$focusRecoveryEvents.Add([pscustomobject]@{
    captured_at_utc = $capturedAt
    isolated_foreground_hwnd = $foreground.ToInt64()
    restored_foreground_hwnd = $restoredForeground.ToInt64()
    restored = $true
  })
}

$foregroundBefore = [P00Window]::GetForegroundWindow()
$startedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss UTC')
[System.IO.File]::WriteAllText($runLog, "started_at=$startedAt`n", [System.Text.UTF8Encoding]::new($false))
$arguments = @('--new-window', "--user-data-dir=$profile", "--extensions-dir=$extensions", "--shared-data-dir=$sharedData", '--disable-telemetry', '--disable-workspace-trust', $fixture)
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
$focusRecoveryEvents = New-Object System.Collections.ArrayList
$startupDeadline = [DateTime]::UtcNow.AddSeconds(5)
while ([DateTime]::UtcNow -lt $startupDeadline) {
  Restore-IsolatedForeground
  Start-Sleep -Milliseconds 25
}

$timer = [System.Diagnostics.Stopwatch]::StartNew()
$samples = @()
$observedPids = @()
$rustAnalyzerPaths = @()
$rustAnalyzerObserved = $false
for ($i = 0; $i -lt $durationSeconds; $i++) {
  Restore-IsolatedForeground
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
  if ((($i + 1) % 60) -eq 0 -or $i -eq ($durationSeconds - 1)) {
    $progressLine = "samples=$($i + 1)/$durationSeconds elapsed_s=$([Math]::Round($timer.Elapsed.TotalSeconds, 1)) private_bytes=$totalPrivate processes=$($items.Count) foreground_recoveries=$($focusRecoveryEvents.Count)"
    [System.IO.File]::AppendAllText($runLog, "$progressLine`n", [System.Text.UTF8Encoding]::new($false))
    Write-Output $progressLine
  }
  if ($i -lt ($durationSeconds - 1)) {
    $remaining = $intervalMilliseconds - [int]$sampleStart.ElapsedMilliseconds
    if ($remaining -gt 0) { Start-Sleep -Milliseconds $remaining }
  }
}
Restore-IsolatedForeground

$focusStayedStable = ($focusRecoveryEvents.Count -eq 0)
$sampleIntervals = @()
for ($sampleIndex = 1; $sampleIndex -lt $samples.Count; $sampleIndex++) {
  $sampleIntervals += [double]$samples[$sampleIndex].t - [double]$samples[$sampleIndex - 1].t
}
$sortedSampleIntervals = @($sampleIntervals | Sort-Object)
$intervalMiddle = [int][Math]::Floor($sortedSampleIntervals.Count / 2)
$medianSampleInterval = if (($sortedSampleIntervals.Count % 2) -eq 0) {
  ($sortedSampleIntervals[$intervalMiddle - 1] + $sortedSampleIntervals[$intervalMiddle]) / 2.0
} else {
  $sortedSampleIntervals[$intervalMiddle]
}
$actualSamplingSpan = [double]$samples[-1].t - [double]$samples[0].t
$actualSamplingElapsed = [double]$timer.Elapsed.TotalSeconds
$finalItems = @(Get-TreeMemory $rootPid)
$tailCount = [int][Math]::Ceiling($samples.Count * 2.0 / 5.0)
$tailStart = $samples.Count - $tailCount
$tailStartTime = [double]$samples[$tailStart].t
$tailPrivateValues = @($samples[$tailStart..($samples.Count - 1)] | ForEach-Object { [long]$_.total_private })
$sortedTailPrivateValues = @($tailPrivateValues | Sort-Object)
# Match mem-probe::summarize: chronological last ceil(2*n/5), then upper-middle.
$middle = [int][Math]::Floor($sortedTailPrivateValues.Count / 2)
$stable = [long]$sortedTailPrivateValues[$middle]
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
  run_tag = $runTag
  product = "Microsoft VS Code $codeVersion Stable"
  exe = $code
  args = @('--new-window', "--user-data-dir=$profile", "--extensions-dir=$extensions", "--shared-data-dir=$sharedData", '--disable-telemetry', '--disable-workspace-trust', $fixture)
  extension = 'rust-lang.rust-analyzer 0.3.3089'
  rust_analyzer_server = 'C:\Users\Vegetable\.cargo\bin\rust-analyzer.exe (rust-analyzer 1.97.1)'
  rust_analyzer_server_version = $rustAnalyzerVersion
  extension_package_sha256 = $extensionPackageHash
  isolated_settings_sha256 = $settingsHash
  rust_analyzer_observed = $rustAnalyzerObserved
  rust_analyzer_process_paths = $rustAnalyzerPaths
  fixture = $fixture
  isolated_profile = $profile
  isolated_extensions = $extensions
  isolated_shared_data = $sharedData
  telemetry_disabled = $true
  automatic_updates_disabled_by_profile_setting = $true
  duration_s = [Math]::Round($actualSamplingElapsed, 3)
  target_sample_count = $durationSeconds
  interval_s = 1.0
  actual_sampling_span_s = [Math]::Round($actualSamplingSpan, 3)
  actual_median_sample_interval_s = [Math]::Round($medianSampleInterval, 3)
  root_pid = $rootPid
  captured_at = $startedAt
  foreground_stayed_stable = $focusStayedStable
  focus_recovery_events = @($focusRecoveryEvents.ToArray())
  samples = $samples
  final_processes = $finalItems
  summary = [ordered]@{
    peak_private = $peakPrivate
    stable_private = $stable
    stable_method = 'upper-middle of Private Bytes values from chronological last ceil(2*n/5) samples, matching tools/mem-probe::summarize'
    stable_tail_sample_count = $tailCount
    stable_tail_start_sample_index = $tailStart
    stable_tail_start_t_s = $tailStartTime
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
  "- Product: Microsoft VS Code $codeVersion Stable; comparison only, not the pinned Code-OSS 1.145.0 reference.",
  '- Runtime: Windows process-tree Private Bytes; minimized window; isolated user-data, extension, and shared-data directories; telemetry and automatic updates disabled; no account sign-in or sync.',
  "- Language service: $($report.extension), configured to use the same rust-analyzer 1.97.1 executable as Alula.",
  "- Rust Analyzer observed in the process tree: $rustAnalyzerObserved; executable paths: $($rustAnalyzerPaths -join ', ').",
  "- Sampling: target $durationSeconds one-second samples; collected $($samples.Count) over $([Math]::Round($actualSamplingElapsed, 1)) seconds; sample span $([Math]::Round($actualSamplingSpan, 1)) seconds and median interval $([Math]::Round($medianSampleInterval, 3)) seconds.",
  "- Stable method: sort Private Bytes only within the chronological last $tailCount samples (beginning at t=$([Math]::Round($tailStartTime, 3)) s) and select the upper-middle value, matching tools/mem-probe::summarize.",
  "- Foreground window stayed unchanged: $focusStayedStable; isolated-window foreground recoveries: $($focusRecoveryEvents.Count).",
  '- If isolated VS Code briefly became foreground, the runner restored the prior foreground, minimized the isolated window without activation, and continued only after confirming focus had moved away.',
  '',
  '| Metric | Private (MiB) | Working Set (MiB) |',
  '|---|---:|---:|',
  "| Peak | $([Math]::Round($peakPrivate / $miB, 2)) | - |",
  "| Stable (chronological tail upper-middle) | $([Math]::Round($stable / $miB, 2)) | - |",
  "| Final | $([Math]::Round($finalPrivate / $miB, 2)) | $([Math]::Round($finalWorkingSet / $miB, 2)) |",
  '',
  "Close check after 30 seconds: all recorded PIDs exited = $($closeCheck.all_recorded_pids_exited).",
  '',
  'Limits: This is a local same-rust-analyzer supplementary comparison on VS Code 1.142.0 Stable. The pinned reference is Code-OSS 1.145.0-dev; this run is not a version-matched or full-feature-set VS Code comparison.'
)
[System.IO.File]::WriteAllLines($outMarkdown, [string[]]$lines, [System.Text.UTF8Encoding]::new($false))
$summaryLine = "complete samples=$($samples.Count) peak_mib=$([Math]::Round($peakPrivate / $miB, 1)) stable_mib=$([Math]::Round($stable / $miB, 1)) final_mib=$([Math]::Round($finalPrivate / $miB, 1)) foreground_unchanged=$focusStayedStable foreground_recoveries=$($focusRecoveryEvents.Count) close_exited=$($closeCheck.all_recorded_pids_exited)"
[System.IO.File]::AppendAllText($runLog, "$summaryLine`njson=$outJson`nmarkdown=$outMarkdown`n", [System.Text.UTF8Encoding]::new($false))
foreach ($path in @($profile, $extensions, $sharedData)) {
  Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Output "JSON report: $outJson"
Write-Output "Markdown report: $outMarkdown"
Write-Output "Run log: $runLog"
Write-Output "Summary: $summaryLine"
