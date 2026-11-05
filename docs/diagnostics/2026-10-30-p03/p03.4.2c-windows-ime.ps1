param(
  [Parameter(Mandatory = $true)]
  [string]$OutputDirectory,
  [switch]$PreflightOnly
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System.Runtime.InteropServices;

public static class AlulaCoreAbiPreflight {
  [DllImport(@"E:\Alula_Code\app\native\alula_core.dll", EntryPoint = "alula_abi_version", CallingConvention = CallingConvention.Cdecl)]
  public static extern uint Version();
}
"@
Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class AlulaImeNative {
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
  public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
  [DllImport("user32.dll")]
  public static extern bool AttachThreadInput(uint attach, uint attachTo, bool attachInput);
  [DllImport("kernel32.dll")]
  public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")]
  public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")]
  public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")]
  public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
  [DllImport("user32.dll")]
  public static extern void keybd_event(byte key, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")]
  public static extern int GetSystemMetrics(int index);
}
"@

function Assert-TargetForeground {
  if ($script:targetHandle -ne [IntPtr]::Zero -and
      [AlulaImeNative]::GetForegroundWindow() -ne $script:targetHandle) {
    throw 'Alula is not the foreground window; aborting before input.'
  }
}

function Send-Key([byte]$key) {
  Assert-TargetForeground
  [AlulaImeNative]::keybd_event($key, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 35
  [AlulaImeNative]::keybd_event($key, 0, 2, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 35
}

function Send-Letters([string]$text) {
  foreach ($character in $text.ToUpperInvariant().ToCharArray()) {
    Send-Key ([byte][char]$character)
  }
}

function Send-ControlKey([byte]$key) {
  [AlulaImeNative]::keybd_event(0x11, 0, 0, [UIntPtr]::Zero)
  Send-Key $key
  [AlulaImeNative]::keybd_event(0x11, 0, 2, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 100
}

function Send-AltShift {
  Assert-TargetForeground
  [AlulaImeNative]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero)
  [AlulaImeNative]::keybd_event(0x10, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 100
  [AlulaImeNative]::keybd_event(0x10, 0, 2, [UIntPtr]::Zero)
  [AlulaImeNative]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 400
}

function Click-Editor([IntPtr]$handle) {
  Assert-TargetForeground
  $rect = New-Object AlulaImeNative+Rect
  if (-not [AlulaImeNative]::GetWindowRect($handle, [ref]$rect)) {
    throw 'GetWindowRect failed'
  }
  [AlulaImeNative]::SetCursorPos($rect.Left + 500, $rect.Top + 360) | Out-Null
  [AlulaImeNative]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
  [AlulaImeNative]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 300
}

function Click-WindowPoint([IntPtr]$handle, [int]$x, [int]$y) {
  Assert-TargetForeground
  $rect = New-Object AlulaImeNative+Rect
  if (-not [AlulaImeNative]::GetWindowRect($handle, [ref]$rect)) {
    throw 'GetWindowRect failed'
  }
  [AlulaImeNative]::SetCursorPos($rect.Left + $x, $rect.Top + $y) | Out-Null
  [AlulaImeNative]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
  [AlulaImeNative]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 350
}

function Save-Window([IntPtr]$handle, [string]$name) {
  Assert-TargetForeground
  $rect = New-Object AlulaImeNative+Rect
  if (-not [AlulaImeNative]::GetWindowRect($handle, [ref]$rect)) {
    throw 'GetWindowRect failed'
  }
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

$appRoot = 'E:\Alula_Code\app'
$executable = Join-Path $appRoot 'build\windows\x64\runner\Release\alula_app.exe'
if (-not (Test-Path $executable)) {
  throw "Alula Release executable missing: $executable"
}
$coreVersion = [AlulaCoreAbiPreflight]::Version()
if ($coreVersion -ne 15) { throw "Expected Rust ABI 15, got $coreVersion" }
$coreHash = (Get-FileHash (Join-Path $appRoot 'native\alula_core.dll')).Hash
$bundleHash = (Get-FileHash (Join-Path (Split-Path $executable) 'alula_core.dll')).Hash
if ($coreHash -ne $bundleHash) { throw 'Release bundle core DLL does not match app/native' }

$originalForeground = [AlulaImeNative]::GetForegroundWindow()
$originalUserProfile = $env:USERPROFILE
$originalHome = $env:HOME
$originalAppData = $env:APPDATA
$originalLocalAppData = $env:LOCALAPPDATA
$profileRoot = Join-Path $env:TEMP "alula-p03-4-2c-$PID"
New-Item -ItemType Directory -Force -Path $profileRoot | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $profileRoot 'Roaming') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $profileRoot 'Local') | Out-Null
$env:USERPROFILE = $profileRoot
$env:HOME = $profileRoot
$env:APPDATA = Join-Path $profileRoot 'Roaming'
$env:LOCALAPPDATA = Join-Path $profileRoot 'Local'
$appProcess = $null
$script:targetHandle = [IntPtr]::Zero
$layoutSwitched = $false
$records = [System.Collections.Generic.List[object]]::new()

try {
  $appProcess = Start-Process -FilePath $executable -WorkingDirectory $appRoot -PassThru
  $handle = [IntPtr]::Zero
  for ($attempt = 0; $attempt -lt 80 -and $handle -eq [IntPtr]::Zero; $attempt++) {
    Start-Sleep -Milliseconds 250
    $current = Get-Process -Id $appProcess.Id -ErrorAction SilentlyContinue
    if ($null -eq $current) { throw 'Alula exited before creating its window' }
    $current.Refresh()
    $handle = $current.MainWindowHandle
  }
  if ($handle -eq [IntPtr]::Zero) { throw 'Alula main window did not appear' }
  $script:targetHandle = $handle

  $screenWidth = [AlulaImeNative]::GetSystemMetrics(0)
  $screenHeight = [AlulaImeNative]::GetSystemMetrics(1)
  $width = [Math]::Min(1180, $screenWidth - 120)
  $height = [Math]::Min(820, $screenHeight - 120)
  [AlulaImeNative]::ShowWindow($handle, 9) | Out-Null
  [AlulaImeNative]::SetWindowPos($handle, [IntPtr]::Zero, 50, 40, $width, $height, 0x0040) | Out-Null
  $foreground = [AlulaImeNative]::GetForegroundWindow()
  [uint32]$foregroundPid = 0
  [uint32]$targetPid = 0
  $foregroundThread = [AlulaImeNative]::GetWindowThreadProcessId($foreground, [ref]$foregroundPid)
  $targetThread = [AlulaImeNative]::GetWindowThreadProcessId($handle, [ref]$targetPid)
  $currentThread = [AlulaImeNative]::GetCurrentThreadId()
  $attachedCurrent = $false
  $attachedTarget = $false
  try {
    if ($foregroundThread -ne 0) {
      $attachedCurrent = [AlulaImeNative]::AttachThreadInput($currentThread, $foregroundThread, $true)
      $attachedTarget = [AlulaImeNative]::AttachThreadInput($targetThread, $foregroundThread, $true)
    }
    [AlulaImeNative]::BringWindowToTop($handle) | Out-Null
    [AlulaImeNative]::SetForegroundWindow($handle) | Out-Null
  } finally {
    if ($attachedTarget) { [AlulaImeNative]::AttachThreadInput($targetThread, $foregroundThread, $false) | Out-Null }
    if ($attachedCurrent) { [AlulaImeNative]::AttachThreadInput($currentThread, $foregroundThread, $false) | Out-Null }
  }
  Start-Sleep -Milliseconds 1800
  Assert-TargetForeground
  Write-Output "foreground=$([AlulaImeNative]::GetForegroundWindow()) target=$handle pid=$($appProcess.Id) profile=$profileRoot"
  if ($PreflightOnly) {
    Start-Sleep -Milliseconds 1000
    Save-Window $handle 'windows-preflight.png'
    $records.Add([pscustomobject]@{
      platform = 'Windows 11'
      product = 'Alula Code Release'
      rustAbi = $coreVersion
      coreHashMatchesBundle = ($coreHash -eq $bundleHash)
      appPid = $appProcess.Id
      windowHandle = $handle.ToInt64()
      preflightOnly = $true
      keyboardEventsSent = $false
      profileRoot = $profileRoot
    })
  } else {
    Save-Window $handle 'windows-before.png'

    Click-Editor $handle
    Send-AltShift
    $layoutSwitched = $true
    Send-ControlKey 0x41
    Send-Letters 'nihao'
    Start-Sleep -Milliseconds 900
    Save-Window $handle 'windows-compose.png'
    Send-Key 0x20
    Start-Sleep -Milliseconds 800
    Save-Window $handle 'windows-commit.png'

    Send-Letters 'zhongguo'
    Start-Sleep -Milliseconds 900
    Save-Window $handle 'windows-cancel-before.png'
    Send-Key 0x1B
    Start-Sleep -Milliseconds 600
    Save-Window $handle 'windows-cancelled.png'

    Send-Letters 'beijing'
    Start-Sleep -Milliseconds 700
    Save-Window $handle 'windows-tab-before.png'
    Send-Key 0x09
    Start-Sleep -Milliseconds 700
    Send-Key 0x1B
    Start-Sleep -Milliseconds 400

    Send-Letters 'beijing'
    Start-Sleep -Milliseconds 700
    Save-Window $handle 'windows-focus-before.png'
    Click-WindowPoint $handle 24 80
    Start-Sleep -Milliseconds 500
    Save-Window $handle 'windows-focus-after.png'
    Send-Key 0x1B

    $records.Add([pscustomobject]@{
      platform = 'Windows 11'
      product = 'Alula Code Release'
      inputMethod = 'Microsoft Pinyin (user input profile)'
      rustAbi = $coreVersion
      coreHashMatchesBundle = ($coreHash -eq $bundleHash)
      appPid = $appProcess.Id
      windowHandle = $handle.ToInt64()
      originalForegroundCaptured = ($originalForeground -ne [IntPtr]::Zero)
      finalForegroundBeforeRestore = [AlulaImeNative]::GetForegroundWindow().ToInt64()
      screenshots = @('windows-before.png', 'windows-compose.png', 'windows-commit.png', 'windows-cancel-before.png', 'windows-cancelled.png', 'windows-tab-before.png', 'windows-focus-before.png', 'windows-focus-after.png')
      sequences = @('Ctrl+A; Alt+Shift; nihao; Space', 'zhongguo; Escape', 'beijing; Tab (candidate navigation)', 'beijing; click Explorer Activity Bar')
      profileRoot = $profileRoot
    })
  }
} finally {
  if ($layoutSwitched -and [AlulaImeNative]::GetForegroundWindow() -eq $script:targetHandle) {
    Send-AltShift
  }
  if ($null -ne $appProcess) {
    Stop-Process -Id $appProcess.Id -Force -ErrorAction SilentlyContinue
    Wait-Process -Id $appProcess.Id -Timeout 5 -ErrorAction SilentlyContinue
  }
  if ($null -ne $originalUserProfile) { $env:USERPROFILE = $originalUserProfile }
  if ($null -ne $originalHome) { $env:HOME = $originalHome }
  if ($null -ne $originalAppData) { $env:APPDATA = $originalAppData }
  if ($null -ne $originalLocalAppData) { $env:LOCALAPPDATA = $originalLocalAppData }
  if ($originalForeground -ne [IntPtr]::Zero -and [AlulaImeNative]::IsWindow($originalForeground)) {
    [AlulaImeNative]::SetForegroundWindow($originalForeground) | Out-Null
  }
}

$resultName = if ($PreflightOnly) { 'windows-preflight.json' } else { 'windows-ime-replay.json' }
$resultPath = Join-Path $OutputDirectory $resultName
$records | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 $resultPath
Write-Output "result=$resultPath"
