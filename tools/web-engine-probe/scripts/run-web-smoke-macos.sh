#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <web_engine_probe.app> <output-directory>" >&2
  exit 2
fi

app_bundle="$1"
output_directory="$2"
app_executable="$app_bundle/Contents/MacOS/web_engine_probe"

if [[ ! -x "$app_executable" ]]; then
  echo "probe executable not found: $app_executable" >&2
  exit 1
fi

mkdir -p "$output_directory/tmp"
output_directory="$(cd "$output_directory" && pwd)"
export TMPDIR="$output_directory/tmp/"

phase_file="$TMPDIR/p00.4-web-probe-phase.txt"
rm -f "$phase_file"

sw_vers > "$output_directory/environment.txt"
flutter --version >> "$output_directory/environment.txt"

P00_4_WEB_AUTO=1 "$app_executable" > "$output_directory/probe.log" 2>&1 &
probe_pid=$!
trap 'kill "$probe_pid" 2>/dev/null || true; wait "$probe_pid" 2>/dev/null || true' EXIT

save_footprint() {
  local name="$1"
  footprint -pid "$probe_pid" -targetChildren \
    > "$output_directory/$name-footprint.txt" 2>&1
}

save_screenshot() {
  local name="$1"
  if ! screencapture -x "$output_directory/$name.png" \
    2> "$output_directory/$name-screenshot-stderr.txt"; then
    echo "screencapture failed for $name" >> "$output_directory/warnings.txt"
  fi
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
save_footprint before-webview

wait_for_phase initial-loaded
save_screenshot webview-open
save_footprint webview-open

wait_for_phase webarchive-loaded
save_screenshot webarchive-reloaded
save_footprint webarchive-reloaded

wait_for_phase webview-destroyed
save_footprint webview-destroyed
sleep 30
save_footprint webview-destroyed-30s

for artifact in \
  p00.4-web-initial-page.json \
  p00.4-web-webarchive-page.json \
  p00.4-web-probe.webarchive; do
  source_path="$TMPDIR$artifact"
  if [[ ! -f "$source_path" ]]; then
    echo "expected probe artifact is missing: $source_path" >&2
    exit 1
  fi
  cp "$source_path" "$output_directory/"
done

shasum -a 256 "$output_directory/p00.4-web-probe.webarchive" \
  > "$output_directory/webarchive.sha256"

kill "$probe_pid" 2>/dev/null || true
wait "$probe_pid" 2>/dev/null || true
trap - EXIT

echo "macOS Web Archive replay evidence saved to $output_directory"
