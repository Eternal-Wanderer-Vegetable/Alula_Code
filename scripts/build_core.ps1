# 构建 Rust 核心并拷贝动态库到 app/native/（Windows）
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    cargo build -p editor-core --release
    if ($LASTEXITCODE -ne 0) { throw "cargo build 失败" }
    New-Item -ItemType Directory -Force -Path app/native | Out-Null
    Copy-Item target/release/alula_core.dll app/native/ -Force
    Write-Host "OK: app/native/alula_core.dll 已就绪"
} finally {
    Pop-Location
}
