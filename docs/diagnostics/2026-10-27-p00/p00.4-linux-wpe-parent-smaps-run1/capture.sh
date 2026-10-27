#!/bin/sh
set -eu
RUN=/tmp/p00.4-linux-wpe-smaps-run2
APP=/repo/tools/web-engine-probe/build/linux/x64/release/bundle/web_engine_probe
mkdir -p "$RUN/tmp"
rm -f "$RUN/tmp/p00.4-web-probe-phase.txt"
export TMPDIR="$RUN/tmp"
export DISPLAY=:127
export LD_LIBRARY_PATH=/repo/tools/web-engine-probe/build/linux/x64/release/bundle/lib:/work/install/lib
export WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1
export WEBKIT_DMABUF_RENDERER_DISABLE_GBM=1
id >"$RUN/environment.txt"
env | grep -E '^(DISPLAY=|LD_LIBRARY_PATH=|WEBKIT_[A-Z0-9_]+=|P00_[A-Z0-9_]+=|TMPDIR=)' >>"$RUN/environment.txt" || true
Xvfb :127 -screen 0 1280x720x24 -nolisten tcp >"$RUN/xvfb.log" 2>&1 &
XVFB_PID=$!
APP_PID=0
cleanup() {
  kill "$APP_PID" 2>/dev/null || true
  kill "$XVFB_PID" 2>/dev/null || true
}
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
      cp "/proc/$PID/smaps" "$RUN/$STAGE-$PID.smaps"
      cp "/proc/$PID/smaps_rollup" "$RUN/$STAGE-$PID.smaps_rollup"
      cp "/proc/$PID/maps" "$RUN/$STAGE-$PID.maps"
      cat "/proc/$PID/status" >"$RUN/$STAGE-$PID.status"
    fi
  done
}
wait_phase() {
  EXPECTED=$1
  LIMIT=$2
  COUNT=0
  while [ "$COUNT" -lt "$LIMIT" ]; do
    CURRENT=$(cat "$TMPDIR/p00.4-web-probe-phase.txt" 2>/dev/null || true)
    if [ "$CURRENT" = "$EXPECTED" ]; then return 0; fi
    if ! kill -0 "$APP_PID" 2>/dev/null; then echo "app exited waiting for $EXPECTED"; return 1; fi
    sleep 0.25
    COUNT=$((COUNT+1))
  done
  echo "timeout waiting for $EXPECTED current=${CURRENT:-none}"
  return 1
}
sleep 2
save_sample before
wait_phase initial-loaded 240
save_sample webview-open
wait_phase webview-destroyed 240
save_sample webview-destroyed
sleep 30
save_sample webview-destroyed-30s
printf 'app_pid=%s\nxvfb_pid=%s\n' "$APP_PID" "$XVFB_PID" >"$RUN/pids.txt"
