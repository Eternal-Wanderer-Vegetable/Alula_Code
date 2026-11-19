#!/usr/bin/env python3
"""Exercise Alula's auxiliary focus registry with native window activation."""

from __future__ import annotations

import argparse
import ctypes
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile
import time
from typing import Callable
from ctypes import wintypes


MAIN_TITLE = "Alula Focus Main"
AUXILIARY_TITLE = "Alula Focus Probe"
ALLOWED_SNAPSHOT_KEYS = {"windowId", "groupId", "revision"}
DOCUMENT_SENTINEL = "FOCUS_DOCUMENT_SECRET_DO_NOT_SYNC"


def linux_windows() -> dict[str, int]:
    result: dict[str, int] = {}
    ids = subprocess.run(
        ["xdotool", "search", "--onlyvisible", "--name", "Alula Focus"],
        check=False,
        capture_output=True,
        text=True,
    )
    for value in ids.stdout.splitlines():
        title = subprocess.run(
            ["xdotool", "getwindowname", value],
            check=False,
            capture_output=True,
            text=True,
        ).stdout.strip()
        if title == MAIN_TITLE:
            result["main"] = int(value)
        elif title == AUXILIARY_TITLE:
            result["auxiliary"] = int(value)
    return result


def windows_windows() -> dict[str, int]:
    user32 = ctypes.windll.user32
    user32.IsWindowVisible.argtypes = [wintypes.HWND]
    user32.IsWindowVisible.restype = wintypes.BOOL
    user32.GetWindowTextLengthW.argtypes = [wintypes.HWND]
    user32.GetWindowTextLengthW.restype = ctypes.c_int
    user32.GetWindowTextW.argtypes = [wintypes.HWND, wintypes.LPWSTR, ctypes.c_int]
    user32.GetWindowTextW.restype = ctypes.c_int
    found: dict[str, int] = {}
    callback_type = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)

    def visit(hwnd: int, _lparam: int) -> bool:
        if not user32.IsWindowVisible(hwnd):
            return True
        length = user32.GetWindowTextLengthW(hwnd)
        if length <= 0:
            return True
        buffer = ctypes.create_unicode_buffer(length + 1)
        user32.GetWindowTextW(hwnd, buffer, length + 1)
        title = buffer.value
        if title == MAIN_TITLE:
            found["main"] = int(hwnd)
        elif title == AUXILIARY_TITLE:
            found["auxiliary"] = int(hwnd)
        return len(found) != 2

    callback = callback_type(visit)
    user32.EnumWindows(callback, 0)
    return found


def find_windows() -> dict[str, int]:
    if sys.platform == "win32":
        return windows_windows()
    if sys.platform.startswith("linux"):
        return linux_windows()
    raise RuntimeError(f"Unsupported native focus smoke platform: {sys.platform}")


def activate_window(hwnd: int) -> None:
    if sys.platform == "win32":
        user32 = ctypes.windll.user32
        user32.AllowSetForegroundWindow.argtypes = [wintypes.DWORD]
        user32.ShowWindow.argtypes = [wintypes.HWND, ctypes.c_int]
        user32.SetForegroundWindow.argtypes = [wintypes.HWND]
        user32.SetForegroundWindow.restype = wintypes.BOOL
        user32.GetForegroundWindow.restype = wintypes.HWND
        user32.AllowSetForegroundWindow(0xFFFFFFFF)
        user32.ShowWindow(hwnd, 9)  # SW_RESTORE
        if not user32.SetForegroundWindow(hwnd):
            raise RuntimeError(f"SetForegroundWindow rejected HWND {hwnd}")
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if int(user32.GetForegroundWindow()) == hwnd:
                return
            time.sleep(0.05)
        raise RuntimeError(f"HWND {hwnd} did not become the foreground window")

    subprocess.run(["xdotool", "windowraise", str(hwnd)], check=True)
    subprocess.run(["xdotool", "windowfocus", "--sync", str(hwnd)], check=True)


def read_snapshots(path: Path) -> list[dict[str, object]]:
    if not path.exists():
        return []
    snapshots: list[dict[str, object]] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        try:
            value = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(value, dict):
            snapshots.append(value)
    return snapshots


def wait_for(
    description: str,
    predicate: Callable[[], object],
    timeout: float = 40,
) -> object:
    deadline = time.monotonic() + timeout
    last: object = None
    while time.monotonic() < deadline:
        last = predicate()
        if last:
            return last
        time.sleep(0.1)
    raise TimeoutError(f"Timed out waiting for {description}; last value: {last!r}")


