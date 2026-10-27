#!/usr/bin/python3
import gc
import argparse
import json
import os
import time
from pathlib import Path

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
gi.require_version("WebKit2", "4.1")
gi.require_foreign("cairo")
from gi.repository import Gdk, Gio, GLib, Gtk, WebKit2

parser = argparse.ArgumentParser(description="Run the Linux WebKitGTK P00.4 engine probe")
parser.add_argument("--output-dir", required=True, help="Directory for phase JSON, screenshots, and MHTML")
OUT = Path(parser.parse_args().output_dir).expanduser().resolve()
OUT.mkdir(parents=True, exist_ok=True)
ARCHIVE = OUT / "p00.4-linux-webkitgtk.mhtml"
HTML = """<!doctype html>
<html><head><meta charset="utf-8"><title>P00.4 WebKitGTK Linux Probe</title>
<style>body{background:#17191f;color:#f5f5f5;font:24px sans-serif;padding:32px}
img{width:32px;height:32px} .marker{color:#83e08b}</style></head>
<body data-ready="true"><h1 class="marker">WEBKITGTK_LINUX_PROBE_OK</h1>
<p>Offline MHTML, snapshot, inspector, and lifecycle experiment.</p>
<img alt="embedded pixel" src="data:image/gif;base64,R0lGODlhAQABAAD/ACwAAAAAAQABAAACADs=">
</body></html>"""

window = None
view = None
inspector = None
phase = "before-webview"
started = time.monotonic()
exit_status = 0


def process_tree(root_pid):
    rows = {}
    for entry in Path("/proc").iterdir():
        if not entry.name.isdigit():
            continue
        pid = int(entry.name)
        try:
            stat = (entry / "stat").read_text()
            close = stat.rfind(")")
            comm = stat[stat.find("(") + 1:close]
            fields = stat[close + 2:].split()
            ppid = int(fields[1])
            rows[pid] = {"pid": pid, "ppid": ppid, "comm": comm}
        except (OSError, ValueError, IndexError):
            continue
    descendants = {root_pid}
    changed = True
    while changed:
        changed = False
        for pid, row in rows.items():
            if row["ppid"] in descendants and pid not in descendants:
                descendants.add(pid)
                changed = True
    result = []
    for pid in sorted(descendants):
        row = dict(rows.get(pid, {"pid": pid, "ppid": None, "comm": "unknown"}))
        try:
            for line in (Path("/proc") / str(pid) / "smaps_rollup").read_text().splitlines():
                if line.startswith("Rss:"):
                    row["rss_kib"] = int(line.split()[1])
                elif line.startswith("Private_Clean:") or line.startswith("Private_Dirty:"):
                    row["private_kib"] = row.get("private_kib", 0) + int(line.split()[1])
        except (OSError, ValueError, IndexError):
            pass
        result.append(row)
    return result


def mark(name, **extra):
    data = {
        "phase": name,
        "capturedAtMonotonicSeconds": round(time.monotonic() - started, 3),
        "rootPid": os.getpid(),
        "webkitgtkVersion": ".".join(map(str, (
            WebKit2.get_major_version(),
            WebKit2.get_minor_version(),
            WebKit2.get_micro_version(),
        ))),
        "processes": process_tree(os.getpid()),
    }
    data.update(extra)
    path = OUT / f"{name}.json"
    path.write_text(json.dumps(data, indent=2) + "\n")
    print("P00_4_LINUX_PHASE=" + json.dumps({"phase": name, "path": str(path)}), flush=True)


def snapshot(widget, path, done):
    def finished(web_view, result, _user_data):
        try:
            surface = web_view.get_snapshot_finish(result)
            surface.write_to_png(str(path))
            done({"ok": True, "path": path.name, "width": surface.get_width(), "height": surface.get_height()})
        except Exception as exc:
            done({"ok": False, "path": path.name, "error": repr(exc)})
    widget.get_snapshot(WebKit2.SnapshotRegion.VISIBLE, WebKit2.SnapshotOptions.NONE, None, finished, None)


def open_inspector_and_finish():
    global inspector
    try:
        inspector = view.get_inspector()
        inspector.show()
        mark("inspector-open", inspectorType=type(inspector).__name__)
        GLib.timeout_add_seconds(3, capture_inspector)
    except Exception as exc:
        mark("inspector-open", inspectorError=repr(exc))
        destroy_view()
    return GLib.SOURCE_REMOVE


