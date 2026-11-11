#!/usr/bin/env python3
"""The control panel for the Zonic web session.

Caddy puts this behind the same password as the stream and routes /settings and /api/*
here. It does three things: say whether the session is running, start it, and stop it.
Everything else about the session is Selkies' business.

Standard library only, on purpose. This runs on a 2 GB box next to a browser.
"""

import calendar
import json
import os
import subprocess
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

STATE_DIR = os.environ.get("ZONIC_STATE", "/var/lib/zonic")
MARKER = os.environ.get("ZONIC_MARKER", "/opt/zonic/server/data/state/disconnected")
COMPOSE = os.environ.get("ZONIC_COMPOSE", "/opt/zonic/server/docker-compose.yml")
SERVICE = os.environ.get("ZONIC_SERVICE", "session")
CONTAINER = os.environ.get("ZONIC_CONTAINER", "zonic-session")
PORT = int(os.environ.get("ZONIC_GATE_PORT", "8091"))
DEFAULT_IDLE = int(os.environ.get("ZONIC_IDLE_MINUTES", "10"))


# --- small state helpers -------------------------------------------------------------


def read_state(name, default):
    try:
        with open(os.path.join(STATE_DIR, name), encoding="utf-8") as handle:
            value = handle.read().strip()
        return value or default
    except OSError:
        return default


def write_state(name, value):
    os.makedirs(STATE_DIR, exist_ok=True)
    target = os.path.join(STATE_DIR, name)
    temporary = target + ".tmp"
    with open(temporary, "w", encoding="utf-8") as handle:
        handle.write(str(value))
    os.replace(temporary, target)


def idle_minutes():
    try:
        return max(1, int(read_state("idle_minutes", DEFAULT_IDLE)))
    except ValueError:
        return DEFAULT_IDLE


# --- docker --------------------------------------------------------------------------


