#!/usr/bin/env python3
"""Drive the Windows native drag/drop fixture with Win32 mouse input."""

from __future__ import annotations

import ctypes
import json
import os
from pathlib import Path
import subprocess
import sys
import time
from ctypes import wintypes


ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "app"
FIXTURE = "tool/editor_native_text_drag_drop_windows_fixture.dart"
PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
SW_RESTORE = 9
MOUSEEVENTF_LEFTDOWN = 0x0002
MOUSEEVENTF_LEFTUP = 0x0004


class RECT(ctypes.Structure):
    _fields_ = [
        ("left", wintypes.LONG),
        ("top", wintypes.LONG),
        ("right", wintypes.LONG),
        ("bottom", wintypes.LONG),
    ]


class POINT(ctypes.Structure):
    _fields_ = [("x", wintypes.LONG), ("y", wintypes.LONG)]


user32 = ctypes.WinDLL("user32", use_last_error=True)
kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)

WNDENUMPROC = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)


def _configure_apis() -> None:
    user32.EnumWindows.argtypes = [WNDENUMPROC, wintypes.LPARAM]
    user32.EnumWindows.restype = wintypes.BOOL
    user32.IsWindowVisible.argtypes = [wintypes.HWND]
    user32.IsWindowVisible.restype = wintypes.BOOL
    user32.GetWindowTextLengthW.argtypes = [wintypes.HWND]
    user32.GetWindowTextLengthW.restype = ctypes.c_int
    user32.GetWindowTextW.argtypes = [wintypes.HWND, wintypes.LPWSTR, ctypes.c_int]
    user32.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
    user32.GetWindowThreadProcessId.restype = wintypes.DWORD
    user32.GetClientRect.argtypes = [wintypes.HWND, ctypes.POINTER(RECT)]
    user32.GetClientRect.restype = wintypes.BOOL
    user32.ClientToScreen.argtypes = [wintypes.HWND, ctypes.POINTER(POINT)]
    user32.ClientToScreen.restype = wintypes.BOOL
    user32.ShowWindow.argtypes = [wintypes.HWND, ctypes.c_int]
    user32.SetForegroundWindow.argtypes = [wintypes.HWND]
    user32.SetForegroundWindow.restype = wintypes.BOOL
    user32.GetForegroundWindow.restype = wintypes.HWND
    user32.SetCursorPos.argtypes = [ctypes.c_int, ctypes.c_int]
    user32.SetCursorPos.restype = wintypes.BOOL
    user32.mouse_event.argtypes = [wintypes.DWORD, wintypes.DWORD, wintypes.DWORD, wintypes.DWORD, ctypes.c_size_t]
    kernel32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    kernel32.OpenProcess.restype = wintypes.HANDLE
    kernel32.QueryFullProcessImageNameW.argtypes = [wintypes.HANDLE, wintypes.DWORD, wintypes.LPWSTR, ctypes.POINTER(wintypes.DWORD)]
    kernel32.QueryFullProcessImageNameW.restype = wintypes.BOOL
    kernel32.CloseHandle.argtypes = [wintypes.HANDLE]


def _window_process_path(window: int) -> tuple[int, str]:
    process_id = wintypes.DWORD()
    user32.GetWindowThreadProcessId(window, ctypes.byref(process_id))
    handle = kernel32.OpenProcess(
        PROCESS_QUERY_LIMITED_INFORMATION, False, process_id.value
    )
    if not handle:
        return process_id.value, ""
    try:
        size = wintypes.DWORD(32768)
        path = ctypes.create_unicode_buffer(size.value)
        if not kernel32.QueryFullProcessImageNameW(
            handle, 0, path, ctypes.byref(size)
        ):
            return process_id.value, ""
        return process_id.value, path.value
    finally:
        kernel32.CloseHandle(handle)


def find_app_window() -> tuple[int, int, str] | None:
    found: list[tuple[int, int, str]] = []

    @WNDENUMPROC
    def visit(window: int, _parameter: int) -> bool:
        if not user32.IsWindowVisible(window):
            return True
        length = user32.GetWindowTextLengthW(window)
        title = ctypes.create_unicode_buffer(length + 1)
        user32.GetWindowTextW(window, title, len(title))
        process_id, path = _window_process_path(window)
        if path.casefold().endswith("\\build\\windows\\x64\\runner\\debug\\alula_app.exe"):
            found.append((window, process_id, title.value))
        return True

    if not user32.EnumWindows(visit, 0):
        raise ctypes.WinError(ctypes.get_last_error())
    return found[-1] if found else None


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


