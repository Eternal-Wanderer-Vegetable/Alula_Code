#!/usr/bin/env bash
# 构建 Rust 核心并拷贝动态库到 app/native/（Windows Git Bash / Linux / macOS）
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
cargo build -p editor-core --release
mkdir -p app/native
HOST_TRIPLE="$(rustc -vV | sed -n 's/^host: //p')"
case "$HOST_TRIPLE" in
  *-windows-*) CORE_LIBRARY=target/release/alula_core.dll ;;
  *-apple-darwin) CORE_LIBRARY=target/release/libalula_core.dylib ;;
  *-linux-*) CORE_LIBRARY=target/release/libalula_core.so ;;
  *)
    echo "不支持的 Rust host target：$HOST_TRIPLE" >&2
    exit 1
    ;;
esac
if [ ! -f "$CORE_LIBRARY" ]; then
  echo "未找到当前 host 的核心动态库：$CORE_LIBRARY" >&2
  exit 1
fi
cp "$CORE_LIBRARY" app/native/
echo "OK: app/native/ 已就绪"
