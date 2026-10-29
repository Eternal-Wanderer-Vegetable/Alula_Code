#!/usr/bin/env python3
"""Repeat the WSLg/Xvfb Rust+rust-analyzer 10-minute idle probe under cgroup v2."""

from __future__ import annotations

import argparse
import json
import os
import platform
import re
import shutil
import statistics
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any


REPO = Path(__file__).resolve().parents[3]
REPORT_DIR = REPO / "docs/diagnostics/2026-10-29-p00"
APP_BIN = REPO / "app/build/linux/x64/release/bundle/alula_app"
FIXTURE = REPO / "tests/fixtures/rust-mini"
CGROUP_ROOT = Path("/sys/fs/cgroup")
MIB = 1024 * 1024
REPORT_SCHEMA = "alula-p00.4-wsl-rust-ra-idle-repeat-v1"


def read_text(path: Path) -> str:
    try:
        return path.read_text(errors="replace")
    except (FileNotFoundError, PermissionError, ProcessLookupError):
        return ""


def read_int(path: Path) -> int | None:
    value = read_text(path).strip()
    try:
        return int(value)
    except ValueError:
        return None


def read_key_values(path: Path) -> dict[str, int]:
    result: dict[str, int] = {}
    for line in read_text(path).splitlines():
        parts = line.split()
        if len(parts) == 2:
            try:
                result[parts[0]] = int(parts[1])
            except ValueError:
                pass
    return result


def proc_identity(pid: int) -> dict[str, Any] | None:
    base = Path("/proc") / str(pid)
    try:
        comm = read_text(base / "comm").strip()
        status = read_text(base / "status")
        ppid = None
        for line in status.splitlines():
            if line.startswith("PPid:"):
                ppid = int(line.split()[1])
                break
        raw_stat = read_text(base / "stat")
        close = raw_stat.rfind(")")
        rest = raw_stat[close + 2 :].split() if close >= 0 else []
        cpu_ticks = int(rest[11]) + int(rest[12]) if len(rest) > 12 else None
        cmdline = read_text(base / "cmdline").replace("\x00", " ").strip()
        pss_bytes = None
        for line in read_text(base / "smaps_rollup").splitlines():
            if line.startswith("Pss:"):
                pss_bytes = int(line.split()[1]) * 1024
                break
        return {
            "pid": pid,
            "ppid": ppid,
            "comm": comm,
            "cmdline": cmdline,
            "pss_bytes": pss_bytes,
            "cpu_ticks": cpu_ticks,
        }
    except (FileNotFoundError, PermissionError, ProcessLookupError, ValueError):
        return None


def cgroup_pids(cgroup: Path) -> list[int]:
    try:
        return [int(item) for item in (cgroup / "cgroup.procs").read_text().split()]
    except (FileNotFoundError, PermissionError, ValueError):
        return []


def snapshot(cgroup: Path, t_s: float) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    processes = [item for pid in cgroup_pids(cgroup) if (item := proc_identity(pid))]
    mem_events = read_key_values(cgroup / "memory.events")
    cpu_stat = read_key_values(cgroup / "cpu.stat")
    memory_current = read_int(cgroup / "memory.current")
    pss_items = [proc["pss_bytes"] for proc in processes if proc["pss_bytes"] is not None]
    row = {
        "t_s": round(t_s, 3),
        "memory_current_bytes": memory_current,
        "pss_tree_bytes": sum(pss_items),
        "pss_processes": len(pss_items),
        "pids": len(processes),
        "cpu_usage_usec": cpu_stat.get("usage_usec"),
        "oom": mem_events.get("oom", 0),
        "oom_kill": mem_events.get("oom_kill", 0),
    }
    return row, processes


def event_file(path: Path, name: str, values: dict[str, Any] | None = None) -> None:
    try:
        data = json.loads(path.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        data = {"events": {}}
    data.setdefault("events", {})[name] = {
        "monotonic_s": time.monotonic(),
        "wall_time": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        **(values or {}),
    }
    temp = path.with_suffix(".tmp")
    temp.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
    temp.replace(path)


def run_command(args: list[str], timeout: float = 10) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, capture_output=True, text=True, timeout=timeout, check=False)


