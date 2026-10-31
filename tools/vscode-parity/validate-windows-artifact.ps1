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
    public string RootName { get; set; }
    public int ChildCount { get; set; }
    public System.Collections.Generic.List<AlulaArtifactMsaaNode> Nodes { get; private set; }
    public AlulaArtifactMsaaSnapshot() { Nodes = new System.Collections.Generic.List<AlulaArtifactMsaaNode>(); }
}

public sealed class AlulaArtifactMsaaNode
{
    public string Path { get; set; }
    public int ChildId { get; set; }
    public string Name { get; set; }
    public string Role { get; set; }
    public string Value { get; set; }
    public int ChildCount { get; set; }
    public string Error { get; set; }
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
        IAccessible root = null;
        try
        {
            Guid iid = IidIAccessible;
            int hr = AccessibleObjectFromWindow(window, 0xFFFFFFFC, ref iid, out root);
            snapshot.HResult = "0x" + hr.ToString("X8");
            if (hr != 0 || root == null)
            {
                snapshot.Error = "AccessibleObjectFromWindow did not return IAccessible.";
                return snapshot;
            }
            try { snapshot.RootName = root.get_accName(0); } catch { }
            try { snapshot.ChildCount = root.accChildCount; }
            catch (Exception error)
            {
                snapshot.Error = "accChildCount: " + error.Message;
                return snapshot;
            }
            Walk(root, snapshot, "", 1);
        }
        catch (Exception error) { snapshot.Error = error.ToString(); }
        finally
        {
            if (root != null && Marshal.IsComObject(root)) Marshal.FinalReleaseComObject(root);
        }
        return snapshot;
    }

    private static void Walk(IAccessible accessible, AlulaArtifactMsaaSnapshot snapshot, string parentPath, int depth)
    {
        if (accessible == null || depth > 8 || snapshot.Nodes.Count >= 250) return;
        int count = 0;
        try { count = Math.Min(accessible.accChildCount, 100); } catch { return; }
        for (int id = 1; id <= count && snapshot.Nodes.Count < 250; id++)
        {
            var node = new AlulaArtifactMsaaNode();
            node.Path = String.IsNullOrEmpty(parentPath) ? id.ToString() : parentPath + "." + id.ToString();
            node.ChildId = id;
            object raw = null;
            IAccessible nested = null;
            try
            {
                try { node.Name = accessible.get_accName(id); } catch (Exception error) { node.Error = error.Message; }
                try { node.Role = Convert.ToString(accessible.get_accRole(id)); } catch (Exception error) { node.Error = error.Message; }
                try { node.Value = accessible.get_accValue(id); } catch (Exception error) { node.Error = error.Message; }
                try { raw = accessible.get_accChild(id); } catch { }
                nested = raw as IAccessible;
                if (nested == null && raw != null && Marshal.IsComObject(raw))
                {
                    IntPtr unknown = Marshal.GetIUnknownForObject(raw);
                    try { nested = (IAccessible)Marshal.GetTypedObjectForIUnknown(unknown, typeof(IAccessible)); }
                    catch { }
                    finally { Marshal.Release(unknown); }
                }
                if (nested != null && !Object.ReferenceEquals(nested, accessible))
                {
                    try
                    {
                        node.ChildCount = nested.accChildCount;
                        Walk(nested, snapshot, node.Path, depth + 1);
                    }
                    catch (Exception error) { node.Error = error.Message; }
                }
                snapshot.Nodes.Add(node);
            }
            catch { }
            finally
            {
                if (nested != null && Marshal.IsComObject(nested) && !Object.ReferenceEquals(nested, accessible))
                    Marshal.FinalReleaseComObject(nested);
                else if (nested == null && raw != null && Marshal.IsComObject(raw))
                    Marshal.FinalReleaseComObject(raw);
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
    for ($y = 0; $y -lt $height; $y += [Math]::Max(1, [int]($height / 80))) {
      for ($x = 0; $x -lt $width; $x += [Math]::Max(1, [int]($width / 80))) {
        $pixel = $bitmap.GetPixel($x, $y)
        [void]$sampledColors.Add("$($pixel.R),$($pixel.G),$($pixel.B)")
      }
    }
  }
  finally { $graphics.Dispose(); $bitmap.Dispose() }
  $screenshotNonUniform = $sampledColors.Count -ge 12

  $child = [AlulaArtifactWindow]::GetWindow($window, 5)
  $uiaAvailable = $false
  $uiaError = $null
  $uiaRoots = @()
  $uiaRoot = $null
  $uiaDescendants = $null
  $uiaElement = $null
  try {
    Add-Type -AssemblyName UIAutomationClient
    $uiaTargets = @(
      [pscustomobject]@{ name = 'topLevelWindow'; handle = $window },
      [pscustomobject]@{ name = 'flutterChildWindow'; handle = $child }
    )
    foreach ($target in $uiaTargets) {
      $targetElements = @()
      $targetError = $null
      try {
        $uiaRoot = [System.Windows.Automation.AutomationElement]::FromHandle($target.handle)
        $uiaDescendants = $uiaRoot.FindAll(
          [System.Windows.Automation.TreeScope]::Subtree,
          [System.Windows.Automation.Condition]::TrueCondition)
        $uiaAvailable = $true
        for ($index = 0; $index -lt [Math]::Min($uiaDescendants.Count, 150); $index++) {
          try {
            $uiaElement = $uiaDescendants.Item($index)
            $current = $uiaElement.Current
            $targetElements += [ordered]@{
              name = $current.Name
              automationId = $current.AutomationId
              className = $current.ClassName
              frameworkId = $current.FrameworkId
              controlType = $current.ControlType.ProgrammaticName
              isControlElement = $current.IsControlElement
              isContentElement = $current.IsContentElement
            }
          }
          catch [System.Windows.Automation.ElementNotAvailableException] { }
        }
      }
      catch {
        $targetError = $_.Exception.Message
        if ($null -eq $uiaError) { $uiaError = $targetError }
      }
      $uiaRoots += [ordered]@{
        target = $target.name
        elementCount = if ($uiaDescendants) { $uiaDescendants.Count } else { 0 }
        elements = @($targetElements)
        error = $targetError
      }
      $uiaElement = $null
      $current = $null
      $uiaDescendants = $null
      $uiaRoot = $null
    }
  }
  catch { $uiaError = $_.Exception.Message }

  # Query UI Automation before MSAA. Flutter enables its semantic tree when an
  # accessibility client inspects the native view.
  $msaaRoots = @()
  $msaaAvailable = $false
  $msaaError = $null
  $msaaTargets = @(
    [pscustomobject]@{ name = 'topLevelWindow'; handle = $window },
    [pscustomobject]@{ name = 'flutterChildWindow'; handle = $child }
  )
  foreach ($target in $msaaTargets) {
    $snapshot = [AlulaArtifactMsaa]::Capture($target.handle)
    if ($snapshot.HResult -eq '0x00000000') {
      $msaaAvailable = $true
    }
    elseif ($null -eq $msaaError) {
      $msaaError = $snapshot.Error
    }
    $msaaRoots += [ordered]@{
      target = $target.name
      hresult = $snapshot.HResult
      rootName = $snapshot.RootName
      childCount = $snapshot.ChildCount
      nodes = @($snapshot.Nodes)
      error = $snapshot.Error
    }
  }
  $flutterMsaaRoot = $msaaRoots | Where-Object { $_.target -eq 'flutterChildWindow' } | Select-Object -First 1
  $accessibleValues = New-Object 'System.Collections.Generic.List[string]'
  if ($flutterMsaaRoot -and ![string]::IsNullOrWhiteSpace($flutterMsaaRoot.rootName)) {
    $accessibleValues.Add($flutterMsaaRoot.rootName)
  }
  if ($flutterMsaaRoot) {
    foreach ($node in $flutterMsaaRoot.nodes) {
      if (![string]::IsNullOrWhiteSpace($node.Name)) { $accessibleValues.Add($node.Name) }
      if (![string]::IsNullOrWhiteSpace($node.Value)) { $accessibleValues.Add($node.Value) }
    }
  }
  $accessibleText = $accessibleValues -join "`n"
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
    screenshotNonUniform = $screenshotNonUniform
    screenshot = 'windows-artifact-client.png'
    screenshotSha256 = (Get-FileHash (Join-Path $OutputDirectory 'windows-artifact-client.png') -Algorithm SHA256).Hash.ToLowerInvariant()
    systemUsesLightTheme = if ($theme) { [bool]$theme.SystemUsesLightTheme } else { $null }
    appsUseLightTheme = if ($theme) { [bool]$theme.AppsUseLightTheme } else { $null }
    uiAutomationAvailable = $uiaAvailable
    uiAutomationError = $uiaError
    uiAutomationRoots = @($uiaRoots)
    msaaAvailable = $msaaAvailable
    msaaError = $msaaError
    msaaRoots = @($msaaRoots)
    flutterMsaaChildCount = if ($flutterMsaaRoot) { $flutterMsaaRoot.childCount } else { 0 }
    flutterMsaaNodeCount = if ($flutterMsaaRoot) { @($flutterMsaaRoot.nodes).Count } else { 0 }
    expectedMsaaText = $expectedMsaaText
    missingMsaaText = $missingMsaaText
  } | ConvertTo-Json -Depth 8 | Set-Content -Path $metadataPath -Encoding utf8
  $msaaNodeCount = if ($flutterMsaaRoot) { @($flutterMsaaRoot.nodes).Count } else { 0 }
  if (!$screenshotNonUniform) { throw "Client capture appears blank or uniform ($($sampledColors.Count) sampled colors)" }
  if (!$msaaAvailable) { throw "Flutter window MSAA unavailable: $msaaError" }
  if ($missingMsaaText.Count -gt 0) { throw "MSAA tree is missing expected text: $($missingMsaaText -join ', ')" }
}
catch {
  $validationError = $_.Exception.Message
}
finally {
  # Drop all UIA provider proxies even when a semantic assertion fails. Leaving
  # them alive while WM_CLOSE tears down Flutter can crash the desktop process.
  $accessibleValues = $null
  $node = $null
  $uiaElement = $null
  $current = $null
  $uiaDescendants = $null
  $uiaRoot = $null
  $uiaTargets = $null
  $msaaTargets = $null
  $target = $null
  $snapshot = $null
  $flutterMsaaRoot = $null
  [GC]::Collect()
  [GC]::WaitForPendingFinalizers()

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
      $metadata | ConvertTo-Json -Depth 8 | Set-Content -Path $metadataPath -Encoding utf8
    }
  }
  catch {
    $closeError = $_.Exception.Message
  }
  if (!$closed -and !$closeError) {
    $closeError = "Release artifact did not close cleanly (posted=$wmCloseSent timeout=$closeTimedOut exit=$exitCode)"
  }
}

