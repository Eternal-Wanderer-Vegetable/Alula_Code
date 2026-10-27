import base64
import hashlib
import json
import os
import re
import socket
import struct
import time
import urllib.request

HOST, PORT = "127.0.0.1", 9231
PHASE = "/tmp/inspector-protocol-run/tmp/p00.4-web-probe-phase.txt"
OUT = "/tmp/inspector-protocol-run/protocol-session.json"

def save(record):
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(record, f, ensure_ascii=False, indent=2)

def fail(message, **details):
    save({"status": "failed", "error": message, **details})
    raise SystemExit(message)

deadline = time.time() + 35
phase = None
while time.time() < deadline:
    try:
        phase = open(PHASE, encoding="utf-8").read().strip()
    except FileNotFoundError:
        pass
    if phase in ("initial-loaded", "mhtml-loaded"):
        break
    if phase == "webview-destroyed":
        fail("WebView was destroyed before the Inspector command was sent.")
    time.sleep(0.1)
if phase not in ("initial-loaded", "mhtml-loaded"):
    fail("Timed out waiting for an active WebView; last phase={!r}".format(phase))

try:
    with urllib.request.urlopen("http://{}:{}/".format(HOST, PORT), timeout=3) as response:
        target_list = response.read().decode("utf-8", "replace")
        http_status = response.status
except Exception as e:
    fail("Inspector target list request failed: {}".format(e))
match = re.search(r"window\.location\.host \+ '(/socket/[^']+)'", target_list)
if not match:
    fail("No WebSocket target path found in target list.")
path = match.group(1)

sock = socket.create_connection((HOST, PORT), timeout=5)
sock.settimeout(5)
key = base64.b64encode(os.urandom(16)).decode("ascii")
request = (
    "GET {} HTTP/1.1\r\nHost: {}:{}\r\nUpgrade: websocket\r\n"
    "Connection: Upgrade\r\nSec-WebSocket-Key: {}\r\n"
    "Sec-WebSocket-Version: 13\r\nOrigin: http://{}:{}\r\n\r\n"
).format(path, HOST, PORT, key, HOST, PORT).encode("ascii")
sock.sendall(request)
response = b""
while b"\r\n\r\n" not in response:
    chunk = sock.recv(4096)
    if not chunk:
        fail("Socket closed during WebSocket handshake.")
    response += chunk
header = response.split(b"\r\n\r\n", 1)[0].decode("latin1")
expected_accept = base64.b64encode(hashlib.sha1(
    (key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()
).digest()).decode()
if " 101 " not in header or "Sec-WebSocket-Accept: {}".format(expected_accept).lower() not in header.lower():
    fail("WebSocket handshake did not validate.", handshake=header)

def send_frame(opcode, payload):
    mask = os.urandom(4)
    length = len(payload)
    first = bytes([0x80 | opcode])
    if length < 126:
        head = first + bytes([0x80 | length])
    elif length <= 0xFFFF:
        head = first + bytes([0x80 | 126]) + struct.pack("!H", length)
    else:
        head = first + bytes([0x80 | 127]) + struct.pack("!Q", length)
    masked = bytes(value ^ mask[i % 4] for i, value in enumerate(payload))
    sock.sendall(head + mask + masked)

def read_exact(count):
    result = bytearray()
    while len(result) < count:
        part = sock.recv(count - len(result))
        if not part:
            raise EOFError("WebSocket closed")
        result.extend(part)
    return bytes(result)

def read_message():
    while True:
        first, second = read_exact(2)
        opcode = first & 0x0F
        length = second & 0x7F
        if length == 126:
            length = struct.unpack("!H", read_exact(2))[0]
        elif length == 127:
            length = struct.unpack("!Q", read_exact(8))[0]
        mask = read_exact(4) if second & 0x80 else None
        payload = read_exact(length)
        if mask:
            payload = bytes(value ^ mask[i % 4] for i, value in enumerate(payload))
        if opcode == 9:
            send_frame(10, payload)
            continue
        if opcode == 8:
            raise EOFError("Inspector closed the WebSocket")
        if opcode == 1:
            return json.loads(payload.decode("utf-8"))

outer_messages = []
deadline = time.time() + 4
page_target_id = None
while time.time() < deadline:
    try:
        message = read_message()
    except socket.timeout:
        continue
    outer_messages.append(message)
    if message.get("method") == "Target.targetCreated":
        info = message.get("params", {}).get("targetInfo", {})
        if info.get("type") == "page":
            page_target_id = info.get("targetId")
            break
if not page_target_id:
    fail("The multiplexing inspector did not announce a page target.", outer_messages=outer_messages)

def send_nested(outer_id, nested_id, method, params=None):
    nested = {"id": nested_id, "method": method}
    if params:
        nested["params"] = params
    envelope = {
        "id": outer_id,
        "method": "Target.sendMessageToTarget",
        "params": {"targetId": page_target_id, "message": json.dumps(nested, separators=(",", ":"))}
    }
    send_frame(1, json.dumps(envelope, separators=(",", ":")).encode("utf-8"))

def wait_nested(nested_id, timeout_seconds=4):
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        try:
            message = read_message()
        except socket.timeout:
            continue
        outer_messages.append(message)
        if message.get("method") != "Target.dispatchMessageFromTarget":
            continue
        params = message.get("params", {})
        if params.get("targetId") != page_target_id:
            continue
        try:
            inner = json.loads(params.get("message", "{}"))
        except json.JSONDecodeError:
            continue
        if inner.get("id") == nested_id:
            return inner
    return None

send_nested(1, 41, "Runtime.enable")
enable_response = wait_nested(41)
if enable_response is None:
    fail("No Runtime.enable response from the page target.", page_target_id=page_target_id, outer_messages=outer_messages)
if enable_response.get("error"):
    fail("Runtime.enable returned a protocol error.", page_target_id=page_target_id, enable_response=enable_response, outer_messages=outer_messages)

send_nested(2, 42, "Runtime.evaluate", {
    "expression": "JSON.stringify({title:document.title,marker:document.body.innerText.includes('WEB_ENGINE_PROBE_OK')})",
    "returnByValue": True
})
evaluate_response = wait_nested(42)
if evaluate_response is None:
    fail("No Runtime.evaluate response from the page target.", page_target_id=page_target_id, outer_messages=outer_messages)
record = {
    "status": "protocol-error-response" if evaluate_response.get("error") else "command-succeeded",
    "target_list_http_status": http_status,
    "websocket_path": path,
    "websocket_handshake": "101 Switching Protocols",
    "multiplexing_page_target_id": page_target_id,
    "commands": [
        {"method": "Runtime.enable", "response": enable_response},
        {"method": "Runtime.evaluate", "params": {
            "expression": "JSON.stringify({title:document.title,marker:document.body.innerText.includes('WEB_ENGINE_PROBE_OK')})",
            "returnByValue": True
        }, "response": evaluate_response}
    ],
    "outer_messages": outer_messages
}
save(record)
sock.close()
if evaluate_response.get("error"):
    raise SystemExit("Runtime.evaluate returned a protocol error: {}".format(evaluate_response["error"]))
value = evaluate_response.get("result", {}).get("result", {}).get("value")
if not value:
    raise SystemExit("Runtime.evaluate succeeded without a returned page value.")
print("Inspector Runtime.evaluate returned: {}".format(value))
