param(
  [ValidateRange(1, 3)]
  [int]$RunIndex = 1,
  [switch]$Preflight,
  [ValidateRange(10, 1800)]
  [int]$DurationSeconds = 1800,
  [ValidateRange(5, 60)]
  [int]$EditIntervalSeconds = 12
)

$ErrorActionPreference = 'Stop'
$repo = 'E:\alula_code'
$appExe = Join-Path $repo 'app\build\windows\x64\runner\Release\alula_app.exe'
$probeExe = Join-Path $repo 'target\release\mem-probe.exe'
$fixtureSource = Join-Path $repo 'tests\fixtures\rust-mini'
$diagnostics = Join-Path $repo 'docs\diagnostics\2026-10-28-p00'
$uiCaptureTag = [DateTime]::Now.ToString('yyyyMMdd-HHmmssfff')
$label = if ($Preflight) { 'alula-rust-lsp-edit-preflight' } else { "alula-rust-lsp-cachepriming-off-$uiCaptureTag" }
$suffix = if ($Preflight) { 'preflight' } else { "cachepriming-off-$uiCaptureTag" }
$memoryJson = Join-Path $diagnostics "p00.4-windows-$label.json"
$memoryMarkdown = Join-Path $diagnostics "p00.4-windows-$label.md"
$activityJson = Join-Path $diagnostics "p00.4-windows-$label-activity.json"
$abortJson = Join-Path $diagnostics "p00.4-windows-$label-abort.json"
$probeStdout = Join-Path $diagnostics "p00.4-windows-$label-probe.stdout.log"
$probeStderr = Join-Path $diagnostics "p00.4-windows-$label-probe.stderr.log"
$uiCapturePaths = @(
  (Join-Path $diagnostics "p00.4-windows-$label-ui-$uiCaptureTag-tree-expanded.png"),
  (Join-Path $diagnostics "p00.4-windows-$label-ui-$uiCaptureTag-editor.png"),
  (Join-Path $diagnostics "p00.4-windows-$label-ui-$uiCaptureTag-scrolled.png"),
  (Join-Path $diagnostics "p00.4-windows-$label-ui-$uiCaptureTag-typed.png"),
  (Join-Path $diagnostics "p00.4-windows-$label-ui-$uiCaptureTag-file-menu.png"),
  (Join-Path $diagnostics "p00.4-windows-$label-ui-$uiCaptureTag-saved.png"),
  (Join-Path $diagnostics "p00.4-windows-$label-ui-$uiCaptureTag-failure.png")
)
$editDuration = if ($Preflight) { 30 } else { $DurationSeconds }
$editInterval = if ($Preflight) { 5 } else { $EditIntervalSeconds }
$probeDuration = $editDuration + 120
$tempRoot = Join-Path $repo "app\build\p00.4-edit-$suffix-$([Guid]::NewGuid().ToString('N'))"
$tempApp = Join-Path $tempRoot 'app'
$tempFixture = Join-Path $tempRoot 'tests\fixtures\rust-mini'
$tempHome = Join-Path $tempRoot 'home'
$editedFile = Join-Path $tempFixture 'src\main.rs'

foreach ($path in @($appExe, $probeExe, $fixtureSource)) {
  if (!(Test-Path -LiteralPath $path)) { throw "Required input not found: $path" }
}
foreach ($path in @($memoryJson, $memoryMarkdown, $activityJson, $abortJson, $probeStdout, $probeStderr) + $uiCapturePaths) {
  if (Test-Path -LiteralPath $path) { throw "Refusing to overwrite existing evidence: $path" }
}
if (!(Test-Path -LiteralPath $diagnostics)) { throw "Diagnostics directory not found: $diagnostics" }

