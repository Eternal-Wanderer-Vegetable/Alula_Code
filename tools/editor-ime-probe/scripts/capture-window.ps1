param(
  [Parameter(Mandatory = $true)]
  [string]$OutputPath
)

Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class ProbeWindowNative {
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
  public static extern bool SetForegroundWindow(IntPtr hWnd);

  [DllImport("user32.dll")]
  public static extern bool ShowWindow(IntPtr hWnd, int command);

  [DllImport("user32.dll")]
  public static extern bool BringWindowToTop(IntPtr hWnd);

  [DllImport("user32.dll")]
  public static extern bool IsIconic(IntPtr hWnd);

  [DllImport("user32.dll")]
  public static extern IntPtr GetForegroundWindow();

  [DllImport("user32.dll")]
  public static extern bool SetWindowPos(
    IntPtr hWnd,
    IntPtr hWndInsertAfter,
    int x,
    int y,
    int cx,
    int cy,
    uint flags
  );
}
"@

$process = Get-Process -Name editor_ime_probe |
  Where-Object { $_.MainWindowHandle -ne 0 } |
  Select-Object -First 1
if ($null -eq $process) {
  throw "editor_ime_probe window is not running"
}

$rect = New-Object ProbeWindowNative+Rect
if (-not [ProbeWindowNative]::GetWindowRect($process.MainWindowHandle, [ref]$rect)) {
  throw "GetWindowRect failed"
}
Write-Output "before handle=$($process.MainWindowHandle) iconic=$([ProbeWindowNative]::IsIconic($process.MainWindowHandle)) rect=$($rect.Left),$($rect.Top),$($rect.Right),$($rect.Bottom)"
[ProbeWindowNative]::ShowWindow($process.MainWindowHandle, 9) | Out-Null
[ProbeWindowNative]::SetWindowPos(
  $process.MainWindowHandle,
  [IntPtr](-1),
  0,
  0,
  0,
  0,
  0x0001 -bor 0x0002
) | Out-Null
[ProbeWindowNative]::BringWindowToTop($process.MainWindowHandle) | Out-Null
[ProbeWindowNative]::SetForegroundWindow($process.MainWindowHandle) | Out-Null
Start-Sleep -Milliseconds 400
[ProbeWindowNative]::GetWindowRect($process.MainWindowHandle, [ref]$rect) | Out-Null
Write-Output "after foreground=$([ProbeWindowNative]::GetForegroundWindow()) rect=$($rect.Left),$($rect.Top),$($rect.Right),$($rect.Bottom)"

$width = $rect.Right - $rect.Left
$height = $rect.Bottom - $rect.Top
$bitmap = New-Object System.Drawing.Bitmap($width, $height)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bitmap.Size)

$parent = Split-Path -Parent $OutputPath
if (-not (Test-Path $parent)) {
  New-Item -ItemType Directory -Path $parent -Force | Out-Null
}
$bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose()
$bitmap.Dispose()
[ProbeWindowNative]::SetWindowPos(
  $process.MainWindowHandle,
  [IntPtr](-2),
  0,
  0,
  0,
  0,
  0x0001 -bor 0x0002
) | Out-Null
Write-Output "saved=$OutputPath size=$width x $height process=$($process.Id)"
