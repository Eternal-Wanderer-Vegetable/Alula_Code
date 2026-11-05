param(
  [Parameter(Mandatory = $true)][string]$ArtifactDirectory,
  [Parameter(Mandatory = $true)][string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class AlulaWin11ScreenReaderNative {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hwnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hwnd, int command);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hwnd);
  [DllImport("user32.dll", SetLastError = true)] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);
  [DllImport("user32.dll", SetLastError = true)] public static extern bool AttachThreadInput(uint attach, uint attachTo, bool attachInput);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll", SetLastError = true)] public static extern bool GetClientRect(IntPtr hwnd, out RECT rect);
  [DllImport("user32.dll", SetLastError = true)] public static extern bool ClientToScreen(IntPtr hwnd, ref POINT point);
  [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr hwnd);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  public static uint ForegroundProcessId() {
    uint pid; GetWindowThreadProcessId(GetForegroundWindow(), out pid); return pid;
  }
  public static void FocusWindow(IntPtr hwnd) {
    uint ignored;
    IntPtr foreground = GetForegroundWindow();
    uint foregroundThread = GetWindowThreadProcessId(foreground, out ignored);
    uint targetThread = GetWindowThreadProcessId(hwnd, out ignored);
    uint currentThread = GetCurrentThreadId();
    bool attachCurrent = foregroundThread != 0 && foregroundThread != currentThread && AttachThreadInput(currentThread, foregroundThread, true);
    bool attachTarget = foregroundThread != 0 && foregroundThread != targetThread && AttachThreadInput(targetThread, foregroundThread, true);
    try { ShowWindow(hwnd, 9); BringWindowToTop(hwnd); SetForegroundWindow(hwnd); }
    finally {
      if (attachTarget) AttachThreadInput(targetThread, foregroundThread, false);
      if (attachCurrent) AttachThreadInput(currentThread, foregroundThread, false);
    }
  }
}
'@

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$transcriptPath = Join-Path $OutputDirectory 'transcript.txt'
Start-Transcript -Path $transcriptPath -Force | Out-Null
$originalForeground = [AlulaWin11ScreenReaderNative]::GetForegroundWindow()
$originalUserProfile = $env:USERPROFILE
$originalHome = $env:HOME
$runProfile = Join-Path $env:TEMP "alula-win11-narrator-$PID"
$narratorProcess = $null
$narratorWasRunning = @(Get-Process -Name Narrator -ErrorAction SilentlyContinue).Count -gt 0
$appProcess = $null
$result = [ordered]@{
  osCaption = (Get-CimInstance Win32_OperatingSystem).Caption
  osVersion = [Environment]::OSVersion.VersionString
  artifactDirectory = $ArtifactDirectory
  narratorWasRunning = $narratorWasRunning
  narratorStartedByRun = $false
  narratorProcessObserved = $false
  narratorSpeechAudioCaptured = $false
  uiaDescendantCount = 0
  uiaSemanticNames = @()
  uiaLegacyAccessibleCount = 0
  focusTraversal = @()
  expectedSemanticText = @('打开文件夹', 'UTF-8. UTF-8', 'LF. 行尾格式', '打开一个文件夹开始工作')
  missingSemanticText = @()
  screenshot = 'screenreader-window.png'
  error = $null
}

