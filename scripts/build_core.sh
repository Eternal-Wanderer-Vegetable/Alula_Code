#!/usr/bin/env bash
# 构建 Rust 核心并拷贝动态库到 app/native/（Linux/macOS）
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
cargo build -p editor-core --release
mkdir -p app/native
SO=target/release/libalula_core.so
DYLIB=target/release/libalula_core.dylib
if [ -f "$SO" ]; then
  cp "$SO" app/native/
elif [ -f "$DYLIB" ]; then
  cp "$DYLIB" app/native/
else
  echo "未找到核心动态库" >&2
  exit 1
fi
echo "OK: app/native/ 已就绪"
