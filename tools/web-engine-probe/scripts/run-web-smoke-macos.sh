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

mkdir -p "$output_directory"
output_directory="$(cd "$output_directory" && pwd)"
sandbox_tmp_directory="$HOME/Library/Containers/dev.alula.webEngineProbe/Data/tmp"
mkdir -p "$sandbox_tmp_directory"
export TMPDIR="$sandbox_tmp_directory/"

phase_file="$TMPDIR/p00.4-web-probe-phase.txt"
inspector_release_file="$TMPDIR/p00.4-web-inspector-release.txt"
inspector_script="$(dirname "$0")/attach-safari-web-inspector.applescript"
rm -f "$phase_file" "$inspector_release_file"

sw_vers > "$output_directory/environment.txt"
flutter --version >> "$output_directory/environment.txt"

inspector_attach_verified=0
if ! defaults write com.apple.Safari IncludeDevelopMenu -bool true \
  > "$output_directory/safari-develop-menu.log" 2>&1; then
  echo "could not enable Safari Develop menu" \
    >> "$output_directory/safari-develop-menu.log"
fi
if ! defaults write com.apple.Safari.SandboxBroker ShowDevelopMenu -bool true \
  >> "$output_directory/safari-develop-menu.log" 2>&1; then
  echo "could not enable Safari Develop menu in SandboxBroker preferences" \
    >> "$output_directory/safari-develop-menu.log"
fi
defaults read com.apple.Safari IncludeDevelopMenu \
  >> "$output_directory/safari-develop-menu.log" 2>&1 || true
defaults read com.apple.Safari.SandboxBroker ShowDevelopMenu \
  >> "$output_directory/safari-develop-menu.log" 2>&1 || true
osascript -e 'tell application "Safari" to quit' \
  >> "$output_directory/safari-develop-menu.log" 2>&1 || true
for _ in $(seq 1 20); do
  if ! pgrep -x Safari >/dev/null 2>&1; then break; fi
  sleep 0.25
done
if pgrep -x Safari >/dev/null 2>&1; then
  killall Safari >> "$output_directory/safari-develop-menu.log" 2>&1 || true
fi
if ! open -a Safari >> "$output_directory/safari-develop-menu.log" 2>&1; then
  echo "could not open Safari" >> "$output_directory/safari-develop-menu.log"
fi
if ! osascript "$inspector_script" prepare \
  > "$output_directory/safari-inspector-prepare.log" 2>&1; then
  echo "Safari Inspector window preparation failed" \
    >> "$output_directory/safari-inspector-prepare.log"
fi

save_footprint() {
  local name="$1"
  local footprint_file="$output_directory/$name-footprint.txt"
  if ! footprint -pid "$probe_pid" -targetChildren \
    > "$footprint_file" 2>&1; then
    if ! sudo -n footprint -pid "$probe_pid" -targetChildren \
      > "$footprint_file" 2>&1; then
      cat "$footprint_file" >&2
      return 1
    fi
    echo "capture=privileged-fallback" >> "$footprint_file"
  fi
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
      cat "$output_directory/probe-stderr.log" >&2 || true
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
  cat "$output_directory/probe-stderr.log" >&2 || true
  exit 1
}

wait_for_log() {
  local marker="$1"
  local timeout_seconds="${2:-90}"
  local deadline=$((SECONDS + timeout_seconds))

  while (( SECONDS < deadline )); do
    if ! kill -0 "$probe_pid" 2>/dev/null; then
      echo "probe exited before log marker '$marker'" >&2
      cat "$output_directory/probe.log" >&2 || true
      cat "$output_directory/probe-stderr.log" >&2 || true
      exit 1
    fi
    if grep -Fq "$marker" \
      "$output_directory/probe.log" \
      "$output_directory/probe-stderr.log"; then
      echo "log_marker=$marker"
      return 0
    fi
    sleep 0.25
  done

  echo "timed out waiting for log marker '$marker'" >&2
  cat "$output_directory/probe.log" >&2 || true
  cat "$output_directory/probe-stderr.log" >&2 || true
  exit 1
}

if ! open -n \
  --env P00_4_WEB_AUTO=1 \
  --env P00_4_WEB_INSPECTOR_HOLD=1 \
  --stdout "$output_directory/probe.log" \
  --stderr "$output_directory/probe-stderr.log" \
  "$app_bundle" > "$output_directory/probe-launch.log" 2>&1; then
  echo "could not launch probe app bundle" >&2
  cat "$output_directory/probe-launch.log" >&2 || true
  exit 1
fi

probe_pid=""
for _ in $(seq 1 40); do
  probe_pid="$(ps -axo pid=,command= | awk -v executable="$app_executable" \
    'index($0, executable) > 0 { print $1 }' | tail -n 1)"
  if [[ -n "$probe_pid" ]]; then break; fi
  sleep 0.25
done
if [[ -z "$probe_pid" ]]; then
  echo "probe process was not found after Launch Services startup" >&2
  cat "$output_directory/probe-launch.log" >&2 || true
  exit 1
fi
ps -p "$probe_pid" -o pid=,ppid=,user=,command= \
  > "$output_directory/probe-process.txt"
trap 'kill "$probe_pid" 2>/dev/null || true; wait "$probe_pid" 2>/dev/null || true' EXIT

save_footprint before-webview
wait_for_log P00_4_PROBE_MAIN
wait_for_log P00_4_WEBVIEW_CREATED
save_footprint webview-created

wait_for_phase initial-loaded
save_screenshot webview-open
save_footprint webview-open

wait_for_phase webarchive-loaded
save_screenshot webarchive-reloaded
save_footprint webarchive-reloaded

if osascript "$inspector_script" attach \
  > "$output_directory/safari-inspector-attach.log" 2>&1; then
  inspector_attach_verified=1
  save_screenshot safari-web-inspector-attached
  printf 'attached\n' > "$inspector_release_file"
else
  printf 'attach-failed\n' > "$inspector_release_file"
  echo "Safari Web Inspector attach failed; see safari-inspector-attach.log" \
    >> "$output_directory/warnings.txt"
fi

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
if (( inspector_attach_verified != 1 )); then
  echo "Safari Web Inspector attachment was not verified" >&2
  exit 1
fi
