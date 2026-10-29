$ErrorActionPreference = 'Stop'

$root = 'E:\alula_code'
$diagnostics = Join-Path $root 'docs\diagnostics\2026-10-28-p00'
$runTag = (Get-Date).ToString('yyyyMMdd-HHmmssfff')
$profile = Join-Path $root "app\build\p00.4-code-oss-rust-idle-profile-$runTag"
$extensions = Join-Path $root "app\build\p00.4-code-oss-rust-idle-extensions-$runTag"
$sharedData = Join-Path $root "app\build\p00.4-code-oss-rust-idle-shared-$runTag"
$fixtureSource = Join-Path $root 'tests\fixtures\rust-mini'
$fixture = Join-Path $root "app\build\p00.4-code-oss-rust-idle-fixture-$runTag"
$referenceRoot = 'E:\_alula_vscode_ref_4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e'
$referenceCommit = '4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e'
$code = Join-Path $referenceRoot '.build\electron\Code - OSS.exe'
$extensionSource = Join-Path $env:USERPROFILE '.vscode\extensions\rust-lang.rust-analyzer-0.3.3089-win32-x64'
$rustAnalyzer = Join-Path $env:USERPROFILE '.cargo\bin\rust-analyzer.exe'
$outJson = Join-Path $diagnostics "p00.4-windows-code-oss-rust-lsp-idle-$runTag.json"
$outMarkdown = Join-Path $diagnostics "p00.4-windows-code-oss-rust-lsp-idle-$runTag.md"
$runLog = Join-Path $diagnostics "p00.4-windows-code-oss-rust-lsp-idle-$runTag.log"
$launcher = Join-Path $profile 'launch-code-oss.cmd'
$durationSeconds = 600
$intervalMilliseconds = 1000
$rootPid = 0
trap {
  $failureText = $_.ToString()
  try {
    [System.IO.File]::AppendAllText($runLog, "failed=$failureText`n", [System.Text.UTF8Encoding]::new($false))
    $logRoots = @((Join-Path $profile 'logs'), (Join-Path $profile 'User\logs'))
    foreach ($logRoot in $logRoots) {
      if (Test-Path -LiteralPath $logRoot) {
        $copyRoot = Join-Path $diagnostics "p00.4-code-oss-startup-logs-$runTag"
        New-Item -ItemType Directory -Path $copyRoot -Force | Out-Null
        Copy-Item -LiteralPath $logRoot -Destination $copyRoot -Recurse -Force
      }
    }
  } catch {}
  try {
    if ($rootPid -gt 0) { Stop-Tree $rootPid }
    else {
      $failedRoots = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -eq 'Code - OSS.exe' -and $_.ExecutablePath -eq $code -and $_.CommandLine -like "*--user-data-dir=$profile*"
      })
      foreach ($failedRoot in $failedRoots) { Stop-Tree ([int]$failedRoot.ProcessId) }
    }
  } catch {}
  foreach ($path in @($profile, $extensions, $sharedData, $fixture)) {
    Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
  }
  throw
}