def find_app_windows(pid: int) -> list[str]:
    result = run_command(["xdotool", "search", "--onlyvisible", "--pid", str(pid)])
    return [line.strip() for line in result.stdout.splitlines() if line.strip().isdigit()]


def rust_processes() -> list[dict[str, Any]]:
    result = []
    try:
        pids = [int(name) for name in os.listdir("/proc") if name.isdigit()]
    except OSError:
        return result
    for pid in pids:
        proc = proc_identity(pid)
        if proc and ("rust-analyzer" in proc["comm"] or "rust-analyzer" in proc["cmdline"]):
            result.append(proc)
    return result


def inner_main(root: Path, app_bin: Path, idle_seconds: int, warmup_seconds: int) -> int:
    events_path = root / "events.json"
    app_log = root / "app.log"
    env = os.environ.copy()
    cwd = root / "app"
    env.update(
        {
            "HOME": str(root / "home"),
            "XDG_CONFIG_HOME": str(root / "home/.config"),
            "XDG_DATA_HOME": str(root / "home/.local/share"),
            "XDG_CACHE_HOME": str(root / "home/.cache"),
            "CARGO_HOME": "/home/vegetable/.cargo",
            "RUSTUP_HOME": "/home/vegetable/.rustup",
            "PATH": "/home/vegetable/.cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
            "GDK_BACKEND": "x11",
            "LIBGL_ALWAYS_SOFTWARE": "1",
            "GALLIUM_DRIVER": "llvmpipe",
        }
    )
    with app_log.open("w") as log:
        app = subprocess.Popen([str(app_bin), "--lsp-auto"], cwd=cwd, env=env, stdout=log, stderr=subprocess.STDOUT)
        window_id = None
        ra_seen = False
        deadline = time.monotonic() + 180
        while time.monotonic() < deadline:
            if app.poll() is not None:
                event_file(events_path, "startup_failed", {"app_exit_code": app.returncode})
                return 2
            windows = find_app_windows(app.pid)
            if windows:
                window_id = windows[-1]
            if rust_processes():
                ra_seen = True
            if window_id and ra_seen:
                break
            time.sleep(0.5)

        if not window_id or not ra_seen:
            event_file(events_path, "startup_failed", {"window_id": window_id, "rust_analyzer_seen": ra_seen})
            app.terminate()
            try:
                app.wait(timeout=10)
            except subprocess.TimeoutExpired:
                app.kill()
                app.wait(timeout=10)
            return 3

        event_file(events_path, "app_ready", {"app_pid": app.pid, "window_id": window_id, "rust_analyzer_seen": True})
        run_command(["xdotool", "windowfocus", "--sync", window_id])
        quick_open_key = run_command(["xdotool", "key", "--clearmodifiers", "ctrl+p"])
        time.sleep(0.35)
        quick_open_type = run_command(["xdotool", "type", "--clearmodifiers", "--delay", "50", "src/main.rs"])
        time.sleep(0.75)
        quick_open_enter = run_command(["xdotool", "key", "--clearmodifiers", "Return"])
        time.sleep(2)
        event_file(events_path, "main_rs_open_attempted", {
            "path": "src/main.rs",
            "window_id": window_id,
            "quick_open_key_returncode": quick_open_key.returncode,
            "quick_open_type_returncode": quick_open_type.returncode,
            "quick_open_enter_returncode": quick_open_enter.returncode,
        })

        time.sleep(warmup_seconds)
        still_running = app.poll() is None
        current_ra = rust_processes()
        if not still_running or not current_ra:
            event_file(events_path, "idle_not_started", {"app_alive": still_running, "rust_analyzer_processes": current_ra})
            if still_running:
                app.terminate()
                app.wait(timeout=10)
            return 4

        event_file(events_path, "idle_start", {"rust_analyzer_processes": current_ra})
        time.sleep(idle_seconds)
        event_file(events_path, "idle_end", {"rust_analyzer_processes": rust_processes()})

        # Alula sets preventClose=true and performs LSP shutdown from its custom
        # title-bar close button. Xvfb has no window manager to deliver that
        # callback for WM_DELETE_WINDOW, so click the same UI control directly.
        geometry = run_command(["xdotool", "getwindowgeometry", "--shell", window_id])
        dimensions = {}
        for line in geometry.stdout.splitlines():
            key, separator, value = line.partition("=")
            if separator:
                try:
                    dimensions[key] = int(value)
                except ValueError:
                    pass
        width = dimensions.get("WIDTH")
        if not width:
            close_method = "custom-titlebar-geometry-failed"
        else:
            close_method = "xdotool-custom-close-button"
            move_result = run_command(["xdotool", "mousemove", "--sync", "--window", window_id, str(width - 20), "18"])
            time.sleep(0.7)
            click_result = run_command(["xdotool", "click", "--clearmodifiers", "--repeat", "2", "--delay", "250", "1"])
            mouse = run_command(["xdotool", "getmouselocation", "--shell"])
            event_file(events_path, "close_click_sent", {
                "window_geometry": geometry.stdout.strip(),
                "move_returncode": move_result.returncode,
                "move_stderr": move_result.stderr.strip(),
                "click_returncode": click_result.returncode,
                "click_stderr": click_result.stderr.strip(),
                "mouse_location": mouse.stdout.strip(),
            })

        try:
            app.wait(timeout=10)
        except subprocess.TimeoutExpired:
            try:
                run_command(["xdotool", "key", "--clearmodifiers", "alt+F4"])
                close_method += "+alt-f4"
                app.wait(timeout=10)
            except subprocess.TimeoutExpired:
                close_method = "forced-terminate"
                app.terminate()
                try:
                    app.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    close_method = "forced-kill"
                    app.kill()
                    app.wait(timeout=10)

        event_file(events_path, "app_closed", {"close_method": close_method, "app_exit_code": app.returncode})
        time.sleep(30)
        leftovers = rust_processes()
        event_file(events_path, "close_plus_30s", {"rust_services_left": leftovers})
        print(json.dumps({"app_exit_code": app.returncode, "close_method": close_method, "rust_left": len(leftovers)}), flush=True)
        return 0 if app.returncode == 0 and close_method.startswith("xdotool-custom-close-button") and not leftovers else 5


