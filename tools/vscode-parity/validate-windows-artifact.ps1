param(
  [Parameter(Mandatory = $true)][string]$ArtifactDirectory,
  [Parameter(Mandatory = $true)][string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Accessibility

Add-Type -ReferencedAssemblies @([Accessibility.IAccessible].Assembly.Location) -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using Accessibility;

public sealed class AlulaArtifactMsaaSnapshot
{
    public string HResult { get; set; }
    public string Error { get; set; }
    public string[] Text { get; set; }
    public AlulaArtifactMsaaSnapshot() { Text = new string[0]; }
}

public static class AlulaArtifactMsaa
{
    private static readonly Guid IidIAccessible =
        new Guid("618736E0-3C3D-11CF-810C-00AA00389B71");

    [DllImport("oleacc.dll", PreserveSig = true)]
    private static extern int AccessibleObjectFromWindow(
        IntPtr window,
        uint objectId,
        ref Guid interfaceId,
        [MarshalAs(UnmanagedType.Interface)] out IAccessible accessible);

    public static AlulaArtifactMsaaSnapshot Capture(IntPtr window)
    {
        var snapshot = new AlulaArtifactMsaaSnapshot();
        try
        {
            Guid iid = IidIAccessible;
            IAccessible root;
            int hr = AccessibleObjectFromWindow(window, 0xFFFFFFFC, ref iid, out root);
            snapshot.HResult = "0x" + hr.ToString("X8");
            if (hr == 0 && root != null) Walk(root, snapshot, 0);
        }
        catch (Exception error) { snapshot.Error = error.ToString(); }
        return snapshot;
    }

    private static void Add(AlulaArtifactMsaaSnapshot snapshot, string value)
    {
        if (!String.IsNullOrWhiteSpace(value) && snapshot.Text.Length < 2000)
        {
            string[] expanded = new string[snapshot.Text.Length + 1];
            Array.Copy(snapshot.Text, expanded, snapshot.Text.Length);
            expanded[expanded.Length - 1] = value;
            snapshot.Text = expanded;
        }
    }

    private static void Walk(IAccessible accessible, AlulaArtifactMsaaSnapshot snapshot, int depth)
    {
        if (accessible == null || depth > 8 || snapshot.Text.Length >= 2000) return;
        try { Add(snapshot, accessible.get_accName(0)); } catch { }
        try { Add(snapshot, accessible.get_accValue(0)); } catch { }
        int count = 0;
        try { count = Math.Min(accessible.accChildCount, 100); } catch { return; }
        for (int id = 1; id <= count && snapshot.Text.Length < 2000; id++)
        {
            object raw = null;
            IAccessible nested = null;
            try
            {
                try { Add(snapshot, accessible.get_accName(id)); } catch { }
                try { Add(snapshot, accessible.get_accValue(id)); } catch { }
                try { raw = accessible.get_accChild(id); } catch { }
                nested = raw as IAccessible;
                if (nested == null && raw != null && Marshal.IsComObject(raw))
                {
                    IntPtr unknown = Marshal.GetIUnknownForObject(raw);
                    try { nested = (IAccessible)Marshal.GetTypedObjectForIUnknown(unknown, typeof(IAccessible)); }
                    catch { }
                    finally { Marshal.Release(unknown); }
                }
                if (nested != null) Walk(nested, snapshot, depth + 1);
            }
            catch { }
            finally
            {
                if (nested != null && Marshal.IsComObject(nested)) Marshal.ReleaseComObject(nested);
                else if (nested == null && raw != null && Marshal.IsComObject(raw)) Marshal.ReleaseComObject(raw);
            }
        }
    }
}
'@

Add-Type @'
using System;
using System.Runtime.InteropServices;
public struct AlulaArtifactRect { public int Left; public int Top; public int Right; public int Bottom; }
public struct AlulaArtifactPoint { public int X; public int Y; }
public static class AlulaArtifactWindow
{
    [DllImport("user32.dll", SetLastError = true)] public static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll", SetLastError = true)] public static extern bool GetClientRect(IntPtr hwnd, out AlulaArtifactRect rect);
    [DllImport("user32.dll", SetLastError = true)] public static extern bool ClientToScreen(IntPtr hwnd, ref AlulaArtifactPoint point);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hwnd, int command);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr hwnd, uint command);
    [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr hwnd);
    [DllImport("user32.dll", SetLastError = true)] public static extern bool PostMessage(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam);
}
'@

