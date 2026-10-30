param(
  [Parameter(Mandatory = $true)]
  [string]$OutputDirectory,
  [switch]$PreflightOnly
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class CodeOssImeNative {
  [StructLayout(LayoutKind.Sequential)]
  public struct Rect {
    public int Left;
    public int Top;
    public int Right;
    public int Bottom;
  }

  [DllImport("user32.dll")]
  public static extern bool GetWindowRect(IntPtr hWnd, out Rect rect);
  [DllImport("user32.dll")]
  public static extern bool ShowWindow(IntPtr hWnd, int command);
  [DllImport("user32.dll")]
  public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")]
  public static extern bool BringWindowToTop(IntPtr hWnd);
  [DllImport("user32.dll")]
  public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")]
  public static extern bool IsWindow(IntPtr hWnd);
  [DllImport("user32.dll")]
  public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")]
  public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")]
  public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
  [DllImport("user32.dll")]
  public static extern void keybd_event(byte key, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")]
  public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
  [DllImport("user32.dll")]
  public static extern bool AttachThreadInput(uint attach, uint attachTo, bool attachInput);
  [DllImport("kernel32.dll")]
  public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")]
  public static extern int GetSystemMetrics(int index);
}
"@

$script:targetHandle = [IntPtr]::Zero

function Assert-TargetForeground {
  if ($script:targetHandle -ne [IntPtr]::Zero -and
      [CodeOssImeNative]::GetForegroundWindow() -ne $script:targetHandle) {
    throw 'Code-OSS is not the foreground window; aborting before input.'
  }
}

function Send-Key([byte]$key) {
  Assert-TargetForeground
  [CodeOssImeNative]::keybd_event($key, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 35
  [CodeOssImeNative]::keybd_event($key, 0, 2, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 35
}

function Send-Letters([string]$text) {
  foreach ($character in $text.ToUpperInvariant().ToCharArray()) {
    Send-Key ([byte][char]$character)
  }
}

function Send-ControlKey([byte]$key) {
  [CodeOssImeNative]::keybd_event(0x11, 0, 0, [UIntPtr]::Zero)
  try { Send-Key $key } finally { [CodeOssImeNative]::keybd_event(0x11, 0, 2, [UIntPtr]::Zero) }
  Start-Sleep -Milliseconds 100
}

function Send-AltShift {
  Assert-TargetForeground
  [CodeOssImeNative]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero)
  [CodeOssImeNative]::keybd_event(0x10, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 100
  [CodeOssImeNative]::keybd_event(0x10, 0, 2, [UIntPtr]::Zero)
  [CodeOssImeNative]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 400
}

function Click-WindowPoint([IntPtr]$handle, [int]$x, [int]$y) {
  Assert-TargetForeground
  $rect = New-Object CodeOssImeNative+Rect
  if (-not [CodeOssImeNative]::GetWindowRect($handle, [ref]$rect)) { throw 'GetWindowRect failed' }
  [CodeOssImeNative]::SetCursorPos($rect.Left + $x, $rect.Top + $y) | Out-Null
  [CodeOssImeNative]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
  [CodeOssImeNative]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 350
}

function Save-Window([IntPtr]$handle, [string]$name) {
  Assert-TargetForeground
  $rect = New-Object CodeOssImeNative+Rect
  if (-not [CodeOssImeNative]::GetWindowRect($handle, [ref]$rect)) { throw 'GetWindowRect failed' }
  $width = $rect.Right - $rect.Left
  $height = $rect.Bottom - $rect.Top
  $bitmap = New-Object System.Drawing.Bitmap($width, $height)
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  $graphics.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bitmap.Size)
  $path = Join-Path $OutputDirectory $name
  $bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  $graphics.Dispose()
  $bitmap.Dispose()
  Write-Output "saved=$path rect=$($rect.Left),$($rect.Top),$width,$height"
}

if (-not (Test-Path $OutputDirectory)) {
  New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}

$code = 'E:\_alula_vscode_ref_4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e\.build\electron\Code - OSS.exe'
if (-not (Test-Path $code)) { throw "Pinned Code-OSS executable missing: $code" }
$referenceRoot = 'E:\_alula_vscode_ref_4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e'
$codeBatch = Join-Path $referenceRoot 'scripts\code.bat'
if (-not (Test-Path $codeBatch)) { throw "Pinned Code-OSS dev launcher missing: $codeBatch" }
$profileRoot = Join-Path $env:TEMP "code-oss-p03-4-2c-$PID"
$userData = Join-Path $profileRoot 'user-data'
$extensions = Join-Path $profileRoot 'extensions'
New-Item -ItemType Directory -Force -Path $userData, $extensions, (Join-Path $profileRoot 'shared-data') | Out-Null
$testFile = Join-Path $profileRoot 'p03-ime-input.txt'
[System.IO.File]::WriteAllText($testFile, '')
$launcher = Join-Path $profileRoot 'launch-code-oss.cmd'
$oldSkipPrelaunch = $env:VSCODE_SKIP_PRELAUNCH
$env:VSCODE_SKIP_PRELAUNCH = '1'
$originalForeground = [CodeOssImeNative]::GetForegroundWindow()
$layoutSwitched = $false
$handle = [IntPtr]::Zero

try {
  $arguments = @('--new-window', '--disable-extensions', '--disable-telemetry', '--disable-workspace-trust', "--user-data-dir=$userData", "--extensions-dir=$extensions", "--shared-data-dir=$(Join-Path $profileRoot 'shared-data')", $testFile)
  $quotedArguments = @($arguments | ForEach-Object { '"' + $_.Replace('"', '\"') + '"' })
  $launchLines = @(
    '@echo off',
    'set VSCODE_SKIP_PRELAUNCH=1',
    "cd /d `"$referenceRoot`"",
    "call `"$codeBatch`" $($quotedArguments -join ' ')"
  )
  [System.IO.File]::WriteAllLines($launcher, [string[]]$launchLines, [System.Text.Encoding]::ASCII)
  $shell = New-Object -ComObject WScript.Shell
  $shell.CurrentDirectory = $referenceRoot
  [void]$shell.Run(('cmd.exe /d /c "' + $launcher + '"'), 1, $false)
  $windowProcess = $null
  for ($attempt = 0; $attempt -lt 100 -and $handle -eq [IntPtr]::Zero; $attempt++) {
    Start-Sleep -Milliseconds 250
    $rootNodes = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
      $_.Name -eq 'Code - OSS.exe' -and $_.ExecutablePath -eq $code -and $_.CommandLine -like "*--user-data-dir=$userData*"
    })
    if ($rootNodes.Count -gt 0) {
      $windowProcess = Get-Process -Id ([int]$rootNodes[0].ProcessId) -ErrorAction SilentlyContinue
    }
    if ($null -ne $windowProcess) {
      $windowProcess.Refresh()
      $handle = $windowProcess.MainWindowHandle
    }
  }
  if ($handle -eq [IntPtr]::Zero) { throw 'Code-OSS window did not appear' }
  $fileOpened = $false
  for ($attempt = 0; $attempt -lt 80 -and -not $fileOpened; $attempt++) {
    $windowProcess.Refresh()
    $fileOpened = $windowProcess.MainWindowTitle -like '*p03-ime-input.txt*'
    if (-not $fileOpened) { Start-Sleep -Milliseconds 250 }
  }
  if (-not $fileOpened -or $windowProcess.MainWindowTitle -notmatch 'Code - OSS') {
    throw "Unexpected window title '$($windowProcess.MainWindowTitle)'; refusing to send keyboard input."
  }
  Start-Sleep -Seconds 3
  $script:targetHandle = $handle

  $screenWidth = [CodeOssImeNative]::GetSystemMetrics(0)
  $screenHeight = [CodeOssImeNative]::GetSystemMetrics(1)
  $width = [Math]::Min(1180, $screenWidth - 120)
  $height = [Math]::Min(820, $screenHeight - 120)
  [CodeOssImeNative]::ShowWindow($handle, 9) | Out-Null
  [CodeOssImeNative]::SetWindowPos($handle, [IntPtr]::Zero, 50, 40, $width, $height, 0x0040) | Out-Null
  $foreground = [CodeOssImeNative]::GetForegroundWindow()
  [uint32]$foregroundPid = 0
  [uint32]$targetPid = 0
  $foregroundThread = [CodeOssImeNative]::GetWindowThreadProcessId($foreground, [ref]$foregroundPid)
  $targetThread = [CodeOssImeNative]::GetWindowThreadProcessId($handle, [ref]$targetPid)
  $currentThread = [CodeOssImeNative]::GetCurrentThreadId()
  $attachedCurrent = $false
  $attachedTarget = $false
  try {
    if ($foregroundThread -ne 0) {
      $attachedCurrent = [CodeOssImeNative]::AttachThreadInput($currentThread, $foregroundThread, $true)
      $attachedTarget = [CodeOssImeNative]::AttachThreadInput($targetThread, $foregroundThread, $true)
    }
    [CodeOssImeNative]::BringWindowToTop($handle) | Out-Null
    [CodeOssImeNative]::SetForegroundWindow($handle) | Out-Null
  } finally {
    if ($attachedTarget) { [CodeOssImeNative]::AttachThreadInput($targetThread, $foregroundThread, $false) | Out-Null }
    if ($attachedCurrent) { [CodeOssImeNative]::AttachThreadInput($currentThread, $foregroundThread, $false) | Out-Null }
  }
  Start-Sleep -Milliseconds 1800
  Assert-TargetForeground
  Write-Output "foreground=$([CodeOssImeNative]::GetForegroundWindow()) target=$handle pid=$($windowProcess.Id)"

  Click-WindowPoint $handle 24 80
  Start-Sleep -Seconds 2
  Save-Window $handle 'code-oss-before.png'

  if ($PreflightOnly) {
    $result = [pscustomobject]@{
      platform = 'Windows 11'
      product = 'Code-OSS 1.145.0-dev'
      commit = '4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e'
      appPid = $windowProcess.Id
      windowHandle = $handle.ToInt64()
      preflightOnly = $true
      keyboardEventsSent = $false
      fileTitleMatched = $fileOpened
      userDataIsolated = $true
      extensionsDisabled = $true
      profileRoot = $profileRoot
    }
  } else {
  Click-WindowPoint $handle 500 360
  Send-AltShift
  $layoutSwitched = $true
  Send-Letters 'nihao'
  Start-Sleep -Milliseconds 900
  Save-Window $handle 'code-oss-compose.png'
  Send-Key 0x20
  Start-Sleep -Milliseconds 800
  Save-Window $handle 'code-oss-commit.png'

  Send-Letters 'zhongguo'
  Start-Sleep -Milliseconds 900
  Save-Window $handle 'code-oss-cancel-before.png'
  Send-Key 0x1B
  Start-Sleep -Milliseconds 600
  Save-Window $handle 'code-oss-cancelled.png'

  Send-Letters 'beijing'
  Start-Sleep -Milliseconds 700
  Save-Window $handle 'code-oss-focus-before.png'
  Click-WindowPoint $handle 24 80
  Start-Sleep -Milliseconds 500
  Save-Window $handle 'code-oss-focus-after.png'
  Send-Key 0x1B

  $result = [pscustomobject]@{
    platform = 'Windows 11'
    product = 'Code-OSS 1.145.0-dev'
    commit = '4bda7217fc83e8e838b1edd9ebaf21bb9b498c7e'
    inputMethod = 'Microsoft Pinyin'
    appPid = $windowProcess.Id
    windowHandle = $handle.ToInt64()
    screenshots = @('code-oss-before.png', 'code-oss-compose.png', 'code-oss-commit.png', 'code-oss-cancel-before.png', 'code-oss-cancelled.png', 'code-oss-focus-before.png', 'code-oss-focus-after.png')
    sequences = @('open isolated p03-ime-input.txt; Alt+Shift; nihao; Space', 'zhongguo; Escape', 'beijing; click Explorer Activity Bar')
    userDataIsolated = $true
    extensionsDisabled = $true
    devLauncher = 'scripts/code.bat'
    profileRoot = $profileRoot
  }
  }
} finally {
  if ($layoutSwitched -and [CodeOssImeNative]::GetForegroundWindow() -eq $script:targetHandle) {
    Send-AltShift
  }
  Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.ExecutablePath -eq $code -and $_.CommandLine -like "*$profileRoot*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  if ($originalForeground -ne [IntPtr]::Zero -and [CodeOssImeNative]::IsWindow($originalForeground)) {
    [CodeOssImeNative]::SetForegroundWindow($originalForeground) | Out-Null
  }
  if ($null -ne $oldSkipPrelaunch) { $env:VSCODE_SKIP_PRELAUNCH = $oldSkipPrelaunch }
  else { Remove-Item Env:VSCODE_SKIP_PRELAUNCH -ErrorAction SilentlyContinue }
}

$resultName = if ($PreflightOnly) { 'code-oss-preflight.json' } else { 'code-oss-ime-replay.json' }
$result | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 (Join-Path $OutputDirectory $resultName)
