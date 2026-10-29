# WPE Remote Inspector protocol-session replay

Recorded 2026-10-28 in the existing Debian 12 WPE 2.52.6 diagnostic container.
This run used the standalone Flutter probe; it did not modify the Alula product.

## Replay

The container already has Flutter 3.47.8, the WPE 2.52.6 source install, and
the probe Release binary. From inside that container:

```bash
export PATH=/work/flutter-sdk/bin:$PATH
export FLUTTER_ROOT=/work/flutter-sdk
export PKG_CONFIG_PATH=/work/install/lib/pkgconfig
export LD_LIBRARY_PATH=/work/install/lib:/work/install/lib/x86_64-linux-gnu
export LDFLAGS=-L/work/install/lib
export TMPDIR=/tmp/inspector-protocol-run/tmp
export DISPLAY=:103
export GDK_BACKEND=x11
export LIBGL_ALWAYS_SOFTWARE=1
export WEBKIT_INSPECTOR_HTTP_SERVER=127.0.0.1:9231
export WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1
export WEBKIT_DMABUF_RENDERER_DISABLE_GBM=1
mkdir -p "$TMPDIR"
Xvfb :103 -screen 0 1440x900x24 -nolisten tcp -noreset &
P00_4_WEB_AUTO=1 /repo/tools/web-engine-probe/build/linux/x64/release/bundle/web_engine_probe &
python3 /repo/docs/diagnostics/2026-10-27-p00/p00.4-linux-wpe-2.52.6-inspector-protocol-run/inspector-protocol-client.py
```

The client waits for the probe's `initial-loaded` phase, reads the WPE
Remote Inspector target list, performs the WebSocket upgrade, receives the
`Target.targetCreated` events, then sends `Runtime.enable` and
`Runtime.evaluate` through `Target.sendMessageToTarget` to the announced page
target. The nested evaluate reads the title and the existing probe marker.

## Result and limits

The WebSocket handshake returned 101. `Runtime.enable` returned an empty
successful result. `Runtime.evaluate` returned
`{"title":"Alula Web Probe","marker":true}`. The main app then completed its
existing MHTML reload and WebView-destroyed phases.

This demonstrates a WPE Web Inspector Protocol command session through the
Remote Inspector multiplexing target. It does not demonstrate Chrome DevTools
Protocol (CDP), Safari Inspector UI attachment, hardware GBM, default sandbox
operation, product integration, or the multi-run memory protocol in docs/04.
Both WebKit sandbox and GBM were explicitly disabled for this diagnostic
container run.

The raw protocol exchange, app log, final lifecycle phase, and Python standard
library client are stored beside this README.
