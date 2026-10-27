# P00.4 Web Engine Probe

Standalone Windows Flutter app for the second P00.4 risk experiment. It pins
flutter_inappwebview 6.1.5 and uses the machine's Evergreen WebView2 runtime.
It does not add a dependency to the Alula workbench. The tested release build
used Visual Studio 2026 and required NuGet CLI plus the WebView2 NuGet package;
the current plugin also needs `_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS`
with this MSVC version.

From Windows Git Bash:

```bash
cd /e/alula_code/tools/web-engine-probe
PUB_HOSTED_URL=https://pub.flutter-io.cn /e/_alula_tools/flutter-win-wrapper.sh pub get
PUB_HOSTED_URL=https://pub.flutter-io.cn /e/_alula_tools/flutter-win-wrapper.sh analyze
PUB_HOSTED_URL=https://pub.flutter-io.cn /e/_alula_tools/flutter-win-wrapper.sh test
PATH=/e/alula_code/tools/web-engine-probe:$PATH \
  PUB_HOSTED_URL=https://pub.flutter-io.cn \
  CL=/D_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS \
  /e/_alula_tools/flutter-win-wrapper.sh build windows --release
/e/_alula_tools/flutter-win-wrapper.sh run -d windows --release
```

The probe starts with no WebView. F5 creates or destroys WebView2 and loads an
offline page with an embedded data URI resource. F6 calls
Page.captureSnapshot(format=mhtml), writes the returned archive to the system
temporary directory, and reports whether the MIME header and page marker are
present. F7 navigates the same WebView to the saved archive. The buttons do the
same actions. `P00_4_WEB_AUTO=1` runs that sequence automatically for the
smoke script; it is off in a normal launch. The probe uses `Page.captureScreenshot`
to save the initial page and MHTML reload directly from WebView2. The smoke
waits for those page lifecycle markers before copying screenshots and sampling
the process tree.

For Windows process-tree Private Bytes, get the probe PID from Task Manager or
PowerShell, then run the repository mem-probe in a second Windows Git Bash:

    cd /e/alula_code
    cargo run --release -p mem-probe -- tree --pid <PID>

Record repeated snapshots before creating the view, while loaded, after destroy
and 30 seconds later, and after process exit. These P00.4 snapshots are
exploratory; product memory acceptance still uses the full scenario and repeat
protocol in docs/04. The run-web-smoke.ps1 script performs the F5/F6/F7 replay,
captures WebView page screenshots and process-tree snapshots, waits 30 seconds
after destroy, then closes the probe.

The recorded Windows replay and its limits are in
`docs/diagnostics/2026-10-27-p00/p00.4-web-adr.md`. macOS and Flutter Linux need
their own native builds. Do not infer cross-platform CDP, MHTML, or memory
behavior from the Windows result.

## macOS WKWebView check

The macOS target uses the stable plugin's native `WKWebView.createWebArchiveData`
API and saves a `.webarchive` file before opening it in the same WebView. It
checks the original page and the reloaded archive with JavaScript, because the
macOS WebKit view does not implement the Windows CDP screenshot path. This
Web Archive is not MHTML and does not establish CDP compatibility.

On a Mac with Flutter 3.47.8 and Xcode installed:

```bash
cd tools/web-engine-probe
flutter pub get
flutter analyze
flutter test
flutter build macos --release
scripts/run-web-smoke-macos.sh \
  build/macos/Build/Products/Release/web_engine_probe.app \
  ../../docs/diagnostics/2026-10-27-p00/p00.4-web-macos-run
```

The runner records `footprint -targetChildren` snapshots before/after the
WebView lifecycle, page verification JSON, the Web Archive bytes, and best-effort
desktop screenshots. It does not automate attaching Safari Web Inspector; that
remains a separate manual check. The same replay is available as the
`P00.4 macOS Web Engine Probe` GitHub Actions workflow. Neither the new target
nor the workflow has run on macOS yet, so they are test infrastructure rather
than Mac evidence.

## Linux WebKitGTK engine-only check

`linux/webkitgtk_probe.py` is a separate GTK probe. It checks the host's native
WebKitGTK engine for page rendering, MHTML save/reload, page snapshots, Web
Inspector, and process lifetime. It does not run inside Flutter and it does not
implement or demonstrate Chrome DevTools Protocol (CDP).

On Ubuntu/Debian x86_64 with WSLg or an X11 display, install the host runtime
once if needed, then run the probe:

```bash
sudo apt-get install python3-gi python3-cairo gir1.2-gtk-3.0 libwebkit2gtk-4.1-0
tools/web-engine-probe/linux/run-webkitgtk-probe.sh \
  docs/diagnostics/2026-10-27-p00/p00.4-linux-webkitgtk-run
```

The runner downloads and extracts the WebKitGTK/JSC/Soup GObject typelibs and
Cairo bridge into a temporary directory without installing those packages.
The output directory receives a JSON process-tree sample for each phase, PNG
screenshots, and the MHTML archive. WebKitGTK is the engine tested here; this
does not validate the separate WPE-based Linux Flutter plugin.
