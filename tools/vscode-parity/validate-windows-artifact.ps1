param(
  [Parameter(Mandatory = $true)][string]$ArtifactDirectory,
  [Parameter(Mandatory = $true)][string]$OutputDirectory,
  [switch]$ExerciseInteractions
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Accessibility
Add-Type -AssemblyName System.Windows.Forms

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
    public string State { get; set; }
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

    public static bool InvokeNamed(IntPtr window, string targetName)
    {
        IAccessible root = null;
        try
        {
            Guid iid = IidIAccessible;
            int hr = AccessibleObjectFromWindow(window, 0xFFFFFFFC, ref iid, out root);
            return hr == 0 && root != null && InvokeNamed(root, targetName, 1);
        }
        catch { return false; }
        finally
        {
            if (root != null && Marshal.IsComObject(root)) Marshal.FinalReleaseComObject(root);
        }
    }

    public static int[] LocationByName(IntPtr window, string targetName)
    {
        IAccessible root = null;
        try
        {
            Guid iid = IidIAccessible;
            int hr = AccessibleObjectFromWindow(window, 0xFFFFFFFC, ref iid, out root);
            if (hr != 0 || root == null) return null;
            return LocationByName(root, targetName, 1);
        }
        catch { return null; }
        finally
        {
            if (root != null && Marshal.IsComObject(root)) Marshal.FinalReleaseComObject(root);
        }
    }

    private static int[] LocationByName(IAccessible accessible, string targetName, int depth)
    {
        if (accessible == null || depth > 8) return null;
        int count = 0;
        try { count = Math.Min(accessible.accChildCount, 100); } catch { return null; }
        for (int id = 1; id <= count; id++)
        {
            string name = null;
            try { name = accessible.get_accName(id); } catch { }
            if (String.Equals(name, targetName, StringComparison.Ordinal))
            {
                try
                {
                    int left, top, width, height;
                    accessible.accLocation(out left, out top, out width, out height, id);
                    if (width > 0 && height > 0) return new int[] { left, top, width, height };
                }
                catch { }
            }

            object raw = null;
            IAccessible nested = null;
            try { raw = accessible.get_accChild(id); } catch { }
            nested = raw as IAccessible;
            if (nested != null && !Object.ReferenceEquals(nested, accessible))
            {
                try
                {
                    int[] location = LocationByName(nested, targetName, depth + 1);
                    if (location != null) return location;
                }
                finally
                {
                    if (Marshal.IsComObject(nested)) Marshal.FinalReleaseComObject(nested);
                }
            }
            else if (raw != null && Marshal.IsComObject(raw))
            {
                Marshal.FinalReleaseComObject(raw);
            }
        }
        return null;
    }

    private static bool InvokeNamed(IAccessible accessible, string targetName, int depth)
    {
        if (accessible == null || depth > 8) return false;
        int count = 0;
        try { count = Math.Min(accessible.accChildCount, 100); } catch { return false; }
        for (int id = 1; id <= count; id++)
        {
            string name = null;
            try { name = accessible.get_accName(id); } catch { }
            if (String.Equals(name, targetName, StringComparison.Ordinal))
            {
                try { accessible.accDoDefaultAction(id); return true; } catch { }
            }

            object raw = null;
            IAccessible nested = null;
            try { raw = accessible.get_accChild(id); } catch { }
            nested = raw as IAccessible;
            if (nested != null && !Object.ReferenceEquals(nested, accessible))
            {
                try { if (InvokeNamed(nested, targetName, depth + 1)) return true; }
                finally
                {
                    if (Marshal.IsComObject(nested)) Marshal.FinalReleaseComObject(nested);
                }
            }
            else if (raw != null && Marshal.IsComObject(raw))
            {
                Marshal.FinalReleaseComObject(raw);
            }
        }
        return false;
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
                try { node.State = Convert.ToString(Convert.ToInt32(accessible.get_accState(id))); } catch (Exception error) { node.Error = error.Message; }
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
    [DllImport("user32.dll", SetLastError = true)] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll", SetLastError = true)] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, IntPtr extraInfo);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr LoadKeyboardLayout(string layoutId, uint flags);
    [DllImport("user32.dll")] public static extern IntPtr ActivateKeyboardLayout(IntPtr layout, uint flags);
    [DllImport("imm32.dll")] private static extern IntPtr ImmGetContext(IntPtr window);
    [DllImport("imm32.dll")] private static extern bool ImmSetOpenStatus(IntPtr context, bool open);
    [DllImport("imm32.dll")] private static extern int ImmGetCompositionStringW(IntPtr context, uint index, IntPtr buffer, uint length);
    [DllImport("imm32.dll")] private static extern bool ImmReleaseContext(IntPtr window, IntPtr context);

    public static bool SetImeOpen(IntPtr window, bool open)
    {
        IntPtr context = ImmGetContext(window);
        if (context == IntPtr.Zero) return false;
        try { return ImmSetOpenStatus(context, open); }
        finally { ImmReleaseContext(window, context); }
    }

    public static string GetImeComposition(IntPtr window)
    {
        IntPtr context = ImmGetContext(window);
        if (context == IntPtr.Zero) return "";
        try
        {
            int bytes = ImmGetCompositionStringW(context, 0x0008, IntPtr.Zero, 0);
            if (bytes <= 0) return "";
            IntPtr buffer = Marshal.AllocHGlobal(bytes);
            try
            {
                int copied = ImmGetCompositionStringW(context, 0x0008, buffer, (uint)bytes);
                return copied > 0 ? Marshal.PtrToStringUni(buffer, copied / 2) : "";
            }
            finally { Marshal.FreeHGlobal(buffer); }
        }
        finally { ImmReleaseContext(window, context); }
    }
}
'@

$exe = Get-ChildItem -LiteralPath $ArtifactDirectory -Filter 'alula_app.exe' -File -Recurse | Select-Object -First 1
if (!$exe) { throw "alula_app.exe was not found under $ArtifactDirectory" }
if (!(Test-Path (Join-Path $exe.DirectoryName 'alula_core.dll'))) { throw 'Artifact is missing alula_core.dll' }

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$fixtureFile = Join-Path $repoRoot 'tests/fixtures/rust-mini/src/main.rs'
$sampleText = 'fn main() { println!("linux-save-ok"); }'
$fixtureBackup = $null
$interactionResult = [ordered]@{
  requested = [bool]$ExerciseInteractions
  sampleText = $sampleText
  savedAndReadBack = $false
  multiviewSavedAndReadBack = $false
  accessibleEditorCount = 0
  accessibleEditorValuesMatch = $false
  quickOpenQuery = if ($ExerciseInteractions) { 'main.rs' } else { $null }
  launchMode = if ($ExerciseInteractions) { 'standard launch; fixture opened through MSAA-targeted UI clicks' } else { 'standard launch' }
  openedEditorNames = @()
  namesBeforeFolderButton = @()
  openFolderDialogNames = @()
  workspaceTreeNames = @()
  focusBeforePasteNodes = @()
  editorValuesAfterPaste = @()
  accessibilityTargetLocations = [ordered]@{}
  keyboardFocusNames = @()
  keyboardFocusObserved = $false
  imeStatus = 'not-requested'
  imeLanguageChangePosted = $false
  imeComposition = ''
  imeCommittedChinese = $false
  error = $null
}
if ($ExerciseInteractions) {
  $fixtureBackup = [System.IO.File]::ReadAllBytes($fixtureFile)
  if ($fixtureBackup.Length -eq 0) { throw "Rust fixture is empty: $fixtureFile" }
  [System.IO.File]::WriteAllText($fixtureFile, 'fn main() { println!("baseline"); }', [System.Text.UTF8Encoding]::new($false))
}
$process = $null
try {
  $process = if ($ExerciseInteractions) {
    # Launch the artifact the same way a user launches it. The optional
    # --lsp-auto path has correlated with intermittent missing-window results
    # on hosted ARM64 x64 emulation; open the fixture through the UI and keep
    # that startup behavior out of this editor interaction check.
    Start-Process -FilePath $exe.FullName -WorkingDirectory (Join-Path $repoRoot 'app') -PassThru -WindowStyle Normal
  } else {
    Start-Process -FilePath $exe.FullName -WorkingDirectory $exe.DirectoryName -PassThru -WindowStyle Normal
  }
} catch {
  if ($null -ne $fixtureBackup) { [System.IO.File]::WriteAllBytes($fixtureFile, $fixtureBackup) }
  throw
}
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
  $child = [AlulaArtifactWindow]::GetWindow($window, 5)
  if ($child -eq [IntPtr]::Zero) { $child = $window }

  if ($ExerciseInteractions) {
    try {
      function Send-ArtifactKeys([string]$keys, [int]$delayMs = 250) {
        [System.Windows.Forms.SendKeys]::SendWait($keys)
        Start-Sleep -Milliseconds $delayMs
      }
      function Paste-ArtifactText([string]$value) {
        Set-Clipboard -Value $value
        Send-ArtifactKeys '^v'
      }
      function Open-ArtifactFile([string]$query) {
        Send-ArtifactKeys '^p'
        Set-Clipboard -Value $query
        Send-ArtifactKeys '^v'
        Send-ArtifactKeys '{ENTER}' 1200
      }
      function Open-ArtifactWorkspace([string]$path) {
        if (!(Click-ArtifactAccessibleNode '打开文件夹')) {
          $initialSnapshot = [AlulaArtifactMsaa]::Capture($child)
          $interactionResult.namesBeforeFolderButton = @($initialSnapshot.Nodes | ForEach-Object { $_.Name } | Where-Object { $_ })
          throw "Could not click the accessible Open Folder button; names: $($interactionResult.namesBeforeFolderButton -join ' | ')"
        }
        Start-Sleep -Milliseconds 700
        $dialogSnapshot = [AlulaArtifactMsaa]::Capture($child)
        $interactionResult.openFolderDialogNames = @($dialogSnapshot.Nodes | ForEach-Object { $_.Name } | Where-Object { $_ })
        if (@($interactionResult.openFolderDialogNames | Where-Object { $_ -eq '取消' }).Count -eq 0 -or
            @($interactionResult.openFolderDialogNames | Where-Object { $_ -eq '打开' }).Count -eq 0) {
          throw "The accessible Open Folder button did not open the folder dialog; names: $($interactionResult.openFolderDialogNames -join ' | ')"
        }
        Send-ArtifactKeys '^a'
        Paste-ArtifactText $path
        if (!(Click-ArtifactAccessibleNode '打开')) {
          # The dialog autofocuses its path field. Tab moves through Cancel then
          # Open when the button has no accessible default action.
          Send-ArtifactKeys '{TAB}'
          Send-ArtifactKeys '{TAB}'
          Send-ArtifactKeys '{ENTER}' 1400
        } else {
          Start-Sleep -Milliseconds 1400
        }
        $workspaceSnapshot = [AlulaArtifactMsaa]::Capture($child)
        $interactionResult.workspaceTreeNames = @($workspaceSnapshot.Nodes | ForEach-Object { $_.Name } | Where-Object { $_ })
        if (@($interactionResult.workspaceTreeNames | Where-Object { $_ -like '*rust-mini*' -or $_ -eq 'src' -or $_ -eq 'Cargo.toml' }).Count -eq 0) {
          throw "Opening tests/fixtures/rust-mini did not populate the accessible workspace tree; names: $($interactionResult.workspaceTreeNames -join ' | ')"
        }
        if (@($interactionResult.workspaceTreeNames | Where-Object { $_ -eq 'src' }).Count -gt 0) {
          [void](Click-ArtifactAccessibleNode 'src')
          Start-Sleep -Milliseconds 350
          $expandedSnapshot = [AlulaArtifactMsaa]::Capture($child)
          $interactionResult.workspaceTreeNames = @($expandedSnapshot.Nodes | ForEach-Object { $_.Name } | Where-Object { $_ })
        }
      }
      function Open-ArtifactSourceFile() {
        if (@($interactionResult.workspaceTreeNames | Where-Object { $_ -eq 'main.rs' }).Count -gt 0 -and
            (Click-ArtifactAccessibleNode 'main.rs' 2)) {
          Start-Sleep -Milliseconds 1200
          return
        }
        # If the file tree does not expose an invokable Rust item, use the
        # application's Quick Open after explicitly focusing the editor.
        Click-ArtifactEditor 0.67
        Open-ArtifactFile 'main.rs'
        Start-Sleep -Milliseconds 500
      }
      function Run-ArtifactPaletteCommand([string]$query) {
        if (Click-ArtifactAccessibleNode $query) {
          Start-Sleep -Milliseconds 500
          return
        }
        Click-ArtifactEditor 0.67
        Send-ArtifactKeys '^+p'
        Set-Clipboard -Value $query
        Send-ArtifactKeys '^v'
        Send-ArtifactKeys '{ENTER}' 900
      }
      function Click-ArtifactEditor([double]$horizontalFraction) {
        $rect = New-Object AlulaArtifactRect
        if (![AlulaArtifactWindow]::GetClientRect($window, [ref]$rect)) { throw 'GetClientRect failed before editor click' }
        $point = New-Object AlulaArtifactPoint
        $point.X = [int](($rect.Right - $rect.Left) * $horizontalFraction)
        $point.Y = [int](($rect.Bottom - $rect.Top) * 0.30)
        if (![AlulaArtifactWindow]::ClientToScreen($window, [ref]$point)) { throw 'ClientToScreen failed before editor click' }
        [AlulaArtifactWindow]::SetCursorPos($point.X, $point.Y) | Out-Null
        [AlulaArtifactWindow]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)
        [AlulaArtifactWindow]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)
        Start-Sleep -Milliseconds 300
      }
      function Click-ArtifactAccessibleNode([string]$name, [int]$clickCount = 1) {
        $location = [AlulaArtifactMsaa]::LocationByName($child, $name)
        $interactionResult.accessibilityTargetLocations[$name] = if ($location) { @($location) } else { $null }
        if ($location -and $location.Count -ge 4) {
          $x = [int]($location[0] + ($location[2] / 2))
          $y = [int]($location[1] + ($location[3] / 2))
          if (![AlulaArtifactWindow]::SetCursorPos($x, $y)) { return $false }
          for ($click = 0; $click -lt $clickCount; $click++) {
            [AlulaArtifactWindow]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)
            [AlulaArtifactWindow]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)
            Start-Sleep -Milliseconds 80
          }
          Start-Sleep -Milliseconds 300
          return $true
        }
        return [AlulaArtifactMsaa]::InvokeNamed($child, $name)
      }
      function Read-ArtifactFixture() {
        [System.IO.File]::ReadAllText($fixtureFile).Replace("`r`n", "`n")
      }
      function Wait-ForArtifactText([string]$expected) {
        $deadline = (Get-Date).AddSeconds(8)
        do {
          if ((Read-ArtifactFixture) -ceq $expected) { return $true }
          Start-Sleep -Milliseconds 200
        } while ((Get-Date) -lt $deadline)
        return $false
      }

      Open-ArtifactWorkspace (Split-Path -Parent (Split-Path -Parent $fixtureFile))
      Open-ArtifactSourceFile
      Start-Sleep -Milliseconds 500
      $child = [AlulaArtifactWindow]::GetWindow($window, 5)
      $openedSnapshot = [AlulaArtifactMsaa]::Capture($child)
      $interactionResult.openedEditorNames = @($openedSnapshot.Nodes | ForEach-Object { $_.Name } | Where-Object { $_ })
      if (@($interactionResult.openedEditorNames | Where-Object { $_ -like '*main.rs*' }).Count -eq 0) {
        throw "Quick Open did not activate src/main.rs; accessible names: $($interactionResult.openedEditorNames -join ' | ')"
      }
      Click-ArtifactEditor 0.67
      $focusSnapshot = [AlulaArtifactMsaa]::Capture($child)
      $interactionResult.focusBeforePasteNodes = @($focusSnapshot.Nodes | Where-Object {
        $state = 0
        [int]::TryParse($_.State, [ref]$state) -and (($state -band 4) -ne 0)
      } | ForEach-Object { [ordered]@{ path = $_.Path; name = $_.Name; role = $_.Role } })
      Send-ArtifactKeys '^a'
      Paste-ArtifactText $sampleText
      $pastedSnapshot = [AlulaArtifactMsaa]::Capture($child)
      $interactionResult.editorValuesAfterPaste = @($pastedSnapshot.Nodes | Where-Object { $_.Value } | ForEach-Object { $_.Value })
      Send-ArtifactKeys '^s' 700
      if (!(Wait-ForArtifactText $sampleText)) { throw 'The exact Release artifact did not save the linux-save-ok sample to disk' }
      $interactionResult.savedAndReadBack = $true

      $childForIme = [AlulaArtifactWindow]::GetWindow($window, 5)
      $imeLayout = [AlulaArtifactWindow]::LoadKeyboardLayout('00000804', 1)
      if ($imeLayout -ne [IntPtr]::Zero) {
        $interactionResult.imeLanguageChangePosted = [AlulaArtifactWindow]::PostMessage($window, 0x0050, [IntPtr]::Zero, $imeLayout)
        Start-Sleep -Milliseconds 350
        $imeTarget = if ($childForIme -ne [IntPtr]::Zero) { $childForIme } else { $window }
        $imeOpened = [AlulaArtifactWindow]::SetImeOpen($imeTarget, $true)
        if (!$imeOpened -and $imeTarget -ne $window) {
          $imeTarget = $window
          $imeOpened = [AlulaArtifactWindow]::SetImeOpen($imeTarget, $true)
        }
        if ($imeOpened) {
          $interactionResult.imeStatus = 'opened'
          Click-ArtifactEditor 0.67
          Send-ArtifactKeys '^{END}'
          Paste-ArtifactText "`n// "
          Send-ArtifactKeys 'nihao' 600
          $interactionResult.imeComposition = [AlulaArtifactWindow]::GetImeComposition($imeTarget)
          if (![string]::IsNullOrEmpty($interactionResult.imeComposition)) {
            Send-ArtifactKeys '{ENTER}' 350
            Send-ArtifactKeys '^s' 700
            $imeSaved = Read-ArtifactFixture
            $interactionResult.imeCommittedChinese = $imeSaved.Contains('你好')
            $interactionResult.imeStatus = if ($interactionResult.imeCommittedChinese) { 'composition-committed' } else { 'composition-seen-commit-unconfirmed' }
          } else {
            $interactionResult.imeStatus = 'opened-without-composition'
          }
        } else {
          $interactionResult.imeStatus = 'keyboard-layout-loaded-no-imm-context'
        }
      } else {
        $interactionResult.imeStatus = 'simplified-chinese-ime-not-installed'
      }

      # Restore the supplied sample before checking sibling-view synchronization.
      Click-ArtifactEditor 0.67
      Send-ArtifactKeys '^a'
      Paste-ArtifactText $sampleText
      Send-ArtifactKeys '^s' 600
      if (!(Wait-ForArtifactText $sampleText)) { throw 'The saved sample could not be restored after the IME probe' }

      Run-ArtifactPaletteCommand '拆分编辑器'
      if (Click-ArtifactAccessibleNode 'main.rs' 2) {
        Start-Sleep -Milliseconds 900
      } else {
        Click-ArtifactEditor 0.76
        Open-ArtifactFile 'main.rs'
      }
      Click-ArtifactEditor 0.76
      Send-ArtifactKeys '^{END}'
      Paste-ArtifactText "`n// view-2"
      Send-ArtifactKeys '^s' 700
      $expectedMultiviewText = "$sampleText`n// view-2"
      if (!(Wait-ForArtifactText $expectedMultiviewText)) { throw 'The second editor view did not save and read back its edit' }
      $interactionResult.multiviewSavedAndReadBack = $true
      $interactionResult.fileSha256 = (Get-FileHash -LiteralPath $fixtureFile -Algorithm SHA256).Hash.ToLowerInvariant()
      $interactionResult.finalText = Read-ArtifactFixture

    }
    catch {
      $interactionResult.error = $_.Exception.Message
      $validationError = "Release artifact interaction test failed: $($interactionResult.error)"
    }
  }

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

  if ($child -eq [IntPtr]::Zero) { $child = [AlulaArtifactWindow]::GetWindow($window, 5) }
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
  $expectedMsaaText = if ($ExerciseInteractions) {
    @('打开文件夹', 'UTF-8. UTF-8', 'LF. 行尾格式', 'linux-save-ok')
  } else {
    @('打开文件夹', 'UTF-8. UTF-8', 'LF. 行尾格式', '打开一个文件夹开始工作')
  }
  $missingMsaaText = @($expectedMsaaText | Where-Object { !$accessibleText.Contains($_) })
  if ($ExerciseInteractions -and $flutterMsaaRoot) {
    $matchingEditorNodes = @($flutterMsaaRoot.nodes | Where-Object {
      $_.Name -like '*main.rs*' -and $_.Value -like '*linux-save-ok*'
    })
    $interactionResult.accessibleEditorCount = $matchingEditorNodes.Count
    $interactionResult.accessibleEditorValuesMatch = $matchingEditorNodes.Count -ge 2 -and
      @($matchingEditorNodes | Where-Object { $_.Value -like '*view-2*' }).Count -ge 2
    $interactionResult.accessibleEditorNames = @($matchingEditorNodes | ForEach-Object { $_.Name })
    for ($tab = 0; $tab -lt 8; $tab++) {
      [System.Windows.Forms.SendKeys]::SendWait('{TAB}')
      Start-Sleep -Milliseconds 100
      $focusSnapshot = [AlulaArtifactMsaa]::Capture($child)
      $focusedNodes = @($focusSnapshot.Nodes | Where-Object {
        $state = 0
        [int]::TryParse($_.State, [ref]$state) -and (($state -band 4) -ne 0)
      })
      foreach ($focusedNode in $focusedNodes) {
        if (![string]::IsNullOrWhiteSpace($focusedNode.Name)) {
          $interactionResult.keyboardFocusNames += $focusedNode.Name
        }
      }
    }
    $interactionResult.keyboardFocusObserved = $interactionResult.keyboardFocusNames.Count -gt 0
  }

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
    runnerImage = $env:ImageOS
    hostArchitecture = $env:PROCESSOR_ARCHITECTURE
    artifactArchitecture = if ($ExerciseInteractions) { 'x64 on Windows x64 emulation under Windows 11 ARM' } else { 'x64' }
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
    editorInteraction = $interactionResult
    accessibilityMethod = if ($ExerciseInteractions) { 'MSAA semantic tree plus MSAA focused-state keyboard traversal; Narrator speech was not captured' } else { 'UIA and MSAA tree inspection' }
  } | ConvertTo-Json -Depth 8 | Set-Content -Path $metadataPath -Encoding utf8
  $msaaNodeCount = if ($flutterMsaaRoot) { @($flutterMsaaRoot.nodes).Count } else { 0 }
  if (!$screenshotNonUniform) { throw "Client capture appears blank or uniform ($($sampledColors.Count) sampled colors)" }
  if (!$msaaAvailable) { throw "Flutter window MSAA unavailable: $msaaError" }
  if ($missingMsaaText.Count -gt 0) { throw "MSAA tree is missing expected text: $($missingMsaaText -join ', ')" }
  if ($ExerciseInteractions -and !$interactionResult.savedAndReadBack) { throw 'Release artifact did not save the supplied sample text' }
  if ($ExerciseInteractions -and !$interactionResult.multiviewSavedAndReadBack) { throw 'Release artifact did not complete the second-view edit/save roundtrip' }
  if ($ExerciseInteractions -and !$interactionResult.accessibleEditorValuesMatch) { throw 'MSAA did not expose matching text in both editor views' }
  if ($ExerciseInteractions -and !$interactionResult.keyboardFocusObserved) { throw 'The MSAA tree did not expose a focused node during keyboard traversal' }
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
  if ($null -ne $fixtureBackup) {
    try { [System.IO.File]::WriteAllBytes($fixtureFile, $fixtureBackup) }
    catch { if (!$closeError) { $closeError = "Could not restore interaction fixture: $($_.Exception.Message)" } }
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