$controlClose = [ordered]@{
  accessibilityQueried = $false
  windowCreated = $false
  wmClosePosted = $false
  closeTimedOut = $false
  exitCode = $null
  error = $null
}
$controlProcess = $null
$controlWindow = [IntPtr]::Zero
try {
  # Compare with a second launch that receives no UIA/MSAA queries. This tells
  # us whether the exact older binary crashes on WM_CLOSE independently of the
  # accessibility inspection performed above.
  $controlProcess = Start-Process -FilePath $exe.FullName -WorkingDirectory $exe.DirectoryName -PassThru -WindowStyle Normal
  $controlDeadline = (Get-Date).AddSeconds(35)
  do {
    $controlProcess.Refresh()
    if ($controlProcess.HasExited) { throw "Control launch exited during startup with code $($controlProcess.ExitCode)" }
    $controlWindow = $controlProcess.MainWindowHandle
    if ($controlWindow -eq [IntPtr]::Zero) { Start-Sleep -Milliseconds 250 }
  } while ($controlWindow -eq [IntPtr]::Zero -and (Get-Date) -lt $controlDeadline)
  if ($controlWindow -eq [IntPtr]::Zero) { throw 'Control launch did not create a top-level window' }
  $controlClose.windowCreated = $true
  $controlClose.wmClosePosted = [AlulaArtifactWindow]::PostMessage(
    $controlWindow, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
  if (!$controlProcess.WaitForExit(10000)) {
    $controlClose.closeTimedOut = $true
    try { $controlProcess.Kill() } catch [System.InvalidOperationException] { }
    $controlProcess.WaitForExit(10000) | Out-Null
  }
  $controlProcess.Refresh()
  $controlClose.exitCode = if ($controlProcess.HasExited) { $controlProcess.ExitCode } else { $null }
}
catch {
  $controlClose.error = $_.Exception.Message
}
finally {
  if ($controlProcess) {
    try {
      if (!$controlProcess.HasExited) {
        $controlProcess.Kill()
        $controlProcess.WaitForExit(10000) | Out-Null
      }
    }
    catch [System.InvalidOperationException] { }
    $controlProcess.Dispose()
  }
}
$controlPath = Join-Path $OutputDirectory 'no-accessibility-close-control.json'
$controlClose | ConvertTo-Json -Depth 3 | Set-Content -Path $controlPath -Encoding utf8
if (Test-Path $metadataPath) {
  $metadata = Get-Content $metadataPath -Raw | ConvertFrom-Json
  $metadata | Add-Member -NotePropertyName noAccessibilityCloseControl -NotePropertyValue $controlClose -Force
  $metadata | ConvertTo-Json -Depth 9 | Set-Content -Path $metadataPath -Encoding utf8
}

if ($validationError -or $closeError) {
  $failureSummary = @()
  if ($validationError) { $failureSummary += "Artifact validation failed: $validationError" }
  if ($closeError) { $failureSummary += "Close validation failed: $closeError" }
  throw ($failureSummary -join '; ')
}

Write-Host "Validated visible client ${width}x${height}; DPI=$dpi; MSAA text nodes=$msaaNodeCount; screenshot=$screenshot"