if (!(Test-Path -LiteralPath $code)) { throw "Pinned Code-OSS executable not found: $code" }
if (!(Test-Path -LiteralPath $extensionSource)) { throw "Installed Rust Analyzer extension not found: $extensionSource" }
if (!(Test-Path -LiteralPath $fixtureSource)) { throw "Rust fixture not found: $fixtureSource" }
if (!(Test-Path -LiteralPath $rustAnalyzer)) { throw "Rust Analyzer server not found: $rustAnalyzer" }
if ((Test-Path -LiteralPath $outJson) -or (Test-Path -LiteralPath $outMarkdown)) { throw 'Refusing to overwrite an existing report' }
if (Test-Path -LiteralPath $runLog) { throw "Refusing to overwrite run log: $runLog" }
$actualReferenceCommit = (& git -C $referenceRoot rev-parse HEAD).Trim()
if ($actualReferenceCommit -ne $referenceCommit) { throw "Pinned source checkout changed: $actualReferenceCommit" }
$referencePackage = Get-Content -LiteralPath (Join-Path $referenceRoot 'package.json') -Raw | ConvertFrom-Json
if ($referencePackage.version -ne '1.145.0') { throw "Unexpected Code-OSS version: $($referencePackage.version)" }
$extensionManifest = Get-Content -LiteralPath (Join-Path $extensionSource 'package.json') -Raw | ConvertFrom-Json
if ("$($extensionManifest.publisher).$($extensionManifest.name)@$($extensionManifest.version)" -ne 'rust-lang.rust-analyzer@0.3.3089') { throw 'Unexpected Rust Analyzer extension package.' }
$rustAnalyzerVersion = (& $rustAnalyzer --version | Select-Object -First 1).Trim()
if ($rustAnalyzerVersion -notmatch '^rust-analyzer 1\.97\.1(\s|$)') { throw "Unexpected rust-analyzer server: $rustAnalyzerVersion" }
New-Item -ItemType Directory -Path (Join-Path $profile 'User'), $extensions, $sharedData, $fixture -Force | Out-Null
$extensionDestination = Join-Path $extensions (Split-Path -Leaf $extensionSource)
Copy-Item -LiteralPath $extensionSource -Destination $extensionDestination -Recurse
$fixturePrefix = $fixtureSource.TrimEnd('\') + '\'
foreach ($file in @(Get-ChildItem -LiteralPath $fixtureSource -Recurse -File | Where-Object {
  $_.FullName -notmatch '[\\/]target[\\/]' -and $_.FullName -notmatch '[\\/]\.git[\\/]'
})) {
  $relative = $file.FullName.Substring($fixturePrefix.Length)
  $destination = Join-Path $fixture $relative
  $destinationDir = Split-Path -Parent $destination
  New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
  Copy-Item -LiteralPath $file.FullName -Destination $destination
}
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
$codeExeHash = (Get-FileHash -LiteralPath $code -Algorithm SHA256).Hash
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
$env:VSCODE_SKIP_PRELAUNCH = '1'
$shell = New-Object -ComObject WScript.Shell
$shell.CurrentDirectory = $referenceRoot
$arguments = @('--new-window', "--user-data-dir=$profile", "--extensions-dir=$extensions", "--shared-data-dir=$sharedData", '--disable-telemetry', '--disable-workspace-trust', $fixture)
$quotedArguments = @($arguments | ForEach-Object { '"' + $_.Replace('"', '\"') + '"' })
$codeBatch = Join-Path $referenceRoot 'scripts\code.bat'
$launchLines = @(
  '@echo off',
  'set VSCODE_SKIP_PRELAUNCH=1',
  "cd /d `"$referenceRoot`"",
  "call `"$codeBatch`" $($quotedArguments -join ' ')"
)
[System.IO.File]::WriteAllLines($launcher, [string[]]$launchLines, [System.Text.Encoding]::ASCII)
$commandLine = 'cmd.exe /d /c ' + $launcher
[void]$shell.Run($commandLine, 1, $false) # SW_SHOWNORMAL; the guard restores the previous foreground immediately.
Start-Sleep -Milliseconds 500
$rootNodes = @(Get-CimInstance -ClassName Win32_Process | Where-Object {
  $_.Name -eq 'Code - OSS.exe' -and $_.ExecutablePath -eq $code -and $_.CommandLine -like "*--new-window*" -and $_.CommandLine -like "*--user-data-dir=$profile*"
})
if ($rootNodes.Count -eq 0) { throw 'Could not locate the isolated pinned Code-OSS root process.' }
$rootPid = [int]$rootNodes[0].ProcessId
$focusStayedStable = $true
$focusRecoveryEvents = New-Object System.Collections.ArrayList
$startupStartedAt = [DateTime]::UtcNow
$startupDeadline = $startupStartedAt.AddSeconds(180)
$rendererDeadline = $startupStartedAt.AddSeconds(30)
$startupRustAnalyzerSeen = $false
$startupRendererSeen = $false
$lastStartupLogAt = -10
while ([DateTime]::UtcNow -lt $startupDeadline) {
  Restore-IsolatedForeground
  $startupNodes = @(Get-TreeNodes $rootPid)
  $startupItems = @(Get-TreeMemory $rootPid)
  if ($startupItems.Count -eq 0) { throw 'Pinned Code-OSS process tree exited before Rust Analyzer started.' }
  $startupRendererCount = @($startupNodes | Where-Object { $_.CommandLine -match '--type=renderer' }).Count
  $startupRendererSeen = $startupRendererSeen -or ($startupRendererCount -gt 0)
  if (@($startupItems | Where-Object { $_.name -eq 'rust-analyzer.exe' }).Count -gt 0) {
    $startupRustAnalyzerSeen = $true
    break
  }
  $startupElapsed = [int][Math]::Floor(([DateTime]::UtcNow - $startupStartedAt).TotalSeconds)
  if ($startupElapsed -ge ($lastStartupLogAt + 10)) {
    $startupLine = "startup_s=$startupElapsed processes=$($startupItems.Count) renderer_processes=$startupRendererCount rust_analyzer=0"
    [System.IO.File]::AppendAllText($runLog, "$startupLine`n", [System.Text.UTF8Encoding]::new($false))
    Write-Output $startupLine
    $lastStartupLogAt = $startupElapsed
  }
  if (!$startupRendererSeen -and [DateTime]::UtcNow -ge $rendererDeadline) {
    throw 'Code-OSS did not start a workbench renderer within 30 seconds.'
  }
  Start-Sleep -Seconds 1
}
if (!$startupRustAnalyzerSeen) { throw 'Rust Analyzer did not appear in the isolated Code-OSS process tree within 180 seconds.' }

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
$isolatedDataCleaned = $true
foreach ($path in @($profile, $extensions, $sharedData, $fixture)) {
  try { Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop }
  catch { $isolatedDataCleaned = $false }
  if (Test-Path -LiteralPath $path) { $isolatedDataCleaned = $false }
}

$report = [ordered]@{
  label = 'code-oss-rust-lsp-idle-10min'
  product = 'Code-OSS 1.145.0-dev pinned commit 4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e'
  exe = $code
  source_commit = $actualReferenceCommit
  source_version = [string]$referencePackage.version
  source_electron_version = [string]$referencePackage.devDependencies.electron
  executable_sha256 = $codeExeHash
  launch_method = 'upstream scripts/code.bat with VSCODE_SKIP_PRELAUNCH=1; isolated user-data/extensions/shared-data paths'
  extension = 'rust-lang.rust-analyzer 0.3.3089'
  extension_package_sha256 = $extensionPackageHash
  rust_analyzer_server = "$rustAnalyzer ($rustAnalyzerVersion)"
  isolated_settings_sha256 = $settingsHash
  args = @('--new-window', "--user-data-dir=$profile", "--extensions-dir=$extensions", "--shared-data-dir=$sharedData", '--disable-telemetry', '--disable-workspace-trust', $fixture)
  rust_analyzer_observed = $rustAnalyzerObserved
  rust_analyzer_process_paths = $rustAnalyzerPaths
  fixture = $fixture
  isolated_profile = $profile
  isolated_extensions = $extensions
  isolated_shared_data = $sharedData
  isolated_data_cleaned = $isolatedDataCleaned
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
  '# Memory sample: pinned-code-oss-rust-lsp-idle-10min',
  '',
  '- Product: fixed Code-OSS 1.145.0-dev at commit 4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e, launched from the reproducible Windows dev build.',
  '- Runtime: Windows process-tree Private Bytes; isolated user-data, copied rust-analyzer-only extensions, shared-data, and rust-mini fixture; telemetry/updates disabled; no account sign-in or sync.',
  "- Language service: $($report.extension), configured to use $rustAnalyzerVersion at $rustAnalyzer.",
  "- Rust Analyzer observed in the process tree: $rustAnalyzerObserved; executable paths: $($rustAnalyzerPaths -join ', ').",
  "- Sampling: target $durationSeconds one-second samples; collected $($samples.Count) over $([Math]::Round($actualSamplingElapsed, 1)) seconds; sample span $([Math]::Round($actualSamplingSpan, 1)) seconds and median interval $([Math]::Round($medianSampleInterval, 3)) seconds.",
  "- Stable method: sort Private Bytes only within the chronological last $tailCount samples (beginning at t=$([Math]::Round($tailStartTime, 3)) s) and select the upper-middle value, matching tools/mem-probe::summarize.",
  "- Foreground window stayed unchanged: $focusStayedStable; isolated-window foreground recoveries: $($focusRecoveryEvents.Count).",
  '- If isolated Code-OSS briefly became foreground, the runner restored the prior foreground, minimized the isolated window without activation, and continued only after confirming focus had moved away.',
  '',
  '| Metric | Private (MiB) | Working Set (MiB) |',
  '|---|---:|---:|',
  "| Peak | $([Math]::Round($peakPrivate / $miB, 2)) | - |",
  "| Stable (chronological tail upper-middle) | $([Math]::Round($stable / $miB, 2)) | - |",
  "| Final | $([Math]::Round($finalPrivate / $miB, 2)) | $([Math]::Round($finalWorkingSet / $miB, 2)) |",
  '',
  "Close check after 30 seconds: all recorded PIDs exited = $($closeCheck.all_recorded_pids_exited).",
  '',
  'Limits: This is a fixed-version Code-OSS idle sample with rust-analyzer active. It is not an editing workload, complete feature-set comparison, or full docs/04 product memory matrix.'
)
[System.IO.File]::WriteAllLines($outMarkdown, [string[]]$lines, [System.Text.UTF8Encoding]::new($false))
$summaryLine = "complete samples=$($samples.Count) peak_mib=$([Math]::Round($peakPrivate / $miB, 1)) stable_mib=$([Math]::Round($stable / $miB, 1)) final_mib=$([Math]::Round($finalPrivate / $miB, 1)) foreground_unchanged=$focusStayedStable foreground_recoveries=$($focusRecoveryEvents.Count) close_exited=$($closeCheck.all_recorded_pids_exited) isolated_data_cleaned=$isolatedDataCleaned"
[System.IO.File]::AppendAllText($runLog, "$summaryLine`njson=$outJson`nmarkdown=$outMarkdown`n", [System.Text.UTF8Encoding]::new($false))
Write-Output "JSON report: $outJson"
Write-Output "Markdown report: $outMarkdown"
Write-Output "Run log: $runLog"
Write-Output "Summary: $summaryLine"