def wait_for_snapshot(
    trace: Path,
    window_id: str,
    after_revision: int = -1,
) -> dict[str, object]:
    def find() -> dict[str, object] | None:
        for snapshot in reversed(read_snapshots(trace)):
            if (
                snapshot.get("windowId") == window_id
                and isinstance(snapshot.get("revision"), int)
                and snapshot["revision"] > after_revision
            ):
                return snapshot
        return None

    return wait_for(f"focus snapshot for {window_id}", find)  # type: ignore[return-value]


def run(executable: Path, output_directory: Path) -> dict[str, object]:
    executable = executable.resolve()
    output_directory = output_directory.resolve()
    output_directory.mkdir(parents=True, exist_ok=True)
    trace = output_directory / "focus-snapshots.jsonl"
    trace.write_text("", encoding="utf-8")
    state_directory = Path(tempfile.mkdtemp(prefix="alula-aux-focus-state-"))
    env = os.environ.copy()
    env["ALULA_AUXILIARY_FOCUS_SMOKE_DIR"] = str(state_directory)
    env["ALULA_AUXILIARY_FOCUS_TRACE"] = str(trace)
    process = subprocess.Popen([str(executable)], cwd=executable.parent, env=env)
    try:
        windows_value = wait_for(
            "main and auxiliary native windows",
            lambda: (found if len(found := find_windows()) == 2 else None),
        )
        windows = windows_value
        records = wait_for("initial main focus snapshot", lambda: (
            found if (found := read_snapshots(trace)) else None
        ))
        main_snapshot = records[0]  # type: ignore[index]
        main_id = str(main_snapshot["windowId"])
        first_aux = wait_for(
            "auxiliary focus snapshot",
            lambda: next(
                (
                    snapshot
                    for snapshot in read_snapshots(trace)
                    if snapshot.get("windowId") != main_id
                ),
                None,
            ),
        )
        first_aux = first_aux  # narrowed by wait_for at runtime
        auxiliary_id = str(first_aux["windowId"])
        assert windows["main"] and windows["auxiliary"]  # type: ignore[index]

        activate_window(windows["main"])  # type: ignore[index]
        main_after_aux = wait_for_snapshot(
            trace,
            main_id,
            int(first_aux["revision"]),
        )
        activate_window(windows["auxiliary"])  # type: ignore[index]
        aux_after_main = wait_for_snapshot(
            trace,
            auxiliary_id,
            int(main_after_aux["revision"]),
        )
        activate_window(windows["main"])  # type: ignore[index]
        main_after_round_trip = wait_for_snapshot(
            trace,
            main_id,
            int(aux_after_main["revision"]),
        )

        if auxiliary_id == main_id:
            raise AssertionError("Main and auxiliary windows shared an ID")
        if not str(first_aux["groupId"]).startswith(f"{auxiliary_id}:"):
            raise AssertionError(f"Unexpected auxiliary group: {first_aux!r}")
        if not str(main_after_aux["groupId"]).startswith(f"{main_id}:"):
            raise AssertionError(f"Unexpected main group: {main_after_aux!r}")
        if not str(aux_after_main["groupId"]).startswith(f"{auxiliary_id}:"):
            raise AssertionError(f"Unexpected auxiliary group: {aux_after_main!r}")
        if not str(main_after_round_trip["groupId"]).startswith(f"{main_id}:"):
            raise AssertionError(f"Unexpected main group: {main_after_round_trip!r}")

        all_snapshots = read_snapshots(trace)
        for snapshot in all_snapshots:
            if set(snapshot) != ALLOWED_SNAPSHOT_KEYS:
                raise AssertionError(f"Unexpected focus snapshot fields: {snapshot!r}")
        trace_text = trace.read_text(encoding="utf-8")
        if DOCUMENT_SENTINEL in trace_text:
            raise AssertionError("Document content appeared in the focus trace")

        report = {
            "platform": platform.platform(),
            "transitionSnapshots": [first_aux, main_after_aux, aux_after_main, main_after_round_trip],
            "snapshotKeys": sorted(ALLOWED_SNAPSHOT_KEYS),
            "documentSentinelAbsent": True,
        }
        (output_directory / "native-focus-result.json").write_text(
            json.dumps(report, indent=2) + "\n",
            encoding="utf-8",
        )
        return report
    finally:
        process.terminate()
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)
        shutil.rmtree(state_directory, ignore_errors=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("executable", type=Path)
    parser.add_argument("output_directory", type=Path)
    args = parser.parse_args()
    report = run(args.executable, args.output_directory)
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
