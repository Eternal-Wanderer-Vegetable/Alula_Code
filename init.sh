#!/usr/bin/env bash
# init.sh — Alula Code 一键验证（agent 提交前的 DoD 检查）
# 用法: bash init.sh            # 全部：Rust 测试+clippy → 构建核心库 → Flutter 测试
#       bash init.sh --fast     # 跳过 clippy
# Flutter 不在 PATH 时自动探测常见位置，或用 FLUTTER_BIN 环境变量指定。
set -eo pipefail
cd "$(dirname "$0")"

FAIL=0
step() { printf '\n\033[1;36m== %s ==\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m[PASS]\033[0m %s\n' "$*"; }
bad()  { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*"; FAIL=1; }

step "1/4 Rust: cargo test --workspace"
if cargo test --workspace --quiet; then ok "cargo test"; else bad "cargo test"; fi

if [ "${1:-}" != "--fast" ]; then
  step "2/4 Rust: cargo clippy -D warnings"
  if cargo clippy --workspace --all-targets --quiet -- -D warnings; then ok "clippy"; else bad "clippy"; fi
fi

step "3/4 构建核心动态库 → app/native/"
if bash scripts/build_core.sh; then ok "build_core"; else bad "build_core"; fi

step "4/4 Flutter: flutter test (app/)"
REPO_ROOT="$(pwd -W 2>/dev/null || pwd)"
FLUTTER="${FLUTTER_BIN:-}"
if [ -z "$FLUTTER" ]; then
  for c in "$(command -v flutter 2>/dev/null || true)" \
           "$REPO_ROOT/../flutter/bin/flutter" \
           /e/flutter/bin/flutter /c/flutter/bin/flutter "$HOME/flutter/bin/flutter"; do
    if [ -n "$c" ] && [ -e "$c" ]; then FLUTTER="$c"; break; fi
  done
fi
if [ -z "$FLUTTER" ]; then
  bad "未找到 flutter（设 FLUTTER_BIN 或加入 PATH）"
else
  FLUTTER="$(cd "$(dirname "$FLUTTER")" && pwd)/$(basename "$FLUTTER")"  # 转绝对路径：下面要 cd app
  if (cd app && "$FLUTTER" test); then
    ok "flutter test"
  else
    bad "flutter test"
  fi
fi

printf '\n'
if [ "$FAIL" -eq 0 ]; then
  printf '\033[1;32m全部通过 — 满足提交前 DoD。\033[0m\n'
else
  printf '\033[1;31m存在失败项 — 修复后才能提交。\033[0m\n'
  exit 1
fi