def nearest(rows: list[dict[str, Any]], t: float) -> dict[str, Any] | None:
    if not rows:
        return None
    return min(rows, key=lambda row: abs(row["t_s"] - t))


def process_medians(rows: list[dict[str, Any]], start: float, end: float) -> dict[str, int]:
    grouped: dict[str, list[int]] = {}
    for row in rows:
        if start <= row["t_s"] <= end:
            for proc in row["processes"]:
                if proc["pss_bytes"] is not None:
                    grouped.setdefault(proc["comm"], []).append(proc["pss_bytes"])
    return {name: int(statistics.median(values)) for name, values in grouped.items() if values}


def process_cpu_delta(rows: list[dict[str, Any]], start: float, end: float, ticks_per_second: int) -> list[dict[str, Any]]:
    # Use samples at or before both boundaries so an app that exits just after
    # idle_end remains available for attribution instead of disappearing from
    # the nearest (post-close) breakdown sample.
    before_rows = [row for row in rows if row["t_s"] <= start]
    after_rows = [row for row in rows if row["t_s"] <= end]
    before = max(before_rows, key=lambda row: row["t_s"]) if before_rows else nearest(rows, start)
    after = max(after_rows, key=lambda row: row["t_s"]) if after_rows else nearest(rows, end)
    if not before or not after:
        return []
    start_by_pid = {p["pid"]: p for p in before["processes"] if p["cpu_ticks"] is not None}
    result = []
    for proc in after["processes"]:
        old = start_by_pid.get(proc["pid"])
        if old and proc["cpu_ticks"] is not None:
            result.append(
                {
                    "pid": proc["pid"],
                    "comm": proc["comm"],
                    "cpu_seconds": round((proc["cpu_ticks"] - old["cpu_ticks"]) / ticks_per_second, 3),
                    "pss_start_bytes": old["pss_bytes"],
                    "pss_end_bytes": proc["pss_bytes"],
                }
            )
    return result