Add-Type -TypeDefinition @"
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class P004EditInput {
  [StructLayout(LayoutKind.Sequential)]
  public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
  [StructLayout(LayoutKind.Sequential)]
  public struct POINT { public int X; public int Y; }
  [StructLayout(LayoutKind.Sequential)]
  public struct INPUT { public uint type; public InputUnion U; }
  [StructLayout(LayoutKind.Explicit, Size = 32)]
  public struct InputUnion { [FieldOffset(0)] public KEYBDINPUT keyboard; }
  [StructLayout(LayoutKind.Sequential)]
  public struct KEYBDINPUT {
    public ushort vk; public ushort scan; public uint flags; public uint time; public UIntPtr extra;
  }

  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int command);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT point);
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT point);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr hWnd, out RECT rect);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr hWnd, ref POINT point);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
  [DllImport("user32.dll", SetLastError = true)]
  private static extern uint SendInput(uint count, INPUT[] inputs, int size);
  [DllImport("user32.dll")]
  public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")]
  private static extern uint MapVirtualKey(uint code, uint mapType);

  private static uint ExtendedKeyFlag(ushort vk) {
    switch (vk) {
      case 0x21: case 0x22: case 0x23: case 0x24:
      case 0x25: case 0x26: case 0x27: case 0x28:
      case 0x2D: case 0x2E: return 1;
      default: return 0;
    }
  }

  private static void Send(INPUT input) {
    var inputs = new INPUT[] { input };
    if (SendInput(1, inputs, Marshal.SizeOf(typeof(INPUT))) != 1)
      throw new Win32Exception(Marshal.GetLastWin32Error());
  }
  public static void SendChord(ushort modifier, ushort key) {
    uint extended = ExtendedKeyFlag(key);
    var inputs = new INPUT[4];
    inputs[0].type = 1; inputs[0].U.keyboard.vk = modifier;
    inputs[1].type = 1; inputs[1].U.keyboard.vk = key; inputs[1].U.keyboard.flags = extended;
    inputs[2].type = 1; inputs[2].U.keyboard.vk = key; inputs[2].U.keyboard.flags = extended | 2;
    inputs[3].type = 1; inputs[3].U.keyboard.vk = modifier; inputs[3].U.keyboard.flags = 2;
    if (SendInput(4, inputs, Marshal.SizeOf(typeof(INPUT))) != 4)
      throw new Win32Exception(Marshal.GetLastWin32Error());
  }
  public static void KeyDown(ushort vk) {
    uint translated = MapVirtualKey(vk, 4);
    if (translated == 0) translated = MapVirtualKey(vk, 0);
    uint extended = ((translated & 0xFF00) == 0xE000 || ExtendedKeyFlag(vk) != 0) ? 1u : 0u;
    keybd_event(0, (byte)(translated & 0xFF), 0x0008 | extended, UIntPtr.Zero);
  }
  public static void KeyUp(ushort vk) {
    uint translated = MapVirtualKey(vk, 4);
    if (translated == 0) translated = MapVirtualKey(vk, 0);
    uint extended = ((translated & 0xFF00) == 0xE000 || ExtendedKeyFlag(vk) != 0) ? 1u : 0u;
    keybd_event(0, (byte)(translated & 0xFF), 0x0008 | extended | 2u, UIntPtr.Zero);
  }
  public static void Tap(ushort vk) {
    KeyDown(vk); System.Threading.Thread.Sleep(35); KeyUp(vk); System.Threading.Thread.Sleep(35);
  }
  public static void ScrollDown(int notches) {
    mouse_event(0x0800, 0, 0, unchecked((uint)(-120 * notches)), UIntPtr.Zero);
  }
  public static void SendUnicode(string value) {
    foreach (char ch in value) {
      var down = new INPUT(); down.type = 1; down.U.keyboard.scan = ch; down.U.keyboard.flags = 4; Send(down);
      var up = new INPUT(); up.type = 1; up.U.keyboard.scan = ch; up.U.keyboard.flags = 6; Send(up);
    }
  }
}
"@

function Assert-TargetForeground {
  $current = [P004EditInput]::GetForegroundWindow()
  if ($current -ne $targetWindow) {
    throw "Foreground changed (expected $($targetWindow.ToInt64()), found $($current.ToInt64())); stopped before sending more input."
  }
}

function Send-ControlKey([uint16]$key) {
  Assert-TargetForeground
  [P004EditInput]::KeyDown(0x11)
  try {
    Start-Sleep -Milliseconds 35
    [P004EditInput]::Tap($key)
    Start-Sleep -Milliseconds 35
  } finally {
    [P004EditInput]::KeyUp(0x11)
  }
}

function Send-AltF4 {
  Assert-TargetForeground
  [P004EditInput]::KeyDown(0x12)
  try {
    Start-Sleep -Milliseconds 35
    [P004EditInput]::Tap(0x73)
    Start-Sleep -Milliseconds 35
  } finally {
    [P004EditInput]::KeyUp(0x12)
  }
}