def docker(*args, timeout=120):
    try:
        return subprocess.run(
            ["docker", *args], capture_output=True, text=True, timeout=timeout
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        return subprocess.CompletedProcess(args, 1, "", str(error))


def is_running():
    result = docker("inspect", "-f", "{{.State.Running}}", CONTAINER, timeout=15)
    return result.stdout.strip() == "true"


def started_at():
    result = docker("inspect", "-f", "{{.State.StartedAt}}", CONTAINER, timeout=15)
    return result.stdout.strip()


def uptime_seconds():
    """Docker reports RFC3339 in UTC with nanoseconds, e.g. 2026-11-11T18:22:42.1234Z."""
    stamp = started_at()
    try:
        started = calendar.timegm(time.strptime(stamp[:19], "%Y-%m-%dT%H:%M:%S"))
    except (ValueError, TypeError):
        return None
    return max(0, int(time.time() - started))


def start_session():
    if is_running():
        return True
    docker("compose", "-f", COMPOSE, "up", "-d", SERVICE, timeout=300)
    if not is_running():
        return False
    # Nobody is connected yet, so start the idle clock now. The session removes this file
    # the moment a client connects, and puts it back when the last one leaves.
    try:
        os.makedirs(os.path.dirname(MARKER), exist_ok=True)
        with open(MARKER, "w", encoding="utf-8"):
            pass
    except OSError:
        pass
    return True


def stop_session():
    if not is_running():
        return True
    docker("stop", CONTAINER, timeout=90)
    return not is_running()


def status():
    running = is_running()
    marker_age = None
    if running and os.path.exists(MARKER):
        marker_age = int(time.time() - os.path.getmtime(MARKER))
    return {
        "running": running,
        "connected": running and marker_age is None,
        "idle_minutes": idle_minutes(),
        "idle_seconds": marker_age,
        "uptime_seconds": uptime_seconds() if running else None,
    }


# --- pages ---------------------------------------------------------------------------

STYLE = """
:root { color-scheme: dark }
* { box-sizing: border-box }
body {
  margin: 0; min-height: 100vh; display: grid; place-items: center;
  background: #1a1917; color: #ece3d4;
  font: 15px/1.55 -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif;
  padding: 32px;
}
main { width: 100%; max-width: 520px }
h1 { font-size: 1.35rem; margin: 0 0 4px; letter-spacing: -0.01em }
p.lede { color: #a49c8d; margin: 0 0 28px }
.card {
  background: #232220; border: 1px solid #37342f; border-radius: 14px;
  padding: 20px; margin-bottom: 14px;
}
.row { display: flex; align-items: center; justify-content: space-between; gap: 16px }
.row + .row { margin-top: 14px; padding-top: 14px; border-top: 1px solid #37342f }
.label { color: #a49c8d; font-size: 13.5px }
.value { font-variant-numeric: tabular-nums }
.dot { display: inline-block; width: 8px; height: 8px; border-radius: 50%; margin-right: 8px }
.on { background: #7ec8d8 } .off { background: #6b6459 }
button, a.btn {
  font: inherit; font-size: 14px; cursor: pointer; text-decoration: none;
  border-radius: 9px; padding: 8px 16px; border: 1px solid #37342f;
  background: #2b2a26; color: #ece3d4;
}
button.primary { background: #7ec8d8; border-color: #7ec8d8; color: #10201f; font-weight: 600 }
button:hover, a.btn:hover { border-color: #7ec8d8 }
input[type=number] {
  font: inherit; width: 76px; padding: 7px 10px; border-radius: 9px;
  border: 1px solid #37342f; background: #1a1917; color: #ece3d4;
}
.actions { display: flex; gap: 10px; flex-wrap: wrap }
code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 13px; color: #a49c8d }
"""


def page(title, body):
    return (
        "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">"
        "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
        f"<title>{title}</title><style>{STYLE}</style></head>"
        f"<body><main>{body}</main></body></html>"
    ).encode("utf-8")


SETTINGS_JS = """
const $ = (id) => document.getElementById(id);
function clock(seconds) {
  if (seconds === null || seconds === undefined) return "unknown";
  const m = Math.floor(seconds / 60), s = seconds % 60;
  return m ? `${m}m ${s}s` : `${s}s`;
}
async function refresh() {
  const state = await (await fetch("/api/status")).json();
  $("state").innerHTML = state.running
    ? '<span class="dot on"></span>running'
    : '<span class="dot off"></span>stopped';
  $("connected").textContent = state.connected ? "yes" : "no";
  $("uptime").textContent = state.running ? clock(state.uptime_seconds) : "not running";
  $("idle").value = state.idle_minutes;
  $("idle-now").textContent = state.idle_seconds === null
    ? "someone is connected"
    : `idle for ${clock(state.idle_seconds)}`;
  $("start").disabled = state.running;
  $("stop").disabled = !state.running;
}
async function post(path, body) {
  await fetch(path, { method: "POST", body: body || "" });
  refresh();
}
$("start").onclick = () => post("/api/start");
$("stop").onclick = () => post("/api/stop");
$("save").onclick = () => post("/api/idle", "minutes=" + $("idle").value);
refresh();
setInterval(refresh, 5000);
"""


def settings_page():
    body = """
<h1>Zonic web session</h1>
<p class="lede">A real Chrome on your server, streamed to this browser. It shuts itself
down when you stop using it.</p>

<div class="card">
  <div class="row"><span class="label">Session</span><span class="value" id="state">…</span></div>
  <div class="row"><span class="label">Someone connected</span><span class="value" id="connected">…</span></div>
  <div class="row"><span class="label">Up for</span><span class="value" id="uptime">…</span></div>
  <div class="row"><span class="label">Idle</span><span class="value" id="idle-now">…</span></div>
</div>

<div class="card">
  <div class="row">
    <span class="label">Shut down after</span>
    <span><input type="number" id="idle" min="1" max="240"> <span class="label">minutes</span></span>
  </div>
  <div class="row actions">
    <button id="save">Save</button>
    <button id="start" class="primary">Start now</button>
    <button id="stop">Stop now</button>
  </div>
</div>

<div class="card">
  <div class="row"><span class="label">Open the session</span><a class="btn" href="/">client</a></div>
</div>

<p class="label">The session is a container. Stopping it does not sign you out: the Chrome
profile lives on disk, so the next start is already logged in.</p>
<script>%s</script>
""" % SETTINGS_JS
    return page("Zonic session", body)


def wake_page(started):
    if started:
        body = """
<h1>Starting the session</h1>
<p class="lede">Chrome is booting in the container. This page reloads itself until it is
ready, usually within fifteen seconds.</p>
<p><code>reloading…</code></p>
<script>setTimeout(() => location.replace("/"), 3000);</script>
"""
    else:
        body = """
<h1>The session did not start</h1>
<p class="lede">Docker refused to bring the container up. Check
<code>docker compose logs session</code> on the server.</p>
<p><a class="btn" href="/settings">Settings</a></p>
"""
    return page("Zonic session", body)


# --- server --------------------------------------------------------------------------


class Handler(BaseHTTPRequestHandler):
    server_version = "zonic-gate"

    def log_message(self, fmt, *args):  # quieter logs, one line per request
        print("%s %s" % (self.address_string(), fmt % args), flush=True)

    def send(self, code, body, content_type="text/html; charset=utf-8"):
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def send_json(self, payload, code=200):
        self.send(code, json.dumps(payload).encode("utf-8"), "application/json")

    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/healthz":
            return self.send(200, b"ok", "text/plain; charset=utf-8")
        if path == "/wake":
            return self.send(200, wake_page(start_session()))
        if path in ("/settings", "/settings/"):
            return self.send(200, settings_page())
        if path == "/api/status":
            return self.send_json(status())
        if path == "/":
            self.send_response(302)
            self.send_header("Location", "/settings")
            self.end_headers()
            return
        return self.send(404, b"not found", "text/plain; charset=utf-8")

    def do_POST(self):
        path = urlparse(self.path).path
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length).decode("utf-8", "replace") if length else ""
        if path == "/api/start":
            return self.send_json({"ok": start_session(), **status()})
        if path == "/api/stop":
            return self.send_json({"ok": stop_session(), **status()})
        if path == "/api/idle":
            try:
                minutes = int(parse_qs(raw).get("minutes", ["10"])[0])
            except ValueError:
                return self.send_json({"ok": False, "error": "minutes must be a number"}, 400)
            write_state("idle_minutes", max(1, min(240, minutes)))
            return self.send_json({"ok": True, **status()})
        return self.send(404, b"not found", "text/plain; charset=utf-8")


def main():
    os.makedirs(STATE_DIR, exist_ok=True)
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print("zonic gate on 127.0.0.1:%d" % PORT, flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
