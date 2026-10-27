# Default WebKit sandbox replay context

- Runner: temporary Debian 12 Bookworm container derived from the WPE build environment. Docker used `--cap-add SYS_ADMIN --security-opt seccomp=unconfined`; the probe process ran as unprivileged `probe` (UID/GID 1000), without `--privileged`.
- `unshare --user --map-root-user true` exited 0 in this container. `/usr/bin/bwrap` was mode 0755.
- `WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS` was unset. `WEBKIT_DMABUF_RENDERER_DISABLE_GBM=1` remained set for CPU screenshots; hardware GBM rendering was not tested.
- Replay command: `tools/web-engine-probe/scripts/run-web-smoke-linux.sh tools/web-engine-probe/build/linux/x64/release/bundle/web_engine_probe <output-directory>`.
- Replay exit code: 0. The script observed `initial-loaded`, `mhtml-loaded`, and `webview-destroyed`, then sampled 30 seconds after destroy.
- Memory snapshots contain two `bwrap` children and `WPEWebProcess` while the view was open, confirming that the sandbox launcher ran. `WPEWebProcess` was gone by destroy; `WPENetworkProcess` remained.
- The initial page JSON has the expected DOM marker, but its PNG is background-only. The MHTML reload JSON and PNG show the marker and rendered page. Treat the initial screenshot as a first-frame capture limitation, not a complete rendering pass.