function Send-EditorComment([string]$marker) {
  Assert-TargetForeground
  Add-Type -AssemblyName System.Windows.Forms
  $window = New-Object P004EditInput+RECT
  if (![P004EditInput]::GetWindowRect($targetWindow, [ref]$window)) { throw 'GetWindowRect failed before editing.' }
  [void][P004EditInput]::SetCursorPos($window.Left + 800, $window.Top + 400)
  [P004EditInput]::ScrollDown(-60)
  Start-Sleep -Milliseconds 600
  Assert-TargetForeground
  if ($Preflight -and $edits.Count -eq 0) { Save-TargetScreenshot $uiCapturePaths[2] }
  [void][P004EditInput]::SetCursorPos($window.Left + 500, $window.Bottom - 45)
  [P004EditInput]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
  [P004EditInput]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 150
  Assert-TargetForeground
  [P004EditInput]::Tap(0x23)
  [P004EditInput]::Tap(0x0D) # Enter
  [P004EditInput]::SendUnicode("// $marker")
  Assert-TargetForeground
  if ($Preflight -and $edits.Count -eq 0) { Save-TargetScreenshot $uiCapturePaths[3] }
  if ($Preflight -and $edits.Count -eq 0) {
    [void][P004EditInput]::SetCursorPos($window.Left + 130, $window.Top + 26)
    Start-Sleep -Milliseconds 200
    [P004EditInput]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
    [P004EditInput]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 400
    Assert-TargetForeground
    Save-TargetScreenshot $uiCapturePaths[4]
    [P004EditInput]::Tap(0x1B) # Close the menu; save through the documented shortcut below.
    Start-Sleep -Milliseconds 100
    Assert-TargetForeground
  }
  Send-ControlKey 0x53 # Ctrl+S; avoid coordinate-sensitive menu selection.
  Start-Sleep -Milliseconds 600
  Assert-TargetForeground
  if ($Preflight -and $edits.Count -eq 0) { Save-TargetScreenshot $uiCapturePaths[5] }
}

function Get-TreeNodes([int]$RootPid) {
  $all = @(Get-CimInstance -ClassName Win32_Process)
  $ids = @($RootPid)
  do {
    $previousCount = $ids.Count
    $children = @($all | Where-Object { $ids -contains [int]$_.ParentProcessId } |
      ForEach-Object { [int]$_.ProcessId })
    $ids = @($ids + $children | Sort-Object -Unique)
  } while ($ids.Count -gt $previousCount)
  return @($all | Where-Object { $ids -contains [int]$_.ProcessId })
}

function Add-ObservedPids([int]$RootPid) {
  foreach ($node in @(Get-TreeNodes $RootPid)) {
    $key = [string][int]$node.ProcessId
    $observedPids[$key] = [pscustomobject]@{
      pid = [int]$node.ProcessId
      ppid = [int]$node.ParentProcessId
      name = [string]$node.Name
      executable_path = [string]$node.ExecutablePath
    }
  }
}

function Add-ProcessMemorySnapshot([int]$RootPid, [double]$ElapsedSeconds) {
  $capturedAt = [DateTime]::UtcNow.ToString('o')
  foreach ($node in @(Get-TreeNodes $RootPid)) {
    try {
      $process = Get-Process -Id ([int]$node.ProcessId) -ErrorAction Stop
      $process.Refresh()
      [void]$processMemorySamples.Add([pscustomobject]@{
        elapsed_s = [Math]::Round($ElapsedSeconds, 3)
        captured_at_utc = $capturedAt
        pid = [int]$node.ProcessId
        ppid = [int]$node.ParentProcessId
        name = [string]$node.Name
        executable_path = [string]$node.ExecutablePath
        private_bytes = [long]$process.PrivateMemorySize64
        working_set_bytes = [long]$process.WorkingSet64
      })
    } catch {
      # A short-lived child may exit between the process-tree and memory queries.
    }
  }
}

function Stop-AppTree([int]$RootPid) {
  if ($RootPid -le 0) { return }
  $nodes = @(Get-TreeNodes $RootPid)
  $ordered = @($nodes | Where-Object { [int]$_.ProcessId -ne $RootPid }) +
    @($nodes | Where-Object { [int]$_.ProcessId -eq $RootPid })
  foreach ($node in $ordered) {
    Stop-Process -Id ([int]$node.ProcessId) -Force -ErrorAction SilentlyContinue
  }
}

function Wait-ForSavedMarker([string]$Marker) {
  $deadline = [DateTime]::UtcNow.AddSeconds(8)
  while ([DateTime]::UtcNow -lt $deadline) {
    Assert-TargetForeground
    if (Test-Path -LiteralPath $editedFile) {
      $text = [System.IO.File]::ReadAllText($editedFile)
      if ($text.Contains($Marker)) { return $text }
    }
    Start-Sleep -Milliseconds 150
  }
  throw "Save verification failed for marker $Marker"
}