$exe = Get-ChildItem -LiteralPath $ArtifactDirectory -Filter 'alula_app.exe' -File -Recurse | Select-Object -First 1
if (!$exe) { throw "alula_app.exe was not found under $ArtifactDirectory" }
if (!(Test-Path (Join-Path $exe.DirectoryName 'alula_core.dll'))) { throw 'Artifact is missing alula_core.dll' }

$process = Start-Process -FilePath $exe.FullName -WorkingDirectory $exe.DirectoryName -PassThru -WindowStyle Normal
$window = [IntPtr]::Zero
$metadataPath = Join-Path $OutputDirectory 'metadata.json'
$validationError = $null
$closeError = $null
$width = $null
$height = $null
$dpi = $null
$msaaNodeCount = 0
$screenshot = $null
try {
  $deadline = (Get-Date).AddSeconds(35)
  do {
    $process.Refresh()
    if ($process.HasExited) { throw "Release artifact exited during startup with code $($process.ExitCode)" }
    $window = $process.MainWindowHandle
    if ($window -eq [IntPtr]::Zero) { Start-Sleep -Milliseconds 250 }
  } while ($window -eq [IntPtr]::Zero -and (Get-Date) -lt $deadline)
  if ($window -eq [IntPtr]::Zero) { throw 'Release artifact did not create a top-level window' }

  [AlulaArtifactWindow]::ShowWindow($window, 9) | Out-Null
  [AlulaArtifactWindow]::SetForegroundWindow($window) | Out-Null
  Start-Sleep -Seconds 3
  if (![AlulaArtifactWindow]::IsWindowVisible($window)) { throw 'Release artifact window is not visible' }

  $client = New-Object AlulaArtifactRect
  if (![AlulaArtifactWindow]::GetClientRect($window, [ref]$client)) { throw 'GetClientRect failed' }
  $width = $client.Right - $client.Left
  $height = $client.Bottom - $client.Top
  if ($width -lt 640 -or $height -lt 480) { throw "Unexpected client area ${width}x${height}" }
  $origin = New-Object AlulaArtifactPoint
  if (![AlulaArtifactWindow]::ClientToScreen($window, [ref]$origin)) { throw 'ClientToScreen failed' }
  $bitmap = [System.Drawing.Bitmap]::new($width, $height)
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  try {
    $graphics.CopyFromScreen($origin.X, $origin.Y, 0, 0, $bitmap.Size)
    $screenshot = Join-Path $OutputDirectory 'windows-artifact-client.png'
    $bitmap.Save($screenshot, [System.Drawing.Imaging.ImageFormat]::Png)
    $sampledColors = [System.Collections.Generic.HashSet[string]]::new()
    for ($y = 0; $y -lt $height; $y += [Math]::Max(1, [int]($height / 20))) {
      for ($x = 0; $x -lt $width; $x += [Math]::Max(1, [int]($width / 20))) {
        $pixel = $bitmap.GetPixel($x, $y)
        [void]$sampledColors.Add("$($pixel.R),$($pixel.G),$($pixel.B)")
      }
    }
  }
  finally { $graphics.Dispose(); $bitmap.Dispose() }
  if ($sampledColors.Count -lt 12) { throw "Client capture appears blank or uniform ($($sampledColors.Count) sampled colors)" }

  $child = [AlulaArtifactWindow]::GetWindow($window, 5)
  $msaa = [AlulaArtifactMsaa]::Capture($child)
  $accessibleText = $msaa.Text -join "`n"
  $expectedMsaaText = @('打开文件夹', 'UTF-8. UTF-8', 'LF. 行尾格式', '打开一个文件夹开始工作')
  $missingMsaaText = @($expectedMsaaText | Where-Object { !$accessibleText.Contains($_) })

  $theme = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -ErrorAction SilentlyContinue
  $os = Get-CimInstance Win32_OperatingSystem
  $dpi = [AlulaArtifactWindow]::GetDpiForWindow($window)
  [ordered]@{
    artifactSourceCommit = 'd5319369c5b5d569954e0d816daf325f3bc12a51'
    artifactFile = $exe.FullName
    processId = $process.Id
    osCaption = $os.Caption
    osVersion = $os.Version
    osBuild = $os.BuildNumber
    clientWidth = $width
    clientHeight = $height
    dpi = $dpi
    sampledColorCount = $sampledColors.Count
    screenshot = 'windows-artifact-client.png'
    screenshotSha256 = (Get-FileHash (Join-Path $OutputDirectory 'windows-artifact-client.png') -Algorithm SHA256).Hash.ToLowerInvariant()
    systemUsesLightTheme = if ($theme) { [bool]$theme.SystemUsesLightTheme } else { $null }
    appsUseLightTheme = if ($theme) { [bool]$theme.AppsUseLightTheme } else { $null }
    msaaHResult = $msaa.HResult
    msaaError = $msaa.Error
    msaaText = @($msaa.Text)
    expectedMsaaText = $expectedMsaaText
    missingMsaaText = $missingMsaaText
  } | ConvertTo-Json -Depth 5 | Set-Content -Path $metadataPath -Encoding utf8
  $msaaNodeCount = $msaa.Text.Count
  if ($msaa.HResult -ne '0x00000000') { throw "Flutter child window MSAA unavailable: $($msaa.HResult) $($msaa.Error)" }
  if ($missingMsaaText.Count -gt 0) { throw "MSAA tree is missing expected text: $($missingMsaaText -join ', ')" }
  $msaa = $null
  [GC]::Collect()
  [GC]::WaitForPendingFinalizers()
}
catch {
  $validationError = $_.Exception.Message
}
finally {
  $wmCloseSent = $false
  $closeTimedOut = $false
  $exitCode = $null
  $closed = $false
  try {
    if (!$process.HasExited -and $window -ne [IntPtr]::Zero) {
      $wmCloseSent = [AlulaArtifactWindow]::PostMessage($window, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
    }
    if (!$process.WaitForExit(10000)) {
      $closeTimedOut = $true
      try { $process.Kill() } catch [System.InvalidOperationException] { }
      $process.WaitForExit(10000) | Out-Null
    }
    $process.Refresh()
    $exitCode = if ($process.HasExited) { $process.ExitCode } else { $null }
    $closed = $wmCloseSent -and !$closeTimedOut -and $exitCode -eq 0
    if (Test-Path $metadataPath) {
      $metadata = Get-Content $metadataPath -Raw | ConvertFrom-Json
      $metadata | Add-Member -NotePropertyName validationError -NotePropertyValue $validationError -Force
      $metadata | Add-Member -NotePropertyName wmClosePosted -NotePropertyValue $wmCloseSent -Force
      $metadata | Add-Member -NotePropertyName closeTimedOut -NotePropertyValue $closeTimedOut -Force
      $metadata | Add-Member -NotePropertyName gracefulClose -NotePropertyValue $closed -Force
      $metadata | Add-Member -NotePropertyName exitCode -NotePropertyValue $exitCode -Force
      $metadata | ConvertTo-Json -Depth 5 | Set-Content -Path $metadataPath -Encoding utf8
    }
  }
  catch {
    $closeError = $_.Exception.Message
  }
  if (!$closed -and !$closeError) {
    $closeError = "Release artifact did not close cleanly (posted=$wmCloseSent timeout=$closeTimedOut exit=$exitCode)"
  }
}

if ($validationError -or $closeError) {
  $failureSummary = @()
  if ($validationError) { $failureSummary += "Artifact validation failed: $validationError" }
  if ($closeError) { $failureSummary += "Close validation failed: $closeError" }
  throw ($failureSummary -join '; ')
}

Write-Host "Validated visible client ${width}x${height}; DPI=$dpi; MSAA text nodes=$msaaNodeCount; screenshot=$screenshot"
