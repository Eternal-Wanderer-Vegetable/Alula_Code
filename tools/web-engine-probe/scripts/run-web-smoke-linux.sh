#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <web_engine_probe> <output-directory>" >&2
  exit 2
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"
probe_executable="$1"
output_directory="$2"

if [[ ! -x "$probe_executable" ]]; then
  echo "probe executable not found: $probe_executable" >&2
  exit 1
fi

mkdir -p "$output_directory/tmp"
output_directory="$(cd -- "$output_directory" && pwd)"
export TMPDIR="$output_directory/tmp"
export GDK_BACKEND=x11
export LIBGL_ALWAYS_SOFTWARE=1

phase_file="$TMPDIR/p00.4-web-probe-phase.txt"
rm -f "$phase_file"

memory_probe="$REPO_ROOT/target/release/mem-probe"
if [[ ! -x "$memory_probe" ]]; then
  (cd "$REPO_ROOT" && cargo build --release -p mem-probe)
fi

display_number="${P00_4_X_DISPLAY:-:99}"
Xvfb "$display_number" -screen 0 1440x900x24 -nolisten tcp -noreset \
  > "$output_directory/xvfb.log" 2>&1 &
xvfb_pid=$!
probe_pid=""

cleanup() {
  if [[ -n "$probe_pid" ]] && kill -0 "$probe_pid" 2>/dev/null; then
    kill "$probe_pid" 2>/dev/null || true
    wait "$probe_pid" 2>/dev/null || true
  fi
  kill "$xvfb_pid" 2>/dev/null || true
  wait "$xvfb_pid" 2>/dev/null || true
}
trap cleanup EXIT

export DISPLAY="$display_number"
for _ in $(seq 1 40); do
  if xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; then
    break
  fi
  sleep 0.25
done
if ! xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; then
  echo "Xvfb did not become ready on $DISPLAY" >&2
  cat "$output_directory/xvfb.log" >&2 || true
  exit 1
fi

{
  uname -a
  cat /etc/os-release
  flutter --version
  printf 'wpe-webkit-2.0='
  pkg-config --modversion wpe-webkit-2.0
  printf 'wpe-platform-2.0='
  pkg-config --modversion wpe-platform-2.0
  printf 'wpe-platform-headless-2.0='
  pkg-config --modversion wpe-platform-headless-2.0
  dpkg-query -W -f='${Package}=${Version}\n' \
    libwpewebkit-2.0-dev libwpe-1.0-dev libgtk-3-dev libepoxy-dev
} > "$output_directory/environment.txt"

P00_4_WEB_AUTO=1 "$probe_executable" \
  > "$output_directory/probe.log" 2>&1 &
probe_pid=$!

save_memory() {
  local name="$1"
  "$memory_probe" tree --pid "$probe_pid" \
    > "$output_directory/$name-memory.json"
}

wait_for_phase() {
  local expected="$1"
  local timeout_seconds="${2:-90}"
  local deadline=$((SECONDS + timeout_seconds))

  while (( SECONDS < deadline )); do
    if ! kill -0 "$probe_pid" 2>/dev/null; then
      echo "probe exited before phase '$expected'" >&2
      cat "$output_directory/probe.log" >&2 || true
      exit 1
    fi
    if [[ -f "$phase_file" ]] && [[ "$(<"$phase_file")" == "$expected" ]]; then
      echo "phase=$expected"
      return 0
    fi
    sleep 0.25
  done

  echo "timed out waiting for phase '$expected'" >&2
  cat "$output_directory/probe.log" >&2 || true
  exit 1
}

sleep 1
save_memory before-webview

wait_for_phase initial-loaded
save_memory webview-open

wait_for_phase mhtml-loaded
save_memory mhtml-reloaded

wait_for_phase webview-destroyed
save_memory webview-destroyed
sleep 30
save_memory webview-destroyed-30s

for artifact in \
  p00.4-web-initial-page.json \
  p00.4-web-initial-render.png \
  p00.4-web-mhtml-page.json \
  p00.4-web-mhtml-render.png \
  p00.4-web-probe.mht; do
  source_path="$TMPDIR/$artifact"
  if [[ ! -f "$source_path" ]]; then
    echo "expected probe artifact is missing: $source_path" >&2
    exit 1
  fi
  cp "$source_path" "$output_directory/"
done

sha256sum "$output_directory/p00.4-web-probe.mht" \
  > "$output_directory/mhtml.sha256"

kill "$probe_pid" 2>/dev/null || true
wait "$probe_pid" 2>/dev/null || true
probe_pid=""
printf 'Probe exited after the 30-second destroy sample.\n' \
  > "$output_directory/probe-exit.txt"

echo "Linux WPE Web Engine replay evidence saved to $output_directory"
