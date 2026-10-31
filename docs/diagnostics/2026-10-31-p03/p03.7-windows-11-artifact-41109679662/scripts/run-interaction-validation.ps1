param(
  [string]$RunName = 'msaa-action',
  [string]$ArtifactDirectory = (Join-Path ([System.IO.Path]::GetTempPath()) 'alula-win-artifact-41109679662')
)

$ErrorActionPreference = 'Stop'

Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class AlulaWin11TestDesktopMsaa {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hwnd);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hwnd);
}
'@

$previousForeground = [AlulaWin11TestDesktopMsaa]::GetForegroundWindow()
$runRoot = Join-Path ([System.IO.Path]::GetTempPath()) "alula-p037-win11-$RunName"
$profileRoot = Join-Path $runRoot 'profile'
$outputRoot = Join-Path (Split-Path $PSScriptRoot -Parent) "$RunName-run"
$validator = Join-Path ([System.IO.Path]::GetTempPath()) 'alula-win-artifact-41109679662\validate-windows-artifact-win11.ps1'
$artifact = $ArtifactDirectory
$transcript = Join-Path $outputRoot 'transcript.txt'

if (Test-Path $runRoot) { throw "Isolated run path already exists: $runRoot" }
New-Item -ItemType Directory -Path $profileRoot -Force | Out-Null
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
$env:USERPROFILE = $profileRoot
Start-Transcript -Path $transcript -Force | Out-Null
$runExitCode = 0
try {
  & $validator -ArtifactDirectory $artifact -OutputDirectory $outputRoot -ExerciseInteractions
} catch {
  Write-Error $_
  $runExitCode = 1
} finally {
  Stop-Transcript | Out-Null
  if ($previousForeground -ne [IntPtr]::Zero -and [AlulaWin11TestDesktopMsaa]::IsWindow($previousForeground)) {
    [void][AlulaWin11TestDesktopMsaa]::SetForegroundWindow($previousForeground)
  }
}
exit $runExitCode