def capture_inspector():
    global exit_status
    screenshots = []
    try:
        gdk_window = window.get_window()
        width, height = window.get_size()
        pixbuf = Gdk.pixbuf_get_from_window(gdk_window, 0, 0, width, height)
        if pixbuf is not None:
            path = OUT / "p00.4-linux-webkitgtk-inspector.png"
            pixbuf.savev(str(path), "png", [], [])
            screenshots.append({
                "ok": True,
                "title": window.get_title(),
                "path": path.name,
                "width": pixbuf.get_width(),
                "height": pixbuf.get_height(),
            })
        else:
            screenshots.append({"ok": False, "error": "GDK returned no main-window snapshot"})
    except Exception as exc:
        screenshots.append({"ok": False, "error": repr(exc)})
    if not inspector.is_attached() or not any(item.get("ok") for item in screenshots):
        exit_status = 1
    mark("inspector-open-completed",
         inspectedUri=inspector.get_inspected_uri(),
         attached=inspector.is_attached(),
         canAttach=inspector.get_can_attach(),
         windows=screenshots)
    close_inspector_and_destroy({"windows": screenshots})
    return GLib.SOURCE_REMOVE


def close_inspector_and_destroy(inspector_snapshot):
    try:
        inspector.close()
    except Exception:
        pass
    destroy_view(inspectorScreenshot=inspector_snapshot)
    return GLib.SOURCE_REMOVE


def destroy_view(inspectorScreenshot=None):
    global view
    try:
        if view is not None:
            parent = view.get_parent()
            if parent is not None:
                parent.remove(view)
            view.destroy()
            view = None
            gc.collect()
    finally:
        mark("destroyed", inspectorScreenshot=inspectorScreenshot)
        GLib.timeout_add_seconds(30, finish)


def finish():
    mark("destroyed-30s")
    Gtk.main_quit()
    return GLib.SOURCE_REMOVE


def on_timeout():
    global exit_status
    exit_status = 1
    mark("timeout")
    Gtk.main_quit()
    return GLib.SOURCE_REMOVE


def on_snapshot_initial(result):
    global phase, exit_status
    mark("web-open", initialScreenshot=result)
    if not result.get("ok"):
        exit_status = 1
    phase = "saving-mhtml"
    view.save_to_file(Gio.File.new_for_path(str(ARCHIVE)), WebKit2.SaveMode.MHTML, None, on_mhtml_saved, None)


def on_mhtml_saved(web_view, result, _user_data):
    global phase, exit_status
    try:
        success = web_view.save_to_file_finish(result)
        content = ARCHIVE.read_bytes()
        mime_header = b"MIME-Version:" in content
        marker_present = b"WEBKITGTK_LINUX_PROBE_OK" in content
        mark("mhtml-exported", success=success, archivePath=ARCHIVE.name,
             archiveBytes=len(content), mimeHeader=mime_header,
             markerPresent=marker_present)
        if not success or not mime_header or not marker_present:
            exit_status = 1
        phase = "mhtml-reload"
        web_view.load_uri(Gio.File.new_for_path(str(ARCHIVE)).get_uri())
    except Exception as exc:
        exit_status = 1
        mark("mhtml-export-failed", error=repr(exc))
        destroy_view()


def on_load_changed(web_view, event):
    global phase
    if event != WebKit2.LoadEvent.FINISHED:
        return
    if phase == "initial":
        phase = "snapshot-initial"
        snapshot(web_view, OUT / "p00.4-linux-webkitgtk-open.png", on_snapshot_initial)
    elif phase == "mhtml-reload":
        phase = "snapshot-mhtml"
        snapshot(web_view, OUT / "p00.4-linux-webkitgtk-mhtml-opened.png",
                 lambda result: on_mhtml_snapshot(result))


def on_mhtml_snapshot(result):
    global exit_status
    if not result.get("ok"):
        exit_status = 1
    mark("mhtml-open", mhtmlUri=view.get_uri(), screenshot=result)
    open_inspector_and_finish()


def on_load_failed(web_view, event, uri, error):
    global phase, exit_status
    exit_status = 1
    mark("load-failed", phase=phase, uri=uri, error=str(error))
    if phase in {"initial", "mhtml-reload"}:
        destroy_view(loadError=str(error))
    return False


def create_view():
    global view, phase
    phase = "initial"
    view = WebKit2.WebView()
    view.get_settings().set_property("enable-developer-extras", True)
    view.connect("load-changed", on_load_changed)
    view.connect("load-failed", on_load_failed)
    window.add(view)
    view.show()
    mark("webview-created")
    view.load_html(HTML, "file:///tmp/p00-4-linux-probe.html")
    return GLib.SOURCE_REMOVE


def start_view():
    GLib.timeout_add_seconds(2, create_view)
    return GLib.SOURCE_REMOVE


Gtk.init([])
window = Gtk.Window(title="P00.4 Linux WebKitGTK Probe")
window.set_default_size(960, 640)
window.connect("destroy", lambda *_: Gtk.main_quit())
window.show_all()
mark("before-webview")
GLib.timeout_add_seconds(2, start_view)
GLib.timeout_add_seconds(90, on_timeout)
Gtk.main()
if exit_status:
    raise SystemExit(exit_status)