try {
  if ($narratorWasRunning) { throw 'Narrator was already running; refusing to disturb an existing screen-reader session.' }
  if (Test-Path $runProfile) { throw "Temporary profile already exists: $runProfile" }
  New-Item -ItemType Directory -Path $runProfile -Force | Out-Null
  $env:USERPROFILE = $runProfile
  $env:HOME = $runProfile

  $exe = Join-Path $ArtifactDirectory 'alula_app.exe'
  if (!(Test-Path -LiteralPath $exe)) { throw "Missing artifact executable: $exe" }
  $appProcess = Start-Process -FilePath $exe -WorkingDirectory $ArtifactDirectory -PassThru
  $window = [IntPtr]::Zero
  $deadline = (Get-Date).AddSeconds(35)
  do {
    $appProcess.Refresh()
    if ($appProcess.HasExited) { throw "Alula exited during startup with code $($appProcess.ExitCode)" }
    $window = $appProcess.MainWindowHandle
    if ($window -eq [IntPtr]::Zero) { Start-Sleep -Milliseconds 250 }
  } while ($window -eq [IntPtr]::Zero -and (Get-Date) -lt $deadline)
  if ($window -eq [IntPtr]::Zero) { throw 'Alula did not create a top-level window' }

  $narratorPath = Join-Path $env:WINDIR 'System32\Narrator.exe'
  $narratorProcess = Start-Process -FilePath $narratorPath -PassThru
  $result.narratorStartedByRun = $true
  Start-Sleep -Seconds 2
  $result.narratorProcessObserved = @(Get-Process -Name Narrator -ErrorAction SilentlyContinue).Count -gt 0

  $shell = New-Object -ComObject WScript.Shell
  for ($attempt = 0; $attempt -lt 8; $attempt++) {
    [void]$shell.AppActivate($appProcess.Id)
    [AlulaWin11ScreenReaderNative]::FocusWindow($window)
    Start-Sleep -Milliseconds 300
    if ([AlulaWin11ScreenReaderNative]::ForegroundProcessId() -eq [uint32]$appProcess.Id) { break }
    [System.Windows.Forms.SendKeys]::SendWait('%{TAB}')
    Start-Sleep -Milliseconds 150
  }
  if ([AlulaWin11ScreenReaderNative]::ForegroundProcessId() -ne [uint32]$appProcess.Id) {
    throw "Could not focus Alula while Narrator was running; foreground PID=$([AlulaWin11ScreenReaderNative]::ForegroundProcessId())"
  }

  $root = [System.Windows.Automation.AutomationElement]::FromHandle($window)
  Start-Sleep -Seconds 2
  $elements = $root.FindAll([System.Windows.Automation.TreeScope]::Subtree, [System.Windows.Automation.Condition]::TrueCondition)
  $names = New-Object 'System.Collections.Generic.List[string]'
  $legacyCount = 0
  foreach ($element in $elements) {
    $name = $element.Current.Name
    if (![string]::IsNullOrWhiteSpace($name)) { $names.Add($name) }
    try {
      $legacy = $element.GetCurrentPattern([System.Windows.Automation.LegacyIAccessiblePattern]::Pattern)
      if ($null -ne $legacy) { $legacyCount++ }
    } catch { }
  }
  $result.uiaDescendantCount = $elements.Count
  $result.uiaLegacyAccessibleCount = $legacyCount
  $result.uiaSemanticNames = @($names | Select-Object -Unique)
  $result.missingSemanticText = @($result.expectedSemanticText | Where-Object {
    $expected = $_
    !(@($result.uiaSemanticNames | Where-Object { $_.Contains($expected) }).Count -gt 0)
  })

  for ($index = 0; $index -lt 14; $index++) {
    for ($focusAttempt = 0; $focusAttempt -lt 5; $focusAttempt++) {
      if ([AlulaWin11ScreenReaderNative]::ForegroundProcessId() -eq [uint32]$appProcess.Id) { break }
      [void]$shell.AppActivate($appProcess.Id)
      [AlulaWin11ScreenReaderNative]::FocusWindow($window)
      Start-Sleep -Milliseconds 100
      if ([AlulaWin11ScreenReaderNative]::ForegroundProcessId() -ne [uint32]$appProcess.Id) {
        [System.Windows.Forms.SendKeys]::SendWait('%{TAB}')
      }
    }
    if ([AlulaWin11ScreenReaderNative]::ForegroundProcessId() -ne [uint32]$appProcess.Id) {
      throw "Alula lost foreground before Tab $($index + 1) after five recovery attempts; aborting input."
    }
    [System.Windows.Forms.SendKeys]::SendWait('{TAB}')
    Start-Sleep -Milliseconds 250
    $focus = [System.Windows.Automation.AutomationElement]::FocusedElement
    $legacyName = $null
    $legacyValue = $null
    try {
      $legacy = $focus.GetCurrentPattern([System.Windows.Automation.LegacyIAccessiblePattern]::Pattern)
      $legacyName = $legacy.Current.Name
      $legacyValue = $legacy.Current.Value
    } catch { }
    $result.focusTraversal += [ordered]@{
      index = $index + 1
      name = $focus.Current.Name
      controlType = $focus.Current.ControlType.ProgrammaticName
      automationId = $focus.Current.AutomationId
      isKeyboardFocusable = $focus.Current.IsKeyboardFocusable
      legacyName = $legacyName
      legacyValue = $legacyValue
    }
  }

  $rect = New-Object AlulaWin11ScreenReaderNative+RECT
  if (![AlulaWin11ScreenReaderNative]::GetClientRect($window, [ref]$rect)) { throw 'GetClientRect failed' }
  $origin = New-Object AlulaWin11ScreenReaderNative+POINT
  if (![AlulaWin11ScreenReaderNative]::ClientToScreen($window, [ref]$origin)) { throw 'ClientToScreen failed' }
  $bitmap = New-Object System.Drawing.Bitmap(($rect.Right - $rect.Left), ($rect.Bottom - $rect.Top))
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  try {
    $graphics.CopyFromScreen($origin.X, $origin.Y, 0, 0, $bitmap.Size)
    $bitmap.Save((Join-Path $OutputDirectory $result.screenshot), [System.Drawing.Imaging.ImageFormat]::Png)
  } finally { $graphics.Dispose(); $bitmap.Dispose() }
} catch {
  $result.error = $_.Exception.Message
} finally {
  if ($null -ne $appProcess) { Stop-Process -Id $appProcess.Id -Force -ErrorAction SilentlyContinue }
  if ($result.narratorStartedByRun -and $null -ne $narratorProcess) {
    Stop-Process -Id $narratorProcess.Id -Force -ErrorAction SilentlyContinue
  }
  if ($null -ne $originalUserProfile) { $env:USERPROFILE = $originalUserProfile }
  if ($null -ne $originalHome) { $env:HOME = $originalHome }
  if ($originalForeground -ne [IntPtr]::Zero) { [void][AlulaWin11ScreenReaderNative]::SetForegroundWindow($originalForeground) }
  $result | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 (Join-Path $OutputDirectory 'screenreader-result.json')
  Stop-Transcript | Out-Null
}

if ($result.error) { throw $result.error }
