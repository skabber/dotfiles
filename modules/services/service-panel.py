#!/usr/bin/env python3
"""service-panel: tiny root web UI to start/stop an allowlisted set of systemd
units. Loopback-only HTTP; publish over the tailnet via `tailscale serve`
(TLS + tailnet identity). Optional bearer token when PANEL_TOKEN is set."""
import json
import os
import shutil
import socket
import subprocess
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get("PANEL_PORT", "7980"))
HOST = os.environ.get("PANEL_HOST", "127.0.0.1")
HTML_PATH = os.environ.get("PANEL_HTML")
TOKEN = os.environ.get("PANEL_TOKEN") or None
UNITS = [u for u in os.environ.get("PANEL_UNITS", "").split() if u]

SHOW_PROPS = [
    "Id", "LoadState", "ActiveState", "SubState", "Description",
    "ActiveEnterTimestamp",
]


def run(cmd, timeout=15):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)


def read_int(path):
    try:
        with open(path) as f:
            return int(f.read().strip())
    except OSError:
        return None


def gpu_stats():
    smi = shutil.which("nvidia-smi") or "/run/current-system/sw/bin/nvidia-smi"
    if os.access(smi, os.X_OK):
        r = run([smi,
                 "--query-gpu=name,memory.used,memory.total,utilization.gpu,temperature.gpu",
                 "--format=csv,noheader,nounits"], timeout=10)
        if r.returncode == 0 and r.stdout.strip():
            parts = [p.strip() for p in r.stdout.strip().splitlines()[0].split(",")]
            if len(parts) == 5:
                try:
                    return {
                        "name": parts[0],
                        "memUsedMiB": int(parts[1]),
                        "memTotalMiB": int(parts[2]),
                        "utilPct": int(parts[3]),
                        "tempC": int(parts[4]),
                    }
                except ValueError:
                    pass
    # amdgpu sysfs fallback (same source as gpu-status.nix)
    import glob
    best = None
    for total_path in glob.glob("/sys/class/drm/card*/device/mem_info_vram_total"):
        total = read_int(total_path)
        if total and (best is None or total > best[1]):
            best = (os.path.dirname(total_path), total)
    if best:
        d, total = best
        used = read_int(os.path.join(d, "mem_info_vram_used"))
        if used is not None:
            return {
                "name": "amdgpu",
                "memUsedMiB": used // 1048576,
                "memTotalMiB": total // 1048576,
                "utilPct": None,
                "tempC": None,
            }
    return None


def service_status():
    cmd = ["systemctl", "show", "--no-legend"]
    cmd += [f"--property={p}" for p in SHOW_PROPS]
    cmd += UNITS
    r = run(cmd, timeout=20)
    blocks, block = [], {}
    for line in r.stdout.splitlines():
        if not line.strip():
            if block:
                blocks.append(block)
                block = {}
            continue
        if "=" in line:
            k, v = line.split("=", 1)
            block[k] = v
    if block:
        blocks.append(block)
    out = []
    for unit in UNITS:
        b = next((x for x in blocks if x.get("Id") == unit), {})
        out.append({
            "unit": unit,
            "description": b.get("Description", ""),
            "load": b.get("LoadState", "unknown"),
            "active": b.get("ActiveState", "unknown"),
            "sub": b.get("SubState", ""),
            "since": b.get("ActiveEnterTimestamp", ""),
        })
    return out


class Handler(BaseHTTPRequestHandler):
    server_version = "service-panel/1.0"

    def authorized(self):
        if not TOKEN:
            return True
        if self.headers.get("Authorization", "") == f"Bearer {TOKEN}":
            return True
        q = urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query)
        return q.get("token", [None])[0] == TOKEN

    def send_json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_html(self):
        try:
            with open(HTML_PATH, "rb") as f:
                body = f.read()
        except OSError:
            self.send_json(500, {"error": "panel html missing"})
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if not self.authorized():
            self.send_json(401, {"error": "unauthorized"})
            return
        parts = [urllib.parse.unquote(p) for p in
                 urllib.parse.urlsplit(self.path).path.split("/") if p]
        if parts == []:
            self.send_html()
            return
        if parts == ["api", "status"]:
            self.send_json(200, {
                "hostname": socket.gethostname(),
                "services": service_status(),
                "gpu": gpu_stats(),
            })
            return
        if len(parts) == 3 and parts[0] == "api" and parts[1] == "logs" \
                and parts[2] in UNITS:
            r = run(["journalctl", "-u", parts[2], "-n", "150", "--no-pager",
                     "-o", "short-precise"], timeout=15)
            self.send_json(200, {"lines": r.stdout})
            return
        self.send_json(404, {"error": "not found"})

    def do_POST(self):
        if not self.authorized():
            self.send_json(401, {"error": "unauthorized"})
            return
        parts = [urllib.parse.unquote(p) for p in
                 urllib.parse.urlsplit(self.path).path.split("/") if p]
        if len(parts) == 4 and parts[0] == "api" and parts[1] == "unit" \
                and parts[2] in UNITS and parts[3] in ("start", "stop", "restart"):
            try:
                r = run(["systemctl", parts[3], parts[2]], timeout=240)
            except subprocess.TimeoutExpired:
                self.send_json(504, {"error": f"systemctl {parts[3]} timed out"})
                return
            self.send_json(200 if r.returncode == 0 else 500, {
                "ok": r.returncode == 0,
                "stderr": (r.stderr or r.stdout)[-2000:],
            })
            return
        self.send_json(404, {"error": "not found"})

    def log_message(self, fmt, *args):
        subprocess.run(["systemd-cat", "-t", "service-panel"],
                       input=(fmt % args + "\n").encode(), timeout=5)


if __name__ == "__main__":
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
