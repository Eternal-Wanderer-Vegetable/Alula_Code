#!/usr/bin/env python3
"""Drive the Linux native drag/drop fixture with X11 pointer input."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import time


ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "app"
FIXTURE = "tool/editor_native_text_drag_drop_linux_fixture.dart"


def run_xdotool(*arguments: str) -> str:
    result = subprocess.run(
        ["xdotool", *arguments],
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


def wait_for(path: Path, process: subprocess.Popen[str], timeout: float) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if path.exists():
            return
        if process.poll() is not None:
            raise RuntimeError(
                f"Flutter fixture exited with status {process.returncode} before {path.name}."
            )
        time.sleep(0.1)
    raise TimeoutError(f"Timed out waiting for {path.name}.")


def wait_for_window(process: subprocess.Popen[str], timeout: float) -> str:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        result = subprocess.run(
            ["xdotool", "search", "--onlyvisible", "--name", "alula_app"],
            capture_output=True,
            text=True,
        )
        windows = result.stdout.split()
        if result.returncode == 0 and windows:
            return windows[-1]
        if process.poll() is not None:
            raise RuntimeError(
                f"Flutter fixture exited with status {process.returncode} before its window appeared."
            )
        time.sleep(0.1)
    raise TimeoutError("Timed out waiting for the visible alula_app X11 window.")


def main() -> int:
    if len(sys.argv) != 2:
        print(f"Usage: {Path(sys.argv[0]).name} <diagnostics-directory>", file=sys.stderr)
        return 2

    diagnostics = Path(sys.argv[1]).resolve()
    diagnostics.mkdir(parents=True, exist_ok=True)
    environment = os.environ.copy()
    environment["ALULA_LINUX_DND_DIR"] = str(diagnostics)
    log_path = diagnostics / "flutter-run.log"
    process: subprocess.Popen[str] | None = None

    try:
        with log_path.open("w", encoding="utf-8") as log:
            process = subprocess.Popen(
                [
                    "flutter",
                    "run",
                    "--no-pub",
                    "-d",
                    "linux",
                    "-t",
                    FIXTURE,
                ],
                cwd=APP,
                env=environment,
                stdin=subprocess.PIPE,
                stdout=log,
                stderr=subprocess.STDOUT,
                text=True,
            )

            wait_for(diagnostics / "ready", process, timeout=180)
            layout = json.loads((diagnostics / "layout.json").read_text())
            window_id = wait_for_window(process, timeout=30)

            scale = float(layout["devicePixelRatio"])
            source_x = round(float(layout["source"]["x"]) * scale)
            source_y = round(float(layout["source"]["y"]) * scale)
            external_source_x = round(float(layout["externalSource"]["x"]) * scale)
            external_source_y = round(float(layout["externalSource"]["y"]) * scale)
            target_x = round(float(layout["target"]["x"]) * scale)
            target_y = round(float(layout["target"]["y"]) * scale)

            run_xdotool("windowraise", window_id)
            run_xdotool("windowfocus", "--sync", window_id)
            run_xdotool("mousemove", "--sync", "--window", window_id, str(source_x), str(source_y))
            time.sleep(0.4)
            run_xdotool("mousedown", "1")
            time.sleep(0.3)
            for step in range(1, 25):
                x = round(source_x + (target_x - source_x) * step / 24)
                y = round(source_y + (target_y - source_y) * step / 24)
                run_xdotool("mousemove", "--sync", "--window", window_id, str(x), str(y))
                time.sleep(0.04)
            time.sleep(0.5)
            run_xdotool("mouseup", "1")

            wait_for(diagnostics / "drop.json", process, timeout=15)
            wait_for(diagnostics / "drag-completed.json", process, timeout=5)
            result = json.loads((diagnostics / "drop.json").read_text())
            completed = json.loads((diagnostics / "drag-completed.json").read_text())
            expected = {
                "selectedText": "alpha",
                "operation": "move",
                "targetOffsetUtf16": 11,
            }
            if result != expected:
                raise AssertionError(f"Unexpected drop result: {result!r}")
            if completed != {"selectedText": "alpha", "operation": "move"}:
                raise AssertionError(f"Unexpected drag completion: {completed!r}")

            run_xdotool(
                "mousemove", "--sync", "--window", window_id,
                str(external_source_x), str(external_source_y),
            )
            time.sleep(0.4)
            run_xdotool("mousedown", "1")
            time.sleep(0.3)
            for step in range(1, 25):
                x = round(external_source_x + (target_x - external_source_x) * step / 24)
                y = round(external_source_y + (target_y - external_source_y) * step / 24)
                run_xdotool("mousemove", "--sync", "--window", window_id, str(x), str(y))
                time.sleep(0.04)
            time.sleep(0.5)
            run_xdotool("mouseup", "1")

            wait_for(diagnostics / "external-drop.json", process, timeout=15)
            external_drop = json.loads(
                (diagnostics / "external-drop.json").read_text()
            )
            expected_external = {
                "text": "external text",
                "targetDocumentId": 7002,
                "targetDocumentVersion": 4,
                "targetOffsetUtf16": 6,
            }
            if external_drop != expected_external:
                raise AssertionError(f"Unexpected external drop result: {external_drop!r}")

            pointer_events = [
                json.loads(line)
                for line in (diagnostics / "pointer-events.jsonl").read_text().splitlines()
            ]
            pointer_types = {event["type"] for event in pointer_events}
            if not {"down", "move"}.issubset(pointer_types):
                raise AssertionError(f"Flutter did not receive pointer input: {pointer_types!r}")

            summary = {
                "windowId": window_id,
                "layout": layout,
                "drop": result,
                "dragCompleted": completed,
                "externalDrop": external_drop,
                "flutterPointerEventCount": len(pointer_events),
                "flutterPointerEventTypes": sorted(pointer_types),
            }
            (diagnostics / "result.json").write_text(json.dumps(summary, indent=2) + "\n")
            print(json.dumps(summary, indent=2))

            if process.stdin is not None:
                process.stdin.write("q\n")
                process.stdin.flush()
            process.wait(timeout=15)
            if process.returncode != 0:
                raise RuntimeError(f"Flutter fixture exit status was {process.returncode}.")
        return 0
    except Exception as error:  # noqa: BLE001 - print diagnostics for CI failures.
        print(f"Linux native drag/drop probe failed: {error}", file=sys.stderr)
        if log_path.exists():
            print(log_path.read_text(errors="replace")[-12000:], file=sys.stderr)
        return 1
    finally:
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()


if __name__ == "__main__":
    raise SystemExit(main())
