[CmdletBinding()]
param(
  [switch]$Preflight,
  [ValidateRange(30, 1800)][int]$DurationSeconds = 1800,
  [ValidateRange(2, 60)][int]$EditIntervalSeconds = 12
)

$ErrorActionPreference = 'Stop'

if ($Preflight) {
  $DurationSeconds = 30
  $EditIntervalSeconds = 5
}

$root = 'E:\alula_code'
$diagnostics = Join-Path $root 'docs\diagnostics\2026-10-28-p00'
$runTag = (Get-Date).ToString('yyyyMMdd-HHmmssfff')
$profile = Join-Path $root "app\build\p00.4-code-oss-rust-edit-profile-$runTag"
$extensions = Join-Path $root "app\build\p00.4-code-oss-rust-edit-extensions-$runTag"
$sharedData = Join-Path $root "app\build\p00.4-code-oss-rust-edit-shared-$runTag"
$fixtureSource = Join-Path $root 'tests\fixtures\rust-mini'
$fixture = Join-Path $root "app\build\p00.4-code-oss-rust-edit-fixture-$runTag"
$targetFile = Join-Path $fixture 'src\main.rs'
$referenceRoot = 'E:\_alula_vscode_ref_4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e'
$referenceCommit = '4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e'
$code = Join-Path $referenceRoot '.build\electron\Code - OSS.exe'
$extensionSource = Join-Path $env:USERPROFILE '.vscode\extensions\rust-lang.rust-analyzer-0.3.3089-win32-x64'
$rustAnalyzer = Join-Path $env:USERPROFILE '.cargo\bin\rust-analyzer.exe'
$runKind = if ($Preflight) { 'edit-preflight' } else { 'edit-30m' }
$outJson = Join-Path $diagnostics "p00.4-windows-code-oss-rust-lsp-$runKind-$runTag.json"
$outMarkdown = Join-Path $diagnostics "p00.4-windows-code-oss-rust-lsp-$runKind-$runTag.md"
$runLog = Join-Path $diagnostics "p00.4-windows-code-oss-rust-lsp-$runKind-$runTag.log"
$launcher = Join-Path $profile 'launch-code-oss.cmd'
$intervalMilliseconds = 1000
$expectedSaveCount = [int][Math]::Floor($DurationSeconds / $EditIntervalSeconds)
$driverId = 'local.p00-edit-driver'
$driverVersion = '1.0.0'
$driverExtension = Join-Path $extensions "$driverId-$driverVersion"
$driverConfigPath = Join-Path $driverExtension 'driver-config.json'
$driverStatusPath = Join-Path $driverExtension 'driver-status.json'
$driverEventsPath = Join-Path $driverExtension 'driver-events.jsonl'
$sourceFixtureHashBefore = $null
$rootPid = 0
trap {
  $failureText = $_.ToString()
  try {
    [System.IO.File]::AppendAllText($runLog, "failed=$failureText`n", [System.Text.UTF8Encoding]::new($false))
    foreach ($source in @($driverStatusPath, $driverEventsPath)) {
      if (Test-Path -LiteralPath $source) {
        Copy-Item -LiteralPath $source -Destination (Join-Path $diagnostics ("$runKind-$runTag-" + (Split-Path -Leaf $source))) -Force
      }
    }
    if (Test-Path -LiteralPath $targetFile) {
      Copy-Item -LiteralPath $targetFile -Destination (Join-Path $diagnostics "p00.4-windows-code-oss-edit-failed-$runTag-main.rs") -Force
    }
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
$null = New-Item -ItemType Directory -Path $driverExtension -Force
$driverManifest = [ordered]@{
  name = 'p00-edit-driver'
  displayName = 'P00 Local Edit Driver'
  description = 'Isolated local editor API workload driver for the P00 memory comparison.'
  publisher = 'local'
  version = $driverVersion
  engines = @{ vscode = '^1.80.0' }
  main = './extension.js'
  activationEvents = @('onStartupFinished')
}
[System.IO.File]::WriteAllText((Join-Path $driverExtension 'package.json'), ($driverManifest | ConvertTo-Json -Depth 6), [System.Text.UTF8Encoding]::new($false))
$driverConfig = [ordered]@{
  runTag = $runTag
  targetFile = $targetFile
  statusFile = $driverStatusPath
  eventsFile = $driverEventsPath
  durationSeconds = $DurationSeconds
  editIntervalMs = $EditIntervalSeconds * 1000
  expectedSaveCount = $expectedSaveCount
}
[System.IO.File]::WriteAllText($driverConfigPath, ($driverConfig | ConvertTo-Json -Depth 4), [System.Text.UTF8Encoding]::new($false))
$driverSource = @'
'use strict';

const fs = require('fs');
const vscode = require('vscode');

function writeStatus(file, status) {
  fs.writeFileSync(file, JSON.stringify(status));
}

function delay(ms) {
  return new Promise(resolve => setTimeout(resolve, Math.max(0, ms)));
}

async function run(context) {
  const config = JSON.parse(fs.readFileSync(`${context.extensionPath}/driver-config.json`, 'utf8'));
  const status = { state: 'starting', runTag: config.runTag, completedSaves: 0 };
  writeStatus(config.statusFile, status);
  const uri = vscode.Uri.file(config.targetFile);
  const document = await vscode.workspace.openTextDocument(uri);
  const editor = await vscode.window.showTextDocument(document, { preview: false });
  const startedAt = Date.now();
  Object.assign(status, {
    state: 'running',
    startedAtUtc: new Date(startedAt).toISOString(),
    startedEpochMs: startedAt,
    expectedSaveCount: config.expectedSaveCount,
    durationSeconds: config.durationSeconds,
    editIntervalMs: config.editIntervalMs
  });
  writeStatus(config.statusFile, status);

  for (let index = 1; index <= config.expectedSaveCount; index++) {
    const dueAt = startedAt + (index - 1) * config.editIntervalMs;
    await delay(dueAt - Date.now());
    const marker = `P00_CODE_OSS_API_${config.runTag}_${String(index).padStart(4, '0')}`;
    const original = document.getText();
    const eol = document.eol === vscode.EndOfLine.CRLF ? '\r\n' : '\n';
    const separator = original.endsWith('\n') ? '' : eol;
    const insertion = `${separator}// ${marker}${eol}`;
    const position = document.positionAt(original.length);
    const changed = await editor.edit(builder => builder.insert(position, insertion));
    if (!changed) throw new Error(`TextEditor.edit returned false for ${marker}`);
    const saved = await document.save();
    if (!saved) throw new Error(`TextDocument.save returned false for ${marker}`);
    const diskText = fs.readFileSync(config.targetFile, 'utf8');
    if (!diskText.includes(marker)) throw new Error(`Saved file did not contain ${marker}`);
    const event = {
      index,
      marker,
      dueAtUtc: new Date(dueAt).toISOString(),
      savedAtUtc: new Date().toISOString(),
      elapsedMs: Date.now() - startedAt,
      diskVerified: true
    };
    fs.appendFileSync(config.eventsFile, `${JSON.stringify(event)}\n`);
    status.completedSaves = index;
    status.lastSaveAtUtc = event.savedAtUtc;
    status.lastMarker = marker;
    writeStatus(config.statusFile, status);
  }

  await delay(startedAt + config.durationSeconds * 1000 - Date.now());
  Object.assign(status, {
    state: 'complete',
    completedAtUtc: new Date().toISOString(),
    completedSaves: config.expectedSaveCount
  });
  writeStatus(config.statusFile, status);
}

function activate(context) {
  run(context).catch(error => {
    try {
      const config = JSON.parse(fs.readFileSync(`${context.extensionPath}/driver-config.json`, 'utf8'));
      const status = fs.existsSync(config.statusFile) ? JSON.parse(fs.readFileSync(config.statusFile, 'utf8')) : {};
      Object.assign(status, { state: 'failed', error: String(error), failedAtUtc: new Date().toISOString() });
      writeStatus(config.statusFile, status);
    } catch (_) {}
    console.error('P00 edit driver failed:', error);
  });
}

module.exports = { activate };
'@
[System.IO.File]::WriteAllText((Join-Path $driverExtension 'extension.js'), $driverSource, [System.Text.UTF8Encoding]::new($false))
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
$sourceFixtureHashBefore = (Get-FileHash -LiteralPath (Join-Path $fixtureSource 'src\main.rs') -Algorithm SHA256).Hash
$targetFileHashBefore = (Get-FileHash -LiteralPath $targetFile -Algorithm SHA256).Hash
$codeExeHash = (Get-FileHash -LiteralPath $code -Algorithm SHA256).Hash
$extensionPackageHash = (Get-FileHash -LiteralPath (Join-Path $extensionDestination 'package.json') -Algorithm SHA256).Hash
$driverPackageHash = (Get-FileHash -LiteralPath (Join-Path $driverExtension 'package.json') -Algorithm SHA256).Hash
$driverSourceHash = (Get-FileHash -LiteralPath (Join-Path $driverExtension 'extension.js') -Algorithm SHA256).Hash
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

function Get-DriverStatus {
  if (!(Test-Path -LiteralPath $driverStatusPath)) { return $null }
  try { return (Get-Content -LiteralPath $driverStatusPath -Raw | ConvertFrom-Json) }
  catch { return $null }
}

function Get-DriverEvents {
  if (!(Test-Path -LiteralPath $driverEventsPath)) { return @() }
  $events = @()
  foreach ($line in @(Get-Content -LiteralPath $driverEventsPath -ErrorAction SilentlyContinue)) {
    if (![string]::IsNullOrWhiteSpace($line)) {
      try { $events += ($line | ConvertFrom-Json) } catch {}
    }
  }
  return $events
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
    [P00Window]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero) # A brief Alt event authorizes foreground restoration on Windows.
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
$startupDriverSeen = $false
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
  }
  $driverStatus = Get-DriverStatus
  if ($driverStatus -and $driverStatus.state -eq 'failed') { throw "Local edit driver failed during startup: $($driverStatus.error)" }
  $startupDriverSeen = ($driverStatus -and $driverStatus.state -eq 'running')
  if ($startupRustAnalyzerSeen -and $startupDriverSeen) { break }
  $startupElapsed = [int][Math]::Floor(([DateTime]::UtcNow - $startupStartedAt).TotalSeconds)
  if ($startupElapsed -ge ($lastStartupLogAt + 10)) {
    $startupLine = "startup_s=$startupElapsed processes=$($startupItems.Count) renderer_processes=$startupRendererCount rust_analyzer=$startupRustAnalyzerSeen driver_state=$($driverStatus.state)"
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
if (!$startupDriverSeen) { throw 'The local edit driver did not reach running state within 180 seconds.' }

$timer = [System.Diagnostics.Stopwatch]::StartNew()
$samples = New-Object System.Collections.ArrayList
$processSnapshots = New-Object System.Collections.ArrayList
$observedPids = @()
$rustAnalyzerPaths = @()
$rustAnalyzerObserved = $false
$lastDriverCheckAt = -5.0
$sampleIndex = 0
while ($timer.Elapsed.TotalSeconds -lt $DurationSeconds) {
  Restore-IsolatedForeground
  $sampleStart = [System.Diagnostics.Stopwatch]::StartNew()
  $items = @(Get-TreeMemory $rootPid)
  if ($items.Count -eq 0) { throw "Code-OSS process tree disappeared at sample $sampleIndex" }
  $observedPids = @($observedPids + @($items | ForEach-Object { [int]$_.pid }) | Sort-Object -Unique)
  $serviceItems = @($items | Where-Object { $_.name -eq 'rust-analyzer.exe' })
  if ($serviceItems.Count -gt 0) { $rustAnalyzerObserved = $true }
  $rustAnalyzerPaths = @($rustAnalyzerPaths + @($serviceItems | ForEach-Object { $_.executable_path }) | Where-Object { $_ } | Sort-Object -Unique)
  $totalPrivate = [long](($items | Measure-Object -Property private -Sum).Sum)
  $totalWorkingSet = [long](($items | Measure-Object -Property working_set -Sum).Sum)
  $sampleTime = [Math]::Round($timer.Elapsed.TotalSeconds, 3)
  [void]$samples.Add([pscustomobject]@{
    t = $sampleTime
    total_private = $totalPrivate
    total_working_set = $totalWorkingSet
    n_processes = $items.Count
  })
  if (($sampleIndex % 10) -eq 0) {
    [void]$processSnapshots.Add([pscustomobject]@{ t = $sampleTime; processes = @($items) })
  }
  if (($sampleTime - $lastDriverCheckAt) -ge 5.0) {
    $driverStatus = Get-DriverStatus
    if ($driverStatus -and $driverStatus.state -eq 'failed') {
      throw "Local edit driver failed: $($driverStatus.error)"
    }
    $lastDriverCheckAt = $sampleTime
  }
  if ((($sampleIndex + 1) % 60) -eq 0) {
    $driverStatus = Get-DriverStatus
    $completedSaves = if ($driverStatus) { [int]$driverStatus.completedSaves } else { 0 }
    $progressLine = "samples=$($sampleIndex + 1) elapsed_s=$([Math]::Round($timer.Elapsed.TotalSeconds, 1)) private_mib=$([Math]::Round($totalPrivate / 1048576.0, 1)) processes=$($items.Count) saves=$completedSaves/$expectedSaveCount foreground_recoveries=$($focusRecoveryEvents.Count)"
    [System.IO.File]::AppendAllText($runLog, $progressLine + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
    Write-Output $progressLine
  }
  $sampleIndex++
  $remaining = $intervalMilliseconds - [int]$sampleStart.ElapsedMilliseconds
  if ($remaining -gt 0) { Start-Sleep -Milliseconds $remaining }
}
Restore-IsolatedForeground

$focusStayedStable = ($focusRecoveryEvents.Count -eq 0)
$samples = @($samples.ToArray())
$processSnapshots = @($processSnapshots.ToArray())
$driverStatus = Get-DriverStatus
$saveEvents = @(Get-DriverEvents)
if (!$driverStatus -or $driverStatus.state -ne 'complete') {
  throw "Local edit driver did not complete its requested workload (state=$($driverStatus.state))."
}
if ([int]$driverStatus.completedSaves -ne $expectedSaveCount -or $saveEvents.Count -ne $expectedSaveCount) {
  throw "Expected $expectedSaveCount saved edits, status reports $($driverStatus.completedSaves), event log has $($saveEvents.Count)."
}
if (@($saveEvents | Where-Object { !$_.diskVerified }).Count -gt 0) { throw 'At least one saved edit was not verified on disk.' }
$markerText = [System.IO.File]::ReadAllText($targetFile)
foreach ($event in $saveEvents) {
  if (!$markerText.Contains([string]$event.marker)) { throw "Final fixture is missing saved marker $($event.marker)." }
}
$sourceFixtureHashAfter = (Get-FileHash -LiteralPath (Join-Path $fixtureSource 'src\main.rs') -Algorithm SHA256).Hash
if ($sourceFixtureHashAfter -ne $sourceFixtureHashBefore) { throw 'The source rust-mini fixture changed during the isolated run.' }
$targetFileHashAfter = (Get-FileHash -LiteralPath $targetFile -Algorithm SHA256).Hash
if ($targetFileHashAfter -eq $targetFileHashBefore) { throw 'The isolated fixture did not change during the editing workload.' }
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
$tailSnapshots = @($processSnapshots | Where-Object { [double]$_.t -ge $tailStartTime })
$tailProcessRows = @()
foreach ($snapshot in $tailSnapshots) {
  $snapshotGroups = @($snapshot.processes | Group-Object -Property name, executable_path)
  foreach ($snapshotGroup in $snapshotGroups) {
    $firstProcess = $snapshotGroup.Group[0]
    $identity = "$($firstProcess.name) [$($firstProcess.executable_path)]"
    $tailProcessRows += [pscustomobject]@{
      t = [double]$snapshot.t
      process_identity = $identity
      process_count = $snapshotGroup.Count
      private = [long](($snapshotGroup.Group | Measure-Object -Property private -Sum).Sum)
    }
  }
}
$processBreakdown = @()
$processGroups = @($tailProcessRows | Group-Object -Property process_identity)
foreach ($group in $processGroups) {
  $orderedRows = @($group.Group | Sort-Object -Property t)
  $values = @($orderedRows | ForEach-Object { [long]$_.private } | Sort-Object)
  if ($values.Count -eq 0) { continue }
  $processMiddle = [int][Math]::Floor($values.Count / 2)
  $processBreakdown += [pscustomobject]@{
    process_identity = [string]$group.Name
    observations = $values.Count
    tail_median_private = [long]$values[$processMiddle]
    peak_private = [long](($values | Measure-Object -Maximum).Maximum)
    final_observed_private = [long]$orderedRows[-1].private
    final_process_count = [int]$orderedRows[-1].process_count
  }
}
$processBreakdown = @($processBreakdown | Sort-Object -Property tail_median_private -Descending)
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
  label = if ($Preflight) { 'code-oss-rust-lsp-edit-preflight' } else { 'code-oss-rust-lsp-edit-30min' }
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
  automation_method = 'isolated helper extension using vscode.TextEditor.edit and vscode.TextDocument.save; no global edit keystrokes or CDP; a transient Alt key event may authorize focus restoration'
  helper_extension_id = $driverId
  helper_extension_version = $driverVersion
  helper_extension_package_sha256 = $driverPackageHash
  helper_extension_source_sha256 = $driverSourceHash
  expected_saved_edits = $expectedSaveCount
  actual_saved_edits = $saveEvents.Count
  save_events = $saveEvents
  target_fixture_sha256_before = $targetFileHashBefore
  target_fixture_sha256_after = $targetFileHashAfter
  original_fixture_sha256_before = $sourceFixtureHashBefore
  original_fixture_sha256_after = $sourceFixtureHashAfter
  all_saved_markers_present = $true
  all_saves_verified_on_disk = $true
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
  target_duration_s = $DurationSeconds
  edit_interval_s = $EditIntervalSeconds
  target_sample_count = $samples.Count
  interval_s = 1.0
  actual_sampling_span_s = [Math]::Round($actualSamplingSpan, 3)
  actual_median_sample_interval_s = [Math]::Round($medianSampleInterval, 3)
  root_pid = $rootPid
  captured_at = $startedAt
  foreground_stayed_stable = $focusStayedStable
  focus_recovery_events = @($focusRecoveryEvents.ToArray())
  samples = $samples
  process_snapshots = $processSnapshots
  tail_process_breakdown = $processBreakdown
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
  "# Memory sample: pinned-code-oss-rust-lsp-$runKind",
  '',
  '- Product: fixed Code-OSS 1.145.0-dev at commit 4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e, launched from the reproducible Windows dev build.',
  '- Runtime: Windows process-tree Private Bytes; isolated user-data, copied rust-analyzer-only extensions, shared-data, and rust-mini fixture; telemetry/updates disabled; no account sign-in or sync.',
  "- Language service: $($report.extension), configured to use $rustAnalyzerVersion at $rustAnalyzer.",
  "- Workload: an isolated temporary helper extension used vscode.TextEditor.edit and vscode.TextDocument.save to append unique Rust comments to a copied rust-mini fixture every $EditIntervalSeconds seconds; no global edit keystrokes or CDP.",
  '- Focus recovery may emit a transient Alt event only if Windows blocks restoration of the previously focused window.',
  "- Saved edits: $($saveEvents.Count)/$expectedSaveCount; every save succeeded, was read back from disk, and all markers are present in the final copy. Original fixture SHA-256 unchanged: $($sourceFixtureHashAfter -eq $sourceFixtureHashBefore).",
  "- Helper extension overhead is included in the measured process tree: $driverId@$driverVersion (package SHA-256 $driverPackageHash; source SHA-256 $driverSourceHash).",
  "- Rust Analyzer observed in the process tree: $rustAnalyzerObserved; executable paths: $($rustAnalyzerPaths -join ', ').",
  "- Sampling: target $DurationSeconds seconds at one-second intervals; collected $($samples.Count) samples over $([Math]::Round($actualSamplingElapsed, 1)) seconds; span $([Math]::Round($actualSamplingSpan, 1)) seconds and median sample interval $([Math]::Round($medianSampleInterval, 3)) seconds.",
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
  '## Tail process attribution',
  '',
  '| Process identity | Observations | Tail median Private (MiB) | Tail peak (MiB) | Last observed (MiB) | Last process count |',
  '|---|---:|---:|---:|---:|'
)
foreach ($process in $processBreakdown) {
  $lines += "| $($process.process_identity) | $($process.observations) | $([Math]::Round($process.tail_median_private / $miB, 2)) | $([Math]::Round($process.peak_private / $miB, 2)) | $([Math]::Round($process.final_observed_private / $miB, 2)) | $($process.final_process_count) |"
}
$lines += @(
  '',
  "Close check after 30 seconds: all recorded PIDs exited = $($closeCheck.all_recorded_pids_exited).",
  '',
  'Limits: This is a scripted editor-API editing workload, not a keyboard-latency test. The helper extension contributes memory to the measured process tree, so this is a comparison aid rather than a complete feature-set comparison or full docs/04 product memory matrix.'
)
[System.IO.File]::WriteAllLines($outMarkdown, [string[]]$lines, [System.Text.UTF8Encoding]::new($false))
$summaryLine = "complete samples=$($samples.Count) peak_mib=$([Math]::Round($peakPrivate / $miB, 1)) stable_mib=$([Math]::Round($stable / $miB, 1)) final_mib=$([Math]::Round($finalPrivate / $miB, 1)) foreground_unchanged=$focusStayedStable foreground_recoveries=$($focusRecoveryEvents.Count) close_exited=$($closeCheck.all_recorded_pids_exited) isolated_data_cleaned=$isolatedDataCleaned"
[System.IO.File]::AppendAllText($runLog, "$summaryLine`njson=$outJson`nmarkdown=$outMarkdown`n", [System.Text.UTF8Encoding]::new($false))
Write-Output "JSON report: $outJson"
Write-Output "Markdown report: $outMarkdown"
Write-Output "Run log: $runLog"
Write-Output "Summary: $summaryLine"