def wait_for_window(process: subprocess.Popen[str], timeout: float) -> tuple[int, int, str]:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        window = find_app_window()
        if window:
            return window
        if process.poll() is not None:
            raise RuntimeError(
                f"Flutter fixture exited with status {process.returncode} before its window appeared."
            )
        time.sleep(0.1)
    raise TimeoutError("Timed out waiting for the visible alula_app Windows window.")


def set_cursor(x: int, y: int) -> None:
    if not user32.SetCursorPos(x, y):
        raise ctypes.WinError(ctypes.get_last_error())


def read_json_lines(path: Path) -> list[dict[str, object]]:
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()]


def main() -> int:
    if sys.platform != "win32":
        print("This native drag/drop helper requires Windows.", file=sys.stderr)
        return 2
    if len(sys.argv) != 2:
        print(f"Usage: {Path(sys.argv[0]).name} <diagnostics-directory>", file=sys.stderr)
        return 2

    _configure_apis()
    try:
        set_dpi_context = user32.SetProcessDpiAwarenessContext
        set_dpi_context.argtypes = [ctypes.c_void_p]
        set_dpi_context.restype = wintypes.BOOL
        if not set_dpi_context(ctypes.c_void_p(-4)):
            user32.SetProcessDPIAware()
    except AttributeError:
        user32.SetProcessDPIAware()

    diagnostics = Path(sys.argv[1]).resolve()
    diagnostics.mkdir(parents=True, exist_ok=True)
    environment = os.environ.copy()
    environment["ALULA_WINDOWS_DND_DIR"] = str(diagnostics)
    environment["ALULA_CORE_PATH"] = str(APP / "native" / "alula_core.dll")
    log_path = diagnostics / "flutter-run.log"
    process: subprocess.Popen[str] | None = None
    button_is_down = False

    try:
        with log_path.open("w", encoding="utf-8") as log:
            command = (
                "flutter run --no-pub -d windows "
                f"-t {FIXTURE}"
            )
            process = subprocess.Popen(
                [os.environ.get("COMSPEC", "cmd.exe"), "/d", "/s", "/c", command],
                cwd=APP,
                env=environment,
                stdin=subprocess.PIPE,
                stdout=log,
                stderr=subprocess.STDOUT,
                text=True,
                encoding="utf-8",
                errors="replace",
            )

            wait_for(diagnostics / "ready", process, timeout=240)
            layout = json.loads((diagnostics / "layout.json").read_text(encoding="utf-8"))
            window, window_process_id, title = wait_for_window(process, timeout=30)
            user32.ShowWindow(window, SW_RESTORE)
            foreground_requested = bool(user32.SetForegroundWindow(window))
            time.sleep(0.25)
            foreground_window = int(user32.GetForegroundWindow() or 0)
            if foreground_window != window:
                raise RuntimeError(
                    f"Could not activate Alula window (requested={foreground_requested}, "
                    f"foreground={foreground_window}, window={window})."
                )

            client = RECT()
            origin = POINT(0, 0)
            if not user32.GetClientRect(window, ctypes.byref(client)):
                raise ctypes.WinError(ctypes.get_last_error())
            if not user32.ClientToScreen(window, ctypes.byref(origin)):
                raise ctypes.WinError(ctypes.get_last_error())

            scale = float(layout["devicePixelRatio"])
            source_x = origin.x + round(float(layout["source"]["x"]) * scale)
            source_y = origin.y + round(float(layout["source"]["y"]) * scale)
            external_source_x = origin.x + round(
                float(layout["externalSource"]["x"]) * scale
            )
            external_source_y = origin.y + round(
                float(layout["externalSource"]["y"]) * scale
            )
            target_x = origin.x + round(float(layout["target"]["x"]) * scale)
            target_y = origin.y + round(float(layout["target"]["y"]) * scale)
            client_width = client.right - client.left
            client_height = client.bottom - client.top
            for label, x, y in (
                ("source", source_x, source_y),
                ("external source", external_source_x, external_source_y),
                ("target", target_x, target_y),
            ):
                client_x = x - origin.x
                client_y = y - origin.y
                if not (0 <= client_x < client_width and 0 <= client_y < client_height):
                    raise RuntimeError(
                        f"The {label} point is outside the client area: "
                        f"point=({client_x},{client_y}), "
                        f"client=({client_width},{client_height})."
                    )

            helper_log = {
                "windowHandle": window,
                "windowProcessId": window_process_id,
                "windowTitle": title,
                "foregroundWindow": foreground_window,
                "clientRect": {
                    "width": client_width,
                    "height": client_height,
                },
                "clientScreenOrigin": {"x": origin.x, "y": origin.y},
                "devicePixelRatio": scale,
                "sourceScreen": {"x": source_x, "y": source_y},
                "externalSourceScreen": {
                    "x": external_source_x,
                    "y": external_source_y,
                },
                "targetScreen": {"x": target_x, "y": target_y},
            }
            (diagnostics / "input-helper.json").write_text(
                json.dumps(helper_log, indent=2) + "\n", encoding="utf-8"
            )

            set_cursor(source_x, source_y)
            time.sleep(0.4)
            user32.mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, 0)
            button_is_down = True
            time.sleep(0.25)
            for step in range(1, 25):
                x = round(source_x + (target_x - source_x) * step / 24)
                y = round(source_y + (target_y - source_y) * step / 24)
                set_cursor(x, y)
                time.sleep(0.04)
            time.sleep(0.5)
            user32.mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, 0)
            button_is_down = False

            wait_for(diagnostics / "drop.json", process, timeout=20)
            wait_for(diagnostics / "drag-completed.json", process, timeout=10)
            drop = json.loads((diagnostics / "drop.json").read_text(encoding="utf-8"))
            completed = json.loads(
                (diagnostics / "drag-completed.json").read_text(encoding="utf-8")
            )
            expected = {
                "selectedText": "alpha",
                "operation": "move",
                "targetOffsetUtf16": 11,
            }
            if drop != expected:
                raise AssertionError(f"Unexpected drop result: {drop!r}")
            if completed != {"selectedText": "alpha", "operation": "move"}:
                raise AssertionError(f"Unexpected drag completion: {completed!r}")

            set_cursor(external_source_x, external_source_y)
            time.sleep(0.4)
            user32.mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, 0)
            button_is_down = True
            time.sleep(0.25)
            for step in range(1, 25):
                x = round(
                    external_source_x
                    + (target_x - external_source_x) * step / 24
                )
                y = round(
                    external_source_y
                    + (target_y - external_source_y) * step / 24
                )
                set_cursor(x, y)
                time.sleep(0.04)
            time.sleep(0.5)
            user32.mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, 0)
            button_is_down = False

            wait_for(diagnostics / "external-drop.json", process, timeout=20)
            external_drop = json.loads(
                (diagnostics / "external-drop.json").read_text(encoding="utf-8")
            )
            expected_external = {
                "text": "external text",
                "targetDocumentId": 7002,
                "targetDocumentVersion": 4,
                "targetOffsetUtf16": 6,
            }
            if external_drop != expected_external:
                raise AssertionError(
                    f"Unexpected external drop result: {external_drop!r}"
                )

            pointer_events = read_json_lines(diagnostics / "pointer-events.jsonl")
            pointer_types = {str(event["type"]) for event in pointer_events}
            if not {"down", "move"}.issubset(pointer_types):
                raise AssertionError(
                    f"Flutter did not receive the complete pointer path: {pointer_types!r}"
                )
            if not {"up", "cancel"}.intersection(pointer_types):
                raise AssertionError(
                    "Flutter received neither pointer-up nor pointer-cancel to end the drag: "
                    f"{pointer_types!r}"
                )
            if not (diagnostics / "payload-at.jsonl").exists():
                raise AssertionError("Flutter never asked the source for a drag payload.")
            if not (diagnostics / "drop-over.jsonl").exists():
                raise AssertionError("Flutter never delivered a drop-over callback.")

            summary = {
                "window": helper_log,
                "layout": layout,
                "drop": drop,
                "dragCompleted": completed,
                "externalDrop": external_drop,
                "flutterPointerEventCount": len(pointer_events),
                "flutterPointerEventTypes": sorted(pointer_types),
            }
            (diagnostics / "result.json").write_text(
                json.dumps(summary, indent=2) + "\n", encoding="utf-8"
            )
            print(json.dumps(summary, indent=2))

            if process.stdin is not None:
                process.stdin.write("q\n")
                process.stdin.flush()
            process.wait(timeout=20)
            if process.returncode != 0:
                raise RuntimeError(f"Flutter fixture exit status was {process.returncode}.")
        return 0
    except Exception as error:  # noqa: BLE001 - print diagnostics for CI failures.
        print(f"Windows native drag/drop probe failed: {error}", file=sys.stderr)
        if log_path.exists():
            print(log_path.read_text(encoding="utf-8", errors="replace")[-16000:], file=sys.stderr)
        return 1
    finally:
        if button_is_down:
            user32.mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, 0)
        if process is not None and process.poll() is None:
            subprocess.run(
                ["taskkill", "/PID", str(process.pid), "/T", "/F"],
                capture_output=True,
                check=False,
            )
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()


if __name__ == "__main__":
    raise SystemExit(main())