function Save-TargetScreenshot([string]$Path) {
  if ($targetWindow -eq [IntPtr]::Zero) { return }
  if (Test-Path -LiteralPath $Path) { throw "Refusing to overwrite UI capture: $Path" }
  $bounds = New-Object P004EditInput+RECT
  if (![P004EditInput]::GetWindowRect($targetWindow, [ref]$bounds)) { return }
  $width = $bounds.Right - $bounds.Left
  $height = $bounds.Bottom - $bounds.Top
  if ($width -le 0 -or $height -le 0) { return }
  Add-Type -AssemblyName System.Drawing
  $bitmap = [System.Drawing.Bitmap]::new($width, $height)
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  try {
    $graphics.CopyFromScreen($bounds.Left, $bounds.Top, 0, 0, $bitmap.Size)
    $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
  } finally {
    $graphics.Dispose()
    $bitmap.Dispose()
  }
}

$foregroundBefore = [P004EditInput]::GetForegroundWindow()
$targetWindow = [IntPtr]::Zero
$rootPid = 0
$probeProcess = $null
$observedPids = @{}
$processMemorySamples = New-Object System.Collections.ArrayList
$edits = New-Object System.Collections.ArrayList
$testStartedUtc = [DateTime]::UtcNow.ToString('o')
$editStartedUtc = $null
$editEndedUtc = $null
$editTimer = $null
$failure = $null
$success = $false
$closeCheck = $null

