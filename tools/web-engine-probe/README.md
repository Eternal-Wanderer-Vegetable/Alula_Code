# P00.4 Web Engine Probe

Standalone Flutter app for the second P00.4 risk experiment. It pins
flutter_inappwebview 6.2.0-beta.3 so the same probe can exercise WebView2,
WKWebView, and the Linux WPE implementation. It does not add a dependency to
the Alula workbench. The recorded Windows release build used the previous
6.1.5 plugin and Visual Studio 2026; rerun the Windows release build before
using that capture as evidence for the current probe revision.

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

The Windows build needs NuGet CLI at `tools/web-engine-probe/nuget.exe`. If it
is missing, download the [official NuGet CLI](https://dist.nuget.org/win-x86-commandline/latest/nuget.exe)
to that ignored path before building.

The probe starts with no WebView. F5 creates or destroys the native WebView and loads an
offline page with an embedded data URI resource. F6 calls
Page.captureSnapshot(format=mhtml), writes the returned archive to the system
temporary directory, and reports whether the MIME header and page marker are
present. Linux calls WPE WebKit's `saveWebArchive` API; macOS saves a WKWebView
Web Archive. F7 navigates the same WebView to the saved archive. The buttons do
the same actions. `P00_4_WEB_AUTO=1` runs that sequence automatically for the
platform smoke script; it is off in a normal launch. Windows uses CDP
screenshots, Linux uses the plugin's PNG screenshot API, and macOS records page
verification JSON. The smoke scripts wait for page lifecycle markers before
copying artifacts and sampling the process tree.

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
`docs/diagnostics/2026-10-27-p00/p00.4-web-adr.md`. Do not infer cross-platform
CDP, MHTML, Inspector, or memory behavior from the Windows result.

## macOS WKWebView check

The macOS target uses the plugin's native `WKWebView.createWebArchiveData`
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

## Linux Flutter/WPE check

The Linux Flutter plugin uses WPE WebKit. The probe exercises PNG screenshots
and MHTML archive save/reload. Its published method support table marks
`callDevToolsProtocolMethod` as Windows only, and the Linux implementation has
no native CDP method handler. The generated page JSON records that support flag
as `false`; it does not claim CDP compatibility. The same support table limits
`isInspectable` to iOS, macOS, and Windows; the WPE 2.52.6 Web Inspector Protocol command path was later verified through the multiplexing target, while UI attachment remains unverified on Linux. This does not establish CDP support; see docs/diagnostics/2026-10-27-p00/p00.4-linux-wpe-inspector-protocol-evidence.json.

On Debian sid with Flutter 3.47.8, install the desktop and WPE build
dependencies, then run:

```bash
sudo apt-get install build-essential clang cmake libepoxy-dev libgtk-3-dev \
  libsecret-1-dev libwpe-1.0-dev libwpewebkit-2.0-dev ninja-build pkg-config \
  x11-utils xauth xvfb
flutter config --enable-linux-desktop
cd tools/web-engine-probe
flutter pub get
flutter analyze
flutter test
flutter build linux --release
scripts/run-web-smoke-linux.sh \
  build/linux/x64/release/bundle/web_engine_probe \
  ../../docs/diagnostics/2026-10-27-p00/p00.4-linux-wpe-run
```

The runner records WPE package versions, page verification JSON and PNGs,
MHTML bytes, and `mem-probe` process-tree samples before and after the WebView
lifecycle. It uses Xvfb with software GL, so these memory values are exploratory
and should not be compared with interactive desktop baselines. The
`P00.4 Linux WPE Web Engine Probe` workflow uses a Debian sid container to
produce the same artifacts. A local Debian sid attempt on 2026-10-28 passed
`flutter analyze` and `flutter test`, then stopped during the Release build
because `flutter_inappwebview_linux 0.1.0-beta.1` references the missing
`WPE_SETTING_DISABLE_ANIMATIONS` macro with WPE 2.54.2. The workflow and this
guide include the separately required `libsecret-1-dev` package.

For a lifecycle sample that skips screenshots and archive operations, launch
the Release executable with `P00_4_WEB_AUTO=1` and
`P00_4_WEB_NO_CAPTURE=1`. The probe creates the WebView after startup, waits
until the page is loaded, destroys it, and writes phase markers under
`$TMPDIR/p00.4-web-probe-phase.txt`. This mode reuses the normal WebView
creation/disposal path while avoiding screenshot and MHTML allocations. The
Heaptrack-instrumented exploratory sample and its limits are recorded in
`docs/diagnostics/2026-10-27-p00/p00.4-linux-wpe-parent-heaptrack-evidence.json`.

An official WPE 2.52.6 source build compiled the plugin and passed Xvfb
MHTML save/reload with GBM disabled. The first default-sandbox replay ran as
UID 1000 with `SYS_ADMIN` and seccomp unconfined, left
`WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS` unset, and observed the `bwrap`
sandbox children. Its DOM marker passed, but the initial PNG was fully
transparent. Source inspection showed that the pinned Linux plugin's
`takeScreenshot()` copies its current pixel buffer without waiting for a WPE
frame callback. The isolated probe now checks for the page heading's blue pixel
before its DOM queries and retries up to 30 times at 100 ms intervals. Two
preliminary alpha-check runs rendered on the first attempt; the final version
rendered on its second attempt. All three fresh default-sandbox runs rendered
the initial page and MHTML reload. This stabilizes probe screenshots, but does
not prove a product-level frame guarantee or another host's behavior.
Hardware GBM, normal production/CI sandbox settings, CDP, Inspector, macOS and
production compatibility remain unverified. The Debian Trixie 2.48.3 legacy
FDO fallback also failed to build this plugin at
`webkit_web_view_get_theme_color`. Build flags, warnings, memory snapshots, and
local replay limits are in
`docs/diagnostics/2026-10-27-p00/p00.4-linux-wpe-2.52.6-build.md`,
`p00.4-linux-wpe-2.52.6-run/`, and
`p00.4-linux-wpe-2.52.6-default-sandbox-run/` plus the three
`p00.4-linux-wpe-2.52.6-frame-poll-run*` directories; the 2.54.2 and 2.48.3
failures remain in `p00.4-linux-wpe-evidence.json`,
`p00.4-linux-wpe-build.log`, and `p00.4-linux-wpe-trixie-compat.log`.

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
