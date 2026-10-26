#!/usr/bin/env python3
"""Alula Code 基准编排器（docs/04 §3）。

封装 mem-probe 的结果归档约定与场景对比：

  # 采集一个场景（结果自动归档到 docs/baselines/<日期>/<label>.json|.md）
  python tools/bench/bench.py run <label> --exe <路径> [--arg 参数]... [--duration 45] [--interval 1] [--root-name N]

  # 对比两组基线（Markdown 表格输出到 stdout）
  python tools/bench/bench.py compare <a.json> <b.json> ...
"""

import argparse
import json
import subprocess
import sys
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROBE = ROOT / "target" / "release" / ("mem-probe.exe" if sys.platform == "win32" else "mem-probe")
RESULTS = ROOT / "docs" / "baselines"

MIB = 1048576.0


def cmd_run(args: argparse.Namespace) -> int:
    if not PROBE.exists():
        print(f"未找到 {PROBE}，请先 cargo build -p mem-probe --release", file=sys.stderr)
        return 1
    out_dir = RESULTS / date.today().isoformat()
    out_dir.mkdir(parents=True, exist_ok=True)
    json_out = out_dir / f"{args.label}.json"
    md_out = out_dir / f"{args.label}.md"
    cmd = [
        str(PROBE), "watch",
        "--exe", args.exe,
        "--duration", str(args.duration),
        "--interval", str(args.interval),
        "--label", args.label,
        "--out", str(json_out),
        "--md", str(md_out),
    ]
    for a in args.arg:
        cmd += ["--arg", a]
    if args.root_name:
        cmd += ["--root-name", args.root_name]
    return subprocess.run(cmd).returncode


def load(path: str) -> dict:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def cmd_compare(args: argparse.Namespace) -> int:
    reports = [load(p) for p in args.files]
    print("| 场景 | 进程数 | 峰值 MiB | 稳态 MiB | 结束 MiB |")
    print("|---|---|---|---|---|")
    for r in reports:
        s = r["summary"]
        n = len(r.get("final_processes", []))
        print(
            f"| {r['label']} | {n} | {s['peak_private'] / MIB:.1f} "
            f"| {s['stable_private'] / MIB:.1f} | {s['final_private'] / MIB:.1f} |"
        )
    if len(reports) >= 2:
        base, other = reports[-1], reports[0]
        bs, os_ = base["summary"], other["summary"]
        if bs["stable_private"] > 0:
            delta = (1 - os_["stable_private"] / bs["stable_private"]) * 100
            print(f"\n稳定态对比：{other['label']} 相对 {base['label']} 降低 {delta:.1f}%")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Alula Code 基准编排器")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_run = sub.add_parser("run", help="采集一个场景")
    p_run.add_argument("label")
    p_run.add_argument("--exe", required=True)
    p_run.add_argument("--arg", action="append", default=[])
    p_run.add_argument("--duration", type=float, default=45)
    p_run.add_argument("--interval", type=float, default=1)
    p_run.add_argument("--root-name", default=None)

    p_cmp = sub.add_parser("compare", help="对比多组基线 JSON")
    p_cmp.add_argument("files", nargs="+")

    args = parser.parse_args()
    return {"run": cmd_run, "compare": cmd_compare}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
