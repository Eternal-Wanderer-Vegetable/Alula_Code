#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"
OUTPUT_DIR="${1:-$REPO_ROOT/docs/diagnostics/2026-10-27-p00/p00.4-linux-webkitgtk-run}"
DEPENDENCY_DIR="$(mktemp -d /tmp/alula-p00-4-webkitgtk-deps.XXXXXX)"

if [[ "$(uname -m)" != "x86_64" ]]; then
  echo "This exploratory runner currently supports Ubuntu/Debian x86_64 only." >&2
  exit 2
fi
for command in apt-get dpkg-deb python3; do
  command -v "$command" >/dev/null || { echo "Missing required command: $command" >&2; exit 2; }
done

mkdir -p "$OUTPUT_DIR" "$DEPENDENCY_DIR/extracted"
OUTPUT_DIR="$(cd -- "$OUTPUT_DIR" && pwd)"
cd "$DEPENDENCY_DIR"
apt-get download gir1.2-webkit2-4.1 gir1.2-javascriptcoregtk-4.1 gir1.2-soup-3.0 python3-gi-cairo
for package in ./*.deb; do
  dpkg-deb -x "$package" "$DEPENDENCY_DIR/extracted"
done

GI_TYPELIB_PATH="$DEPENDENCY_DIR/extracted/usr/lib/x86_64-linux-gnu/girepository-1.0${GI_TYPELIB_PATH:+:$GI_TYPELIB_PATH}" \
PYTHONPATH="$DEPENDENCY_DIR/extracted/usr/lib/python3/dist-packages${PYTHONPATH:+:$PYTHONPATH}" \
GDK_BACKEND=x11 \
python3 "$SCRIPT_DIR/webkitgtk_probe.py" --output-dir "$OUTPUT_DIR"

printf 'WebKitGTK probe output: %s\n' "$OUTPUT_DIR"
printf 'Extracted GObject typelibs remain at: %s\n' "$DEPENDENCY_DIR/extracted"
