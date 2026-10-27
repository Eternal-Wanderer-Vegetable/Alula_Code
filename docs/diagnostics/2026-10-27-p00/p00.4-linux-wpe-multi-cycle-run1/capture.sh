#!/bin/sh
set -eu
RUN=/tmp/p00.4-linux-wpe-multi-cycle-run4
APP=/repo/tools/web-engine-probe/build/linux/x64/release/bundle/web_engine_probe
mkdir -p "$RUN/tmp"
rm -f "$RUN/tmp/p00.4-web-probe-phase.txt"
export TMPDIR="$RUN/tmp"
export DISPLAY=:131
export LD_LIBRARY_PATH=/repo/tools/web-engine-probe/build/linux/x64/release/bundle/lib:/work/install/lib
export WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1
export WEBKIT_DMABUF_RENDERER_DISABLE_GBM=1
id >"$RUN/environment.txt"
printf 'DISPLAY=%s\nLD_LIBRARY_PATH=%s\nWEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1\nWEBKIT_DMABUF_RENDERER_DISABLE_GBM=1\nP00_4_WEB_AUTO=1\nP00_4_WEB_NO_CAPTURE=1\nTMPDIR=%s\n' "$DISPLAY" "$LD_LIBRARY_PATH" "$TMPDIR" >>"$RUN/environment.txt"
Xvfb :131 -screen 0 1280x720x24 -nolisten tcp >"$RUN/xvfb.log" 2>&1 &
XVFB_PID=$!
APP_PID=0
cleanup() { kill "$APP_PID" 2>/dev/null || true; kill "$XVFB_PID" 2>/dev/null || true; }
trap cleanup EXIT INT TERM
sleep 1
kill -0 "$XVFB_PID"
P00_4_WEB_AUTO=1 P00_4_WEB_NO_CAPTURE=1 "$APP" >"$RUN/probe.log" 2>&1 &
APP_PID=$!
save_sample() {
  STAGE=$1
  echo "$STAGE" >>"$RUN/stages.txt"
  ps -eo pid,ppid,rss,vsz,comm,args >"$RUN/$STAGE-ps.txt"
  for PID in "$APP_PID" $(pgrep -P "$APP_PID" || true); do
    if [ -r "/proc/$PID/smaps" ]; then
      cp "/proc/$PID/smaps_rollup" "$RUN/$STAGE-$PID.smaps_rollup"
      cp "/proc/$PID/maps" "$RUN/$STAGE-$PID.maps"
      if [ "$PID" = "$APP_PID" ]; then cp "/proc/$PID/smaps" "$RUN/$STAGE-$PID.smaps"; fi
    fi
  done
}
wait_phase() {
  EXPECTED=$1; LIMIT=$2; COUNT=0
  while [ "$COUNT" -lt "$LIMIT" ]; do
    CURRENT=$(cat "$TMPDIR/p00.4-web-probe-phase.txt" 2>/dev/null || true)
    if [ "$CURRENT" = "$EXPECTED" ]; then return 0; fi
    if ! kill -0 "$APP_PID" 2>/dev/null; then echo "app exited waiting for $EXPECTED"; return 1; fi
    sleep 0.25; COUNT=$((COUNT+1))
  done
  echo "timeout waiting for $EXPECTED current=${CURRENT:-none}"
  return 1
}
press_f5() {
  WINDOW=$(xdotool search --onlyvisible --name '^web_engine_probe$' 2>/dev/null | head -n 1 || true)
  if [ -z "$WINDOW" ]; then echo 'probe X11 window not found'; return 1; fi
  xdotool windowfocus --sync "$WINDOW"
  xdotool key --clearmodifiers F5
}
sleep 2
save_sample before
wait_phase webview-destroyed 480
sleep 30
save_sample cycle1-destroyed-30s
for CYCLE in 2 3 4 5 6 7 8 9 10; do
  save_sample "cycle${CYCLE}-before-open"
  press_f5
  wait_phase initial-loaded 240
  save_sample "cycle${CYCLE}-open"
  sleep 4
  press_f5
  wait_phase webview-destroyed 240
  save_sample "cycle${CYCLE}-destroyed"
  sleep 30
  save_sample "cycle${CYCLE}-destroyed-30s"
done
printf 'app_pid=%s\nxvfb_pid=%s\n' "$APP_PID" "$XVFB_PID" >"$RUN/pids.txt"
