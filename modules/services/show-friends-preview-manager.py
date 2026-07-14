#!/usr/bin/env python3
"""show-friends PR preview manager.

A tiny HTTP daemon (loopback only) that owns the lifecycle of per-PR preview
deploys on this host. Gitea Actions workflows call /start and /stop with a
shared bearer token; the manager checks out the PR ref, starts a templated
systemd unit (which builds + serves via nix develop), waits for health, then
posts a comment to the PR with the Tailscale-HTTPS preview URL.
"""
import json
import os
import secrets
import subprocess
import sys
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DATA_ROOT = os.environ.get("DATA_ROOT", "/srv/show-friends")
PREVIEW_ROOT = os.path.join(DATA_ROOT, "previews")

GITEA_URL = os.environ.get("GITEA_URL", "http://127.0.0.1:3000")
GITEA_REPO = os.environ["GITEA_REPO"]
COMMENT_TOKEN = os.environ["COMMENT_TOKEN"]
AUTH_TOKEN = os.environ["PREVIEW_TOKEN"]
DOMAIN = os.environ.get("DOMAIN", "nixos.tail69fe1.ts.net")
MAX_PREVIEWS = int(os.environ.get("MAX_PREVIEWS", "5"))
HEALTH_TIMEOUT = int(os.environ.get("HEALTH_TIMEOUT", "900"))


def sh(*cmd):
    return subprocess.run(cmd, capture_output=True, text=True)


def ports_for(pr):
    base = pr % 1000
    return {"FPORT": 18000 + base, "WPORT": 20000 + base, "SQPORT": 19000 + base}


def active_count():
    r = sh("systemctl", "list-units", "show-friends-preview@*.service",
           "--no-legend", "--plain", "--state=active")
    return len([ln for ln in r.stdout.splitlines() if ln.strip()])


def write_env(pr, ref, backup=None):
    p = ports_for(pr)
    d = os.path.join(PREVIEW_ROOT, str(pr))
    os.makedirs(d, exist_ok=True)
    env = {
        "PR": str(pr),
        "REF": ref,
        "DOMAIN": DOMAIN,
        "DATA_DIR": d,
        "SRC_DIR": os.path.join(d, "src"),
        "DB_FILE": os.path.join(d, "db.sqlite"),
        "SESSION_SECRET": secrets.token_urlsafe(32),
        **p,
    }
    # R2 backup-seed credentials for sf-preview-serve.sh. The R2 read token is
    # the only secret; account id + worker url are project constants sent by
    # the workflow. All optional: when absent, the serve script falls back to
    # an empty DB.
    if backup:
        for src, dst in (("r2_token", "CLOUDFLARE_API_TOKEN"),
                         ("cf_account_id", "CLOUDFLARE_ACCOUNT_ID"),
                         ("backup_worker_url", "BACKUP_WORKER_URL")):
            val = backup.get(src)
            if val:
                env[dst] = str(val)
    with open(os.path.join(d, "preview.env"), "w") as f:
        for k, v in env.items():
            f.write(f"{k}={v}\n")
    sh("chown", "-R", "jay:", d)
    return p


def post_comment(pr, body):
    url = f"{GITEA_URL}/api/v1/repos/{GITEA_REPO}/issues/{pr}/comments"
    data = json.dumps({"body": body}).encode()
    req = urllib.request.Request(
        url, data=data, method="POST",
        headers={"Authorization": f"token {COMMENT_TOKEN}",
                 "Content-Type": "application/json"})
    try:
        urllib.request.urlopen(req, timeout=10)
    except Exception as exc:
        sys.stderr.write(f"comment post failed: {exc}\n")


def wait_healthy(fport):
    url = f"http://127.0.0.1:{fport}/"
    deadline = time.time() + HEALTH_TIMEOUT
    while time.time() < deadline:
        r = sh("curl", "-fsS", "-o", "/dev/null", "-m", "3", url)
        if r.returncode == 0:
            return True
        time.sleep(5)
    return False


class Handler(BaseHTTPRequestHandler):
    def _auth(self):
        return self.headers.get("Authorization", "") == f"Bearer {AUTH_TOKEN}"

    def _send(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        self._send(200, {"ok": True}) if self.path == "/health" else self._send(404, {"error": "not found"})

    def do_POST(self):
        if not self._auth():
            self._send(401, {"error": "unauthorized"})
            return
        try:
            length = int(self.headers.get("Content-Length", 0))
            payload = json.loads(self.rfile.read(length) or "{}")
        except Exception:
            self._send(400, {"error": "bad json"})
            return
        if self.path == "/start":
            self._start(payload)
        elif self.path == "/stop":
            self._stop(payload)
        else:
            self._send(404, {"error": "not found"})

    def _start(self, payload):
        try:
            pr = int(payload["pr"])
            ref = str(payload["ref"])
        except (KeyError, ValueError, TypeError):
            self._send(400, {"error": "pr (int) and ref (str) required"})
            return
        if active_count() >= MAX_PREVIEWS:
            self._send(409, {"error": f"max {MAX_PREVIEWS} previews reached; close one first"})
            return
        backup = {
            "r2_token": payload.get("r2_token"),
            "cf_account_id": payload.get("cf_account_id"),
            "backup_worker_url": payload.get("backup_worker_url"),
        }
        p = write_env(pr, ref, backup)
        r = sh("systemctl", "restart", f"show-friends-preview@{pr}.service")
        if r.returncode != 0:
            self._send(500, {"error": "start failed", "stderr": r.stderr, "stdout": r.stdout})
            return
        url = f"https://{DOMAIN}:{p['FPORT']}"
        healthy = wait_healthy(p["FPORT"])
        if healthy:
            post_comment(pr, f"**Preview ready:** {url}\n\nPer-PR libSQL DB seeded from the latest prod backup (empty DB fallback if the backup download fails). Logs: `journalctl -u show-friends-preview@{pr} -f`.")
            self._send(200, {"ok": True, "url": url})
        else:
            post_comment(pr, f"**Preview started but health check timed out.** Check `journalctl -u show-friends-preview@{pr}`. Intended URL: {url}")
            self._send(202, {"ok": False, "url": url, "warning": "health check timed out"})

    def _stop(self, payload):
        try:
            pr = int(payload["pr"])
        except (KeyError, ValueError, TypeError):
            self._send(400, {"error": "pr (int) required"})
            return
        sh("systemctl", "stop", f"show-friends-preview@{pr}.service")
        self._send(200, {"ok": True})

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    os.makedirs(PREVIEW_ROOT, exist_ok=True)
    srv = ThreadingHTTPServer(("127.0.0.1", int(os.environ["PORT"])), Handler)
    sys.stderr.write(f"show-friends preview manager on 127.0.0.1:{os.environ['PORT']}\n")
    srv.serve_forever()