def main() -> int:
    if len(sys.argv) > 1 and sys.argv[1] == "--inner":
        root = Path(sys.argv[2])
        app = Path(sys.argv[3])
        idle_seconds = int(sys.argv[4])
        warmup_seconds = int(sys.argv[5])
        return inner_main(root, app, idle_seconds, warmup_seconds)

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--idle-seconds", type=int, default=600)
    parser.add_argument("--warmup-seconds", type=int, default=60)
    parser.add_argument("--limit-mib", type=int, default=1024)
    parser.add_argument("--output-dir", type=Path, default=REPORT_DIR)
    args = parser.parse_args()

    if not APP_BIN.is_file() or not FIXTURE.is_dir():
        raise SystemExit(f"missing release binary or rust-mini fixture: {APP_BIN}")
    if args.idle_seconds < 1 or args.warmup_seconds < 0 or args.limit_mib < 1:
        raise SystemExit("idle, warmup, and memory-limit values must be positive")
    args.output_dir.mkdir(parents=True, exist_ok=True)
    out_json = args.output_dir / f"p00.4-wsl-rust-ra-10m-idle-repeat-{args.run_id}.json"
    out_md = args.output_dir / f"p00.4-wsl-rust-ra-10m-idle-repeat-{args.run_id}.md"
    if out_json.exists() or out_md.exists():
        raise SystemExit(f"refusing to overwrite report for run id {args.run_id}")

    root = Path(tempfile.mkdtemp(prefix=f"alula-p00-wsl-ra-idle-{args.run_id}-"))
    (root / "app").mkdir()
    (root / "home").mkdir()
    (root / "tests/fixtures").mkdir(parents=True)
    shutil.copytree(FIXTURE, root / "tests/fixtures/rust-mini")
    events_path = root / "events.json"
    events_path.write_text(json.dumps({"events": {}}, indent=2) + "\n")

    unit = f"alula-p00-ra-idle-{re.sub(r'[^a-zA-Z0-9_-]', '-', args.run_id)[:24]}-{os.getpid()}"
    limit_bytes = args.limit_mib * MIB
    env_args = [
        f"--setenv=HOME={root / 'home'}",
        f"--setenv=XDG_CONFIG_HOME={root / 'home/.config'}",
        f"--setenv=XDG_DATA_HOME={root / 'home/.local/share'}",
        f"--setenv=XDG_CACHE_HOME={root / 'home/.cache'}",
        "--setenv=CARGO_HOME=/home/vegetable/.cargo",
        "--setenv=RUSTUP_HOME=/home/vegetable/.rustup",
        "--setenv=PATH=/home/vegetable/.cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
        "--setenv=GDK_BACKEND=x11",
        "--setenv=LIBGL_ALWAYS_SOFTWARE=1",
        "--setenv=GALLIUM_DRIVER=llvmpipe",
    ]
    command = [
        "systemd-run",
        "--user",
        "--scope",
        "--collect",
        f"--unit={unit}",
        f"--property=MemoryMax={limit_bytes}",
        "--property=MemorySwapMax=0",
        *env_args,
        "--",
        "/usr/bin/xvfb-run",
        "-a",
        "-s",
        "-screen 0 1280x800x24",
        "/usr/bin/python3",
        str(Path(__file__).resolve()),
        "--inner",
        str(root),
        str(APP_BIN),
        str(args.idle_seconds),
        str(args.warmup_seconds),
    ]
    outer_start = time.monotonic()
    proc = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
    output_lines: list[str] = []
    try:
        line = proc.stdout.readline() if proc.stdout else ""
        output_lines.append(line)
        if "Running as unit:" not in line:
            raise RuntimeError(f"systemd-run did not report a unit: {line.strip()}")

        unit_scope = unit if unit.endswith(".scope") else f"{unit}.scope"
        control_group = ""
        for _ in range(30):
            show = run_command(["systemctl", "--user", "show", "--property=ControlGroup", "--value", unit_scope])
            control_group = show.stdout.strip()
            if control_group:
                break
            time.sleep(0.2)
        if not control_group.startswith("/"):
            raise RuntimeError(f"unable to resolve cgroup for {unit_scope}: {control_group!r}")
        cgroup = CGROUP_ROOT / control_group.lstrip("/")

        series: list[dict[str, Any]] = []
        breakdown: list[dict[str, Any]] = []
        next_sample = time.monotonic()
        last_breakdown = -10.0
        timeout_at = outer_start + args.warmup_seconds + args.idle_seconds + 240 + 300
        while True:
            now = time.monotonic()
            if now > timeout_at:
                raise TimeoutError("idle scope exceeded the bounded total run time")
            t_s = now - outer_start
            row, processes = snapshot(cgroup, t_s)
            series.append(row)
            if t_s - last_breakdown >= 10:
                breakdown.append({"t_s": round(t_s, 3), "processes": processes})
                last_breakdown = t_s
            if proc.poll() is not None:
                tail = proc.stdout.read() if proc.stdout else ""
                if tail:
                    output_lines.append(tail)
                break
            next_sample += 1.0
            time.sleep(max(0, next_sample - time.monotonic()))

        events_data = json.loads(events_path.read_text())
        events = events_data.get("events", {})
        idle_start_abs = events.get("idle_start", {}).get("monotonic_s")
        idle_end_abs = events.get("idle_end", {}).get("monotonic_s")
        idle_start_t = idle_start_abs - outer_start if idle_start_abs else None
        idle_end_t = idle_end_abs - outer_start if idle_end_abs else None
        start_row = nearest(series, idle_start_t) if idle_start_t is not None else None
        end_row = nearest(series, idle_end_t) if idle_end_t is not None else None
        cpu_delta = None
        cpu_percent = None
        if start_row and end_row and start_row["cpu_usage_usec"] is not None and end_row["cpu_usage_usec"] is not None:
            cpu_delta = end_row["cpu_usage_usec"] - start_row["cpu_usage_usec"]
            duration = idle_end_abs - idle_start_abs
            if duration > 0:
                cpu_percent = cpu_delta / (duration * 10_000)
        ticks = os.sysconf(os.sysconf_names["SC_CLK_TCK"])
        idle_process_cpu = process_cpu_delta(breakdown, idle_start_t or 0, idle_end_t or 0, ticks)
        first_minute = process_medians(breakdown, (idle_start_t or 0), (idle_start_t or 0) + 60)
        last_minute = process_medians(breakdown, (idle_end_t or 0) - 60, (idle_end_t or 0))
        pss_series = [row["pss_tree_bytes"] for row in series if row["pss_tree_bytes"] is not None]
        memory_series = [row["memory_current_bytes"] for row in series if row["memory_current_bytes"] is not None]
        peak_pss = max(pss_series) if pss_series else None
        peak_memory = max(memory_series) if memory_series else None
        final_events = read_key_values(cgroup / "memory.events") if cgroup.exists() else {}
        if not final_events and series:
            final_events = {
                "oom": series[-1]["oom"],
                "oom_kill": series[-1]["oom_kill"],
                "source": "last in-scope cgroup sample",
            }
        report: dict[str, Any] = {
            "schema": REPORT_SCHEMA,
            "run_id": args.run_id,
            "date": time.strftime("%Y-%m-%d"),
            "platform": "WSLg + Xvfb software GL; not a native DRM/X11/Wayland host",
            "runner": "Flutter Linux Release main app + WSL stable rust-analyzer",
            "runner_executable": str(APP_BIN),
            "fixture": "isolated copy of tests/fixtures/rust-mini",
            "language_server": run_command(["rust-analyzer", "--version"]).stdout.strip(),
            "limit_mib": args.limit_mib,
            "memory_max_bytes": limit_bytes,
            "swap_max_bytes": 0,
            "scope": control_group,
            "scope_unit": unit_scope,
            "scope_result": proc.returncode,
            "process_exit_code": events.get("app_closed", {}).get("app_exit_code"),
            "inner": events,
            "sampling_interval_s": 1,
            "breakdown_interval_s": 10,
            "sample_count": len(series),
            "duration_s": round(series[-1]["t_s"], 3) if series else 0,
            "peak_memory_current_bytes": peak_memory,
            "peak_scope_pss_bytes": peak_pss,
            "idle_start_sample": start_row,
            "idle_end_sample": end_row,
            "idle_duration_s": round(idle_end_abs - idle_start_abs, 3) if idle_start_abs and idle_end_abs else None,
            "idle_cpu_usage_delta_usec": cpu_delta,
            "idle_cpu_percent_of_one_core": round(cpu_percent, 4) if cpu_percent is not None else None,
            "idle_process_cpu_deltas": idle_process_cpu,
            "first_idle_minute_process_pss_median_bytes": first_minute,
            "last_idle_minute_process_pss_median_bytes": last_minute,
            "oom_events_final": final_events,
            "series": series,
            "process_breakdown_samples": breakdown,
            "output_tail": "".join(output_lines)[-8000:],
            "temporary_root": str(root),
            "temporary_data_removed": False,
        }
        out_json.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
        mib = lambda value: round(value / MIB, 2) if value is not None else None
        close_event = events.get("close_plus_30s", {})
        lines = [
            f"# P00.4 WSL Rust+RA 10-minute idle repeat {args.run_id}",
            "",
            "## Method",
            "",
            f"- WSLg/Xvfb software GL; Flutter Linux Release main app; actual WSL rust-analyzer; isolated HOME and copied `rust-mini` fixture.",
            f"- cgroup v2 scope contains `xvfb-run`, Xvfb, controller, app, and services; memory.max={args.limit_mib} MiB; memory.swap.max=0.",
            f"- Launch with `--lsp-auto`, send Ctrl+P and `src/main.rs`, then wait {args.warmup_seconds}s and idle without input for {args.idle_seconds}s.",
            f"- Sample cgroup memory.current and all in-scope process PSS every second; record per-process PSS and CPU ticks every 10s.",
            "",
            "## Result",
            "",
            f"- Samples: {len(series)}; elapsed: {report['duration_s']}s; measured idle: {report['idle_duration_s']}s.",
            f"- Peak cgroup memory.current: {mib(peak_memory)} MiB; peak scope PSS: {mib(peak_pss)} MiB.",
            f"- Idle cgroup CPU: {report['idle_cpu_percent_of_one_core']}% of one core; CPU time delta: {cpu_delta} usec.",
            f"- Idle first-minute/last-minute process PSS medians (bytes): `{json.dumps(first_minute, sort_keys=True)}` / `{json.dumps(last_minute, sort_keys=True)}`.",
            f"- Close path: {events.get('app_closed', {}).get('close_method')}; app exit: {events.get('app_closed', {}).get('app_exit_code')}; RA services after +30s: {len(close_event.get('rust_services_left', []))}.",
            f"- OOM / OOM-kill final counters: {final_events.get('oom', 0)} / {final_events.get('oom_kill', 0)}.",
            "",
            "This is a WSLg/Xvfb software-rendering repeat, not native Linux DRM/WPE GBM evidence. Three repeats at one cgroup limit do not complete the full docs/04 platform and feature matrix.",
            "",
            f"Raw JSON: `{out_json.name}`.",
        ]
        out_md.write_text("\n".join(lines) + "\n")
        print(json.dumps({"json": str(out_json), "markdown": str(out_md), "idle_cpu_percent": report["idle_cpu_percent_of_one_core"], "peak_memory_mib": mib(peak_memory), "peak_pss_mib": mib(peak_pss), "scope_returncode": proc.returncode, "app_exit": report["process_exit_code"]}, ensure_ascii=False), flush=True)
        return 0 if proc.returncode == 0 and report["process_exit_code"] == 0 and not close_event.get("rust_services_left") else 1
    except BaseException:
        if proc.poll() is None:
            subprocess.run(["systemctl", "--user", "stop", unit_scope], capture_output=True, timeout=15, check=False)
            try:
                proc.wait(timeout=15)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=5)
        raise
    finally:
        shutil.rmtree(root, ignore_errors=True)
        if "out_json" in locals() and out_json.is_file():
            try:
                saved = json.loads(out_json.read_text())
                saved["temporary_data_removed"] = not root.exists()
                out_json.write_text(json.dumps(saved, ensure_ascii=False, indent=2) + "\n")
            except (OSError, json.JSONDecodeError):
                pass


if __name__ == "__main__":
    raise SystemExit(main())