try {
  New-Item -ItemType Directory -Path $tempApp, $tempFixture, $tempHome -Force | Out-Null
  $sourcePrefix = $fixtureSource.TrimEnd('\') + '\'
  foreach ($file in @(Get-ChildItem -LiteralPath $fixtureSource -Recurse -File | Where-Object {
        $_.FullName -notmatch '[\\/]target[\\/]' -and $_.FullName -notmatch '[\\/]\.git[\\/]'
      })) {
    $relative = $file.FullName.Substring($sourcePrefix.Length)
    $destination = Join-Path $tempFixture $relative
    $destinationDir = Split-Path -Parent $destination
    New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
    Copy-Item -LiteralPath $file.FullName -Destination $destination
  }
  if (!(Test-Path -LiteralPath $editedFile)) { throw "Copied fixture missing editor target: $editedFile" }
  $rustAnalyzerConfig = Join-Path $tempFixture 'rust-analyzer.toml'
  $rustAnalyzerConfigText = "[cachePriming]`nenable = false`n"
  [System.IO.File]::WriteAllText($rustAnalyzerConfig, $rustAnalyzerConfigText, [System.Text.UTF8Encoding]::new($false))
  $rustAnalyzerConfigHash = (Get-FileHash -LiteralPath $rustAnalyzerConfig -Algorithm SHA256).Hash
  $baselineHash = (Get-FileHash -LiteralPath $editedFile -Algorithm SHA256).Hash

  $probeInfo = New-Object System.Diagnostics.ProcessStartInfo
  $probeInfo.FileName = $probeExe
  $probeInfo.Arguments = @(
    'watch', '--exe', $appExe, '--arg', '--lsp-auto', '--duration', [string]$probeDuration,
    '--interval', '1', '--label', $label, '--out', $memoryJson, '--md', $memoryMarkdown, '--no-kill'
  ) -join ' '
  $probeInfo.WorkingDirectory = $tempApp
  $probeInfo.UseShellExecute = $false
  $probeInfo.CreateNoWindow = $true
  $probeInfo.RedirectStandardOutput = $true
  $probeInfo.RedirectStandardError = $true
  $probeInfo.EnvironmentVariables['HOME'] = $tempHome
  $probeInfo.EnvironmentVariables['RA_LOG'] = 'rust_analyzer=info'
  $probeProcess = [System.Diagnostics.Process]::Start($probeInfo)
  $stdoutTask = $probeProcess.StandardOutput.ReadToEndAsync()
  $stderrTask = $probeProcess.StandardError.ReadToEndAsync()

  $deadline = [DateTime]::UtcNow.AddSeconds(40)
  while ([DateTime]::UtcNow -lt $deadline -and $rootPid -eq 0) {
    $appNode = Get-CimInstance -ClassName Win32_Process -Filter "ParentProcessId=$($probeProcess.Id)" |
      Where-Object { $_.Name -eq 'alula_app.exe' } | Select-Object -First 1
    if ($appNode) { $rootPid = [int]$appNode.ProcessId; break }
    if ($probeProcess.HasExited) { throw "mem-probe exited before Alula appeared (code $($probeProcess.ExitCode))" }
    Start-Sleep -Milliseconds 250
  }
  if ($rootPid -eq 0) { throw 'Timed out waiting for the isolated Alula root process.' }

  $targetProcess = $null
  $deadline = [DateTime]::UtcNow.AddSeconds(60)
  while ([DateTime]::UtcNow -lt $deadline) {
    $targetProcess = Get-Process -Id $rootPid -ErrorAction SilentlyContinue
    if ($targetProcess) {
      $targetProcess.Refresh()
      if ($targetProcess.MainWindowHandle -ne 0) { break }
    }
    Start-Sleep -Milliseconds 250
  }
  if (!$targetProcess -or $targetProcess.MainWindowHandle -eq 0) { throw 'Timed out waiting for the isolated Alula window.' }

  $targetWindow = [IntPtr]$targetProcess.MainWindowHandle
  Write-Output "target_window_handle=$($targetWindow.ToInt64())"
  $windowRect = New-Object P004EditInput+RECT
  [void][P004EditInput]::GetWindowRect($targetWindow, [ref]$windowRect)
  Write-Output "target_window_rect=$($windowRect.Left),$($windowRect.Top),$($windowRect.Right),$($windowRect.Bottom)"
  [void][P004EditInput]::ShowWindow($targetWindow, 9)
  [void][P004EditInput]::BringWindowToTop($targetWindow)
  $shell = New-Object -ComObject WScript.Shell
  $previousCursor = New-Object P004EditInput+POINT
  [void][P004EditInput]::GetCursorPos([ref]$previousCursor)
  $windowRect = New-Object P004EditInput+RECT
  if (![P004EditInput]::GetWindowRect($targetWindow, [ref]$windowRect)) { throw 'GetWindowRect failed.' }
  $activationDeadline = [DateTime]::UtcNow.AddSeconds(8)
  do {
    [P004EditInput]::Tap(0x12) # Alt grants a user-input activation opportunity.
    [void]$shell.AppActivate($rootPid)
    [void][P004EditInput]::SetForegroundWindow($targetWindow)
    if ([P004EditInput]::GetForegroundWindow() -ne $targetWindow) {
      $titlePoint = New-Object P004EditInput+POINT
      $titlePoint.X = [int](($windowRect.Left + $windowRect.Right) / 2)
      $titlePoint.Y = [int]($windowRect.Top + 12)
      if ([P004EditInput]::WindowFromPoint($titlePoint) -eq $targetWindow) {
        [void][P004EditInput]::SetCursorPos($titlePoint.X, $titlePoint.Y)
        [P004EditInput]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
        [P004EditInput]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
      }
    }
    Start-Sleep -Milliseconds 150
  } while ([P004EditInput]::GetForegroundWindow() -ne $targetWindow -and [DateTime]::UtcNow -lt $activationDeadline)
  [void][P004EditInput]::SetCursorPos($previousCursor.X, $previousCursor.Y)
  Assert-TargetForeground
  Start-Sleep -Seconds 5 # Let core and the fixture workspace settle before opening its file.

  $client = New-Object P004EditInput+RECT
  if (![P004EditInput]::GetClientRect($targetWindow, [ref]$client)) { throw 'GetClientRect failed.' }
  $treePoint = New-Object P004EditInput+POINT
  $treePoint.X = [int](($client.Right - $client.Left) * 0.09)
  $treePoint.Y = [int](($client.Bottom - $client.Top) * 0.12)
  if (![P004EditInput]::ClientToScreen($targetWindow, [ref]$treePoint)) { throw 'ClientToScreen failed for src folder.' }
  Assert-TargetForeground
  [void][P004EditInput]::SetCursorPos($treePoint.X, $treePoint.Y)
  [P004EditInput]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
  [P004EditInput]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 500
  Assert-TargetForeground
  if ($Preflight) { Save-TargetScreenshot $uiCapturePaths[0] }

  $filePoint = New-Object P004EditInput+POINT
  $filePoint.X = [int](($client.Right - $client.Left) * 0.09)
  $filePoint.Y = [int](($client.Bottom - $client.Top) * 0.16)
  if (![P004EditInput]::ClientToScreen($targetWindow, [ref]$filePoint)) { throw 'ClientToScreen failed for main.rs.' }
  [void][P004EditInput]::SetCursorPos($filePoint.X, $filePoint.Y)
  [P004EditInput]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
  [P004EditInput]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 700
  Assert-TargetForeground
  if ($Preflight) { Save-TargetScreenshot $uiCapturePaths[1] }

  $point = New-Object P004EditInput+POINT
  $point.X = [Math]::Max(320, [int](($client.Right - $client.Left) * 0.65))
  $point.Y = [Math]::Max(190, [int](($client.Bottom - $client.Top) * 0.38))
  if (![P004EditInput]::ClientToScreen($targetWindow, [ref]$point)) { throw 'ClientToScreen failed.' }
  [void][P004EditInput]::SetCursorPos($point.X, $point.Y)
  [P004EditInput]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
  [P004EditInput]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 300
  Assert-TargetForeground

  Add-ObservedPids $rootPid
  $editStartedUtc = [DateTime]::UtcNow.ToString('o')
  $editTimer = [System.Diagnostics.Stopwatch]::StartNew()
  Add-ProcessMemorySnapshot $rootPid $editTimer.Elapsed.TotalSeconds
  $cycle = 0
  while ($editTimer.Elapsed.TotalSeconds -lt $editDuration) {
    Assert-TargetForeground
    if ($probeProcess.HasExited) { throw "mem-probe ended early during editing (code $($probeProcess.ExitCode))" }
    $cycle++
    $marker = if ($Preflight) {
      'P00_4_PREFLIGHT_EDIT_' + $cycle.ToString('D3')
    } else {
      'P00_4_EDIT_' + $RunIndex.ToString('D1') + '_' + $cycle.ToString('D3')
    }
    Send-EditorComment $marker
    $text = Wait-ForSavedMarker $marker
    $hash = (Get-FileHash -LiteralPath $editedFile -Algorithm SHA256).Hash
    [void]$edits.Add([pscustomobject]@{
      cycle = $cycle
      elapsed_s = [Math]::Round($editTimer.Elapsed.TotalSeconds, 3)
      captured_at_utc = [DateTime]::UtcNow.ToString('o')
      marker = $marker
      saved = $true
      bytes = [System.Text.Encoding]::UTF8.GetByteCount($text)
      sha256 = $hash
    })
    if (($cycle % 5) -eq 0) {
      Add-ObservedPids $rootPid
      Add-ProcessMemorySnapshot $rootPid $editTimer.Elapsed.TotalSeconds
      Write-Output "edit_run=$suffix cycle=$cycle elapsed_s=$([Math]::Round($editTimer.Elapsed.TotalSeconds)) saved_hash=$($hash.Substring(0, 12))"
    }
    $nextDeadline = $cycle * $editInterval
    while ($editTimer.Elapsed.TotalSeconds -lt $nextDeadline) {
      Assert-TargetForeground
      if ($probeProcess.HasExited) { throw "mem-probe ended early during editing (code $($probeProcess.ExitCode))" }
      $remaining = [int][Math]::Min(500, [Math]::Ceiling(($nextDeadline - $editTimer.Elapsed.TotalSeconds) * 1000))
      if ($remaining -gt 0) { Start-Sleep -Milliseconds $remaining }
    }
  }
  if ($editTimer.Elapsed.TotalSeconds -lt $editDuration) { throw 'Edit interval ended before its required duration.' }
  $editEndedUtc = [DateTime]::UtcNow.ToString('o')
  $editTimer.Stop()
  Add-ProcessMemorySnapshot $rootPid $editTimer.Elapsed.TotalSeconds
  $finalText = [System.IO.File]::ReadAllText($editedFile)
  $lastMarker = [string]$edits[$edits.Count - 1].marker
  if (!$finalText.Contains($lastMarker)) { throw "Final disk content is missing last marker $lastMarker" }
  $finalHash = (Get-FileHash -LiteralPath $editedFile -Algorithm SHA256).Hash
  if ($finalHash -eq $baselineHash) { throw 'Fixture hash did not change after scripted edits.' }

  Add-ObservedPids $rootPid
  Assert-TargetForeground
  Send-AltF4
  $exitDeadline = [DateTime]::UtcNow.AddSeconds(12)
  while ([DateTime]::UtcNow -lt $exitDeadline -and (Get-Process -Id $rootPid -ErrorAction SilentlyContinue)) {
    Start-Sleep -Milliseconds 250
  }
  if (Get-Process -Id $rootPid -ErrorAction SilentlyContinue) { Stop-AppTree $rootPid }

  $probeProcess.WaitForExit(60000) | Out-Null
  if (!$probeProcess.HasExited) { throw 'mem-probe did not finish after the application process exited.' }
  $stdoutText = $stdoutTask.GetAwaiter().GetResult()
  $stderrText = $stderrTask.GetAwaiter().GetResult()
  [System.IO.File]::WriteAllText($probeStdout, $stdoutText, [System.Text.UTF8Encoding]::new($false))
  [System.IO.File]::WriteAllText($probeStderr, $stderrText, [System.Text.UTF8Encoding]::new($false))
  if ($probeProcess.ExitCode -ne 0) { throw "mem-probe failed with exit code $($probeProcess.ExitCode): $stderrText" }
  if (!(Test-Path -LiteralPath $memoryJson)) { throw 'mem-probe did not write its JSON report.' }

  $probeReport = Get-Content -LiteralPath $memoryJson -Raw | ConvertFrom-Json
  if ($probeReport.samples.Count -lt $editDuration) {
    throw "Only $($probeReport.samples.Count) memory samples captured for a $editDuration-second edit run."
  }
  $recorded = @($observedPids.Values | Sort-Object pid)
  Start-Sleep -Seconds 30
  $liveRecorded = @()
  foreach ($item in $recorded) {
    $current = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId=$($item.pid)" -ErrorAction SilentlyContinue
    if ($current -and $current.Name -eq $item.name) { $liveRecorded += [int]$item.pid }
  }
  $closeCheck = [pscustomobject]@{
    wait_seconds = 30
    checked_at_utc = [DateTime]::UtcNow.ToString('o')
    all_recorded_processes_exited = ($liveRecorded.Count -eq 0)
    still_alive_pids = $liveRecorded
  }

  $report = [ordered]@{
    label = $label
    run_index = if ($Preflight) { 0 } else { $RunIndex }
    preflight = [bool]$Preflight
    platform = 'Windows'
    app_exe = $appExe
    mem_probe_exe = $probeExe
    args = @('--lsp-auto')
    fixture_source = $fixtureSource
    isolated_fixture = $tempFixture
    isolated_home = $tempHome
    edited_file = $editedFile
    rust_analyzer_config_file = 'rust-analyzer.toml in isolated project root'
    rust_analyzer_config_text = $rustAnalyzerConfigText
    rust_analyzer_config_sha256 = $rustAnalyzerConfigHash
    cache_priming_enabled = $false
    baseline_sha256 = $baselineHash
    final_sha256 = $finalHash
    final_byte_count = [System.Text.Encoding]::UTF8.GetByteCount($finalText)
    last_saved_marker = $lastMarker
    edit_duration_s = [double]$editTimer.Elapsed.TotalSeconds
    edit_interval_s = [double]$editInterval
    edit_count = $edits.Count
    test_started_at_utc = $testStartedUtc
    edit_started_at_utc = $editStartedUtc
    edit_ended_at_utc = $editEndedUtc
    root_pid = $rootPid
    process_tree_pids = $recorded
    foreground_restored = $false
    close_check = $closeCheck
    memory_report = [IO.Path]::GetFileName($memoryJson)
    memory_summary = $probeReport.summary
    memory_samples = $probeReport.samples.Count
    process_memory_sample_interval_edits = 5
    process_memory_samples = @($processMemorySamples.ToArray())
    edits = @($edits.ToArray())
  }
  if ($foregroundBefore -ne [IntPtr]::Zero -and [P004EditInput]::IsWindow($foregroundBefore)) {
    $report.foreground_restored = [P004EditInput]::SetForegroundWindow($foregroundBefore)
  }
  [System.IO.File]::WriteAllText($activityJson, ($report | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))

  $miB = 1048576.0
  $summary = $probeReport.summary
  $md = @(
    "# P00.4 Windows Alula Rust + rust-analyzer scripted editing $suffix",
    '',
    '- Product: Alula Windows Release with isolated HOME and a temporary copy of `rust-mini`.',
    "- rust-analyzer config experiment: cachePriming.enable=false via isolated rust-analyzer.toml (SHA-256 $rustAnalyzerConfigHash); RA_LOG=rust_analyzer=info.",
    "- Scripted editor input: $($edits.Count) source comments inserted and saved over $([Math]::Round($editTimer.Elapsed.TotalSeconds, 1)) seconds.",
    "- Disk check: SHA-256 changed from $baselineHash to $finalHash; final marker '$lastMarker' is present in the saved copy.",
    "- Process tree: $($recorded.Count) distinct PIDs observed; all exited after the close check = $($closeCheck.all_recorded_processes_exited).",
    "- Private Bytes: peak $([Math]::Round($summary.peak_private / $miB, 2)) MiB; stable $([Math]::Round($summary.stable_private / $miB, 2)) MiB; final $([Math]::Round($summary.final_private / $miB, 2)) MiB.",
    "- Samples: $($probeReport.samples.Count); mem-probe duration target $probeDuration s; one-second interval.",
    "- Process detail: $($processMemorySamples.Count) per-PID Private Bytes/Working Set observations at start, every fifth saved edit, and the end of editing.",
    "- Isolated fixture and HOME: removed after evidence capture; app foreground restored = $($report.foreground_restored).",
    '',
    'This is a single Windows product scenario repetition. It does not include a VS Code comparison, other platforms, DRM WPE GBM, or Microsoft account/service validation.'
  )
  [System.IO.File]::WriteAllLines($memoryMarkdown, [string[]]$md, [System.Text.UTF8Encoding]::new($false))
  $success = $true
  Write-Output "complete=$label edits=$($edits.Count) edit_seconds=$([Math]::Round($editTimer.Elapsed.TotalSeconds, 1)) samples=$($probeReport.samples.Count) peak_mib=$([Math]::Round($summary.peak_private / $miB, 1)) stable_mib=$([Math]::Round($summary.stable_private / $miB, 1)) close_exited=$($closeCheck.all_recorded_processes_exited)"
  Write-Output "memory_json=$memoryJson"
  Write-Output "activity_json=$activityJson"
} catch {
  $failure = $_.Exception.Message
  Write-Warning $failure
  if ($targetWindow -ne [IntPtr]::Zero -and [P004EditInput]::GetForegroundWindow() -eq $targetWindow) {
    try { Save-TargetScreenshot $uiCapturePaths[6] } catch {}
  }
  if ($rootPid -gt 0) { Stop-AppTree $rootPid }
  if ($probeProcess -and !$probeProcess.HasExited) {
    $probeProcess.Kill()
    $probeProcess.WaitForExit(10000) | Out-Null
  }
  if ($probeProcess -and $probeProcess.HasExited) {
    try {
      if ($stdoutTask) {
        [System.IO.File]::WriteAllText($probeStdout, $stdoutTask.GetAwaiter().GetResult(), [System.Text.UTF8Encoding]::new($false))
      }
      if ($stderrTask) {
        [System.IO.File]::WriteAllText($probeStderr, $stderrTask.GetAwaiter().GetResult(), [System.Text.UTF8Encoding]::new($false))
      }
    } catch {}
  }
  $foregroundAtAbort = [P004EditInput]::GetForegroundWindow()
  $recordedAtAbort = @($observedPids.Values | Sort-Object pid)
  $elapsedAtAbort = if ($editTimer) { [Math]::Round($editTimer.Elapsed.TotalSeconds, 3) } else { 0 }
  $abortReport = [ordered]@{
    label = $label
    run_index = if ($Preflight) { 0 } else { $RunIndex }
    preflight = [bool]$Preflight
    status = 'aborted'
    abort_reason = $failure
    aborted_at_utc = [DateTime]::UtcNow.ToString('o')
    test_started_at_utc = $testStartedUtc
    edit_started_at_utc = $editStartedUtc
    edit_elapsed_s = $elapsedAtAbort
    expected_foreground_hwnd = if ($targetWindow -ne [IntPtr]::Zero) { $targetWindow.ToInt64() } else { $null }
    foreground_hwnd_at_abort = if ($foregroundAtAbort -ne [IntPtr]::Zero) { $foregroundAtAbort.ToInt64() } else { $null }
    root_pid = $rootPid
    process_tree_pids_observed = $recordedAtAbort
    process_memory_sample_interval_edits = 5
    process_memory_samples = @($processMemorySamples.ToArray())
    saved_edit_count = $edits.Count
    saved_edits = @($edits.ToArray())
    memory_report_path = [IO.Path]::GetFileName($memoryJson)
    memory_report_present = (Test-Path -LiteralPath $memoryJson)
    memory_report_valid_for_acceptance = $false
    note = 'An aborted attempt is not a completed duration sample. Any partial memory output is diagnostic only and must not be counted toward acceptance.'
  }
  try {
    [System.IO.File]::WriteAllText($abortJson, ($abortReport | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))
  } catch {
    Write-Warning "Could not write abort report: $($_.Exception.Message)"
  }
  throw
} finally {
  if ($foregroundBefore -ne [IntPtr]::Zero -and [P004EditInput]::IsWindow($foregroundBefore)) {
    [void][P004EditInput]::SetForegroundWindow($foregroundBefore)
  }
  if ($probeProcess) { $probeProcess.Dispose() }
  if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
