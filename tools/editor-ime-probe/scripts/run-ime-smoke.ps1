param(
  [Parameter(Mandatory = $true)]
  [string]$OutputDirectory
)

Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class ProbeInputNative {
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
  public static extern bool BringWindowToTop(IntPtr hWnd);
  [DllImport("user32.dll")]
  public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")]
  public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")]
  public static extern void keybd_event(byte key, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")]
  public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")]
  public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
  [DllImport("user32.dll")]
  public static extern IntPtr GetForegroundWindow();
}
"@

$process = Get-Process -Name editor_ime_probe |
  Where-Object { $_.MainWindowHandle -ne 0 } |
  Select-Object -First 1
if ($null -eq $process) {
  throw "editor_ime_probe window is not running"
}
$rect = New-Object ProbeInputNative+Rect
if (-not [ProbeInputNative]::GetWindowRect($process.MainWindowHandle, [ref]$rect)) {
  throw "GetWindowRect failed"
}
# Dismiss any foreground capture palette left by the desktop hotkey before
# focusing this isolated probe window.
[ProbeInputNative]::keybd_event(0x1B, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 50
[ProbeInputNative]::keybd_event(0x1B, 0, 2, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 300
[ProbeInputNative]::ShowWindow($process.MainWindowHandle, 9) | Out-Null
[ProbeInputNative]::SetWindowPos(
  $process.MainWindowHandle,
  [IntPtr](-1),
  0,
  0,
  0,
  0,
  0x0001 -bor 0x0002
) | Out-Null
[ProbeInputNative]::BringWindowToTop($process.MainWindowHandle) | Out-Null
[ProbeInputNative]::SetForegroundWindow($process.MainWindowHandle) | Out-Null
Start-Sleep -Milliseconds 500
Write-Output "foreground=$([ProbeInputNative]::GetForegroundWindow()) target=$($process.MainWindowHandle)"

if (-not (Test-Path $OutputDirectory)) {
  New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}

function Send-Key([byte]$key) {
  [ProbeInputNative]::keybd_event($key, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 35
  [ProbeInputNative]::keybd_event($key, 0, 2, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 35
}

function Send-Letters([string]$text) {
  foreach ($character in $text.ToUpperInvariant().ToCharArray()) {
    Send-Key ([byte][char]$character)
  }
}

function Send-ShiftTap {
  [ProbeInputNative]::keybd_event(0x10, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 80
  [ProbeInputNative]::keybd_event(0x10, 0, 2, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 200
}

function Click-ClientPoint([int]$x, [int]$y) {
  [ProbeInputNative]::SetCursorPos($rect.Left + $x, $rect.Top + $y) | Out-Null
  [ProbeInputNative]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
  [ProbeInputNative]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 250
}

function Save-Window([string]$name) {
  $width = $rect.Right - $rect.Left
  $height = $rect.Bottom - $rect.Top
  $bitmap = New-Object System.Drawing.Bitmap($width, $height)
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  $graphics.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bitmap.Size)
  $path = Join-Path $OutputDirectory $name
  $bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  $graphics.Dispose()
  $bitmap.Dispose()
  Write-Output "saved=$path"
}

# The user profile has Microsoft Pinyin as its Chinese input method. Alt+Shift
# selects it; type a syllable, use Space to accept the first candidate, then
# type a second syllable and cancel it with Escape.
[ProbeInputNative]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero)
[ProbeInputNative]::keybd_event(0x10, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 100
[ProbeInputNative]::keybd_event(0x10, 0, 2, [UIntPtr]::Zero)
[ProbeInputNative]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 400
Click-ClientPoint 450 330
Send-Letters "nihao"
Start-Sleep -Milliseconds 800
Save-Window "p00.4-ime-composition.png"
Send-Key 0x20
Start-Sleep -Milliseconds 500
Save-Window "p00.4-ime-committed.png"
Send-Letters "zhongguo"
Start-Sleep -Milliseconds 800
Save-Window "p00.4-ime-cancel-before.png"
Send-Key 0x1B
Start-Sleep -Milliseconds 500
Save-Window "p00.4-ime-cancelled.png"

# Toggle Pinyin to Latin mode and send ordinary incremental input.
Send-ShiftTap
Send-Letters "xyz"
Start-Sleep -Milliseconds 700
Save-Window "p00.4-latin-incremental.png"

# Switch back to the input layout that was active before the run.
[ProbeInputNative]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero)
[ProbeInputNative]::keybd_event(0x10, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 100
[ProbeInputNative]::keybd_event(0x10, 0, 2, [UIntPtr]::Zero)
[ProbeInputNative]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)

[ProbeInputNative]::SetWindowPos(
  $process.MainWindowHandle,
  [IntPtr](-2),
  0,
  0,
  0,
  0,
  0x0001 -bor 0x0002
) | Out-Null
