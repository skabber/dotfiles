#!/usr/bin/env python3
"""pi-chat: web UI that bridges a chat interface to the pi coding agent CLI,
with a file browser and git diff viewer for the dotfiles repo. Runs
unprivileged as the repo owner (the pi agent needs the owner's ~/.pi auth
and edits the repo); loopback-only HTTP published tailnet-only via Tailscale
Serve (TLS + tailnet identity). Optional bearer token when PI_CHAT_TOKEN is
set.

Agent runs are decoupled from the HTTP connection: POST /api/chat starts a
pi process in a background thread and buffers its event stream server-side;
clients follow along via GET /api/run long-polling. Reloading or closing the
page (or a tailnet blip) never kills a run — the next page load re-attaches
to the live run and replays the buffer."""
import json
import os
import re
import signal
import socket
import subprocess
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get("PI_CHAT_PORT", "7981"))
HOST = os.environ.get("PI_CHAT_HOST", "127.0.0.1")
HTML_PATH = os.environ.get("PI_CHAT_HTML")
REPO = os.path.abspath(os.environ.get("PI_CHAT_REPO", os.getcwd()))
PI_BIN = os.environ.get("PI_CHAT_PI", "pi")
TOKEN = os.environ.get("PI_CHAT_TOKEN") or None
MAX_FILE = 1 << 20  # 1 MiB viewer cap
MAX_CHAT_LEN = 32000
MAX_RUNNING = 4
MAX_EVENTS = 30000  # per-run event buffer cap (oldest dropped)
FINISHED_RUNS_KEPT = 8
LONG_POLL_S = 25

SESSION_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]{5,63}$")
SESSION_DIR = os.path.join(os.path.expanduser("~"), ".pi", "agent",
                           "sessions", "--" + REPO.strip("/").replace("/", "-") + "--")


class Run:
    """One pi process + its buffered NDJSON event stream."""

    def __init__(self, message, model):
        self.message = message
        self.model = model
        self.started = time.time()
        self.lock = threading.Lock()
        self.cond = threading.Condition(self.lock)
        self.events = []       # buffered event lines (str)
        self.base = 0          # events dropped from the front (cursor stays monotonic)
        self.proc = None
        self.running = True
        self.exit = None

    def cursor(self):
        with self.lock:
            return self.base + len(self.events)

    def append(self, obj):
        line = obj if isinstance(obj, str) else json.dumps(obj)
        with self.cond:
            self.events.append(line.rstrip("\n"))
            if len(self.events) > MAX_EVENTS:
                drop = len(self.events) - MAX_EVENTS
                del self.events[:drop]
                self.base += drop
            self.cond.notify_all()

    def snapshot(self, since, wait_s):
        """Events after cursor `since`; long-polls up to wait_s for new ones."""
        deadline = time.monotonic() + wait_s
        with self.cond:
            while self.base + len(self.events) <= since and self.running:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    break
                self.cond.wait(remaining)
            start = max(0, since - self.base)
            return {"events": self.events[start:],
                    "cursor": self.base + len(self.events),
                    "dropped": max(0, self.base - since),
                    "running": self.running,
                    "exitCode": self.exit,
                    "started": self.started}

    def stop(self):
        with self.lock:
            proc = self.proc
        if not proc:
            return
        try:
            os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
        except (ProcessLookupError, PermissionError, OSError):
            return
        def hard_kill():
            time.sleep(8)
            try:
                os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
            except (ProcessLookupError, PermissionError, OSError):
                pass
        threading.Thread(target=hard_kill, daemon=True).start()


_runs = {}  # session id -> Run
_lock = threading.Lock()
_models_cache = (0, None)
_pi_version = None


def run(cmd, timeout=20, cwd=REPO):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, cwd=cwd)


def git(args, timeout=20):
    return run(["git"] + args, timeout)


def out(r):
    return r.stdout if r.returncode == 0 else ""


def safe_rel(rel):
    """Resolve rel against REPO, refusing escapes (symlinks included)."""
    root = os.path.realpath(REPO)
    full = os.path.realpath(os.path.join(root, rel))
    if full != root and not full.startswith(root + os.sep):
        return None
    return os.path.relpath(full, root)


def repo_status():
    branch = out(git(["rev-parse", "--abbrev-ref", "HEAD"])).strip() or "-"
    head = out(git(["rev-parse", "--short", "HEAD"])).strip() or "-"
    st = git_status_map()
    dirty = len(st)
    return {"branch": branch, "head": head, "dirty": dirty,
            "hostname": socket.gethostname(),
            "repo": os.path.basename(REPO)}


def pi_version():
    global _pi_version
    if _pi_version is None:
        try:
            r = run([PI_BIN, "--version"], timeout=15, cwd=REPO)
            _pi_version = r.stdout.strip() or "?"
        except Exception:
            _pi_version = "?"
    return _pi_version


def git_status_map():
    """relpath -> 'XY' status codes from git status --porcelain -z -uall."""
    r = git(["status", "--porcelain=v1", "-z", "-uall"])
    m = {}
    parts = r.stdout.split("\0")
    i = 0
    while i < len(parts):
        e = parts[i]
        i += 1
        if not e:
            continue
        if len(e) < 4 or e[2] != " ":
            continue
        xy, path = e[:2], e[3:]
        m[path] = xy
        if xy[0] in "RC" and i < len(parts):  # rename: next part is the origin
            i += 1
    return m


def tree():
    files = [f for f in out(git(["ls-files", "-z"])).split("\0") if f]
    st = git_status_map()
    seen = set(files)
    files += sorted(p for p in st if p not in seen)
    outl = []
    for p in files:
        rel = safe_rel(p)
        if rel is None:
            continue
        try:
            size = os.lstat(os.path.join(REPO, rel)).st_size
        except OSError:
            size = None
        outl.append({"path": rel, "status": st.get(p, ""), "size": size})
    return outl


def read_file(rel):
    full = os.path.join(REPO, rel)
    if not os.path.isfile(full):
        return None, "not a file"
    if os.lstat(full).st_size > MAX_FILE:
        return None, f"file larger than {MAX_FILE // 1024} KiB"
    with open(full, "rb") as f:
        data = f.read()
    if b"\0" in data:
        return None, "binary file"
    return {"path": rel,
            "content": data.decode("utf-8", errors="replace"),
            "size": len(data)}, None


def untracked_files():
    return [p for p, xy in git_status_map().items() if xy == "??"]


def diff(rel=None):
    """Unified diff vs HEAD (staged+unstaged); untracked files diffed from
    /dev/null so new files show as all-added."""
    chunks = []
    if rel is not None:
        args = (["diff", "--no-index", "--", "/dev/null", rel]
                if rel in untracked_files()
                else ["diff", "HEAD", "--", rel])
        r = run(["git"] + args, timeout=30)
        chunks.append(r.stdout if r.stdout.strip() else "")
    else:
        chunks.append(out(git(["diff", "HEAD"], timeout=30)))
        for p in untracked_files():
            r = run(["git", "diff", "--no-index", "--", "/dev/null", p], timeout=30)
            if r.stdout.strip():
                chunks.append(r.stdout)
    return "\n".join(c for c in chunks if c)


def history(session):
    """Reconstruct a conversation from a pi session JSONL (message events)."""
    if not SESSION_RE.match(session):
        return None
    try:
        names = [n for n in os.listdir(SESSION_DIR) if n.endswith("_" + session + ".jsonl")]
    except OSError:
        return []
    if not names:
        return []
    path = os.path.join(SESSION_DIR, sorted(names)[-1])
    msgs = []
    with open(path) as f:
        for line in f:
            try:
                d = json.loads(line)
            except ValueError:
                continue
            if d.get("type") != "message":
                continue
            m = d.get("message", {})
            role = m.get("role")
            if role not in ("user", "assistant", "toolResult"):
                continue
            if role == "user":
                text = " ".join(c.get("text", "") for c in m.get("content", [])
                                if c.get("type") == "text").strip()
                if text:
                    msgs.append({"role": "user", "text": text,
                                 "ts": d.get("timestamp")})
            elif role == "assistant":
                for c in m.get("content", []):
                    if c.get("type") == "text" and c.get("text", "").strip():
                        msgs.append({"role": "assistant", "text": c["text"],
                                     "ts": d.get("timestamp")})
                    elif c.get("type") == "toolCall":
                        msgs.append({"role": "tool", "toolCallId": c.get("id"),
                                     "name": c.get("name"),
                                     "args": c.get("arguments", {}),
                                     "ts": d.get("timestamp")})
            elif role == "toolResult":
                content = " ".join(c.get("text", "") for c in m.get("content", [])
                                   if c.get("type") == "text")
                msgs.append({"role": "toolResult", "toolCallId": m.get("toolCallId"),
                             "name": m.get("toolName"), "output": content,
                             "isError": bool(m.get("isError")),
                             "ts": d.get("timestamp")})
    return msgs


def list_models():
    global _models_cache
    now, cached = _models_cache
    if cached is not None and time.time() - now < 600:
        return cached
    try:
        r = run([PI_BIN, "--list-models"], timeout=25, cwd=REPO)
        models = []
        for line in r.stdout.splitlines()[1:]:
            f = line.split()
            if len(f) >= 2:
                models.append({"provider": f[0], "model": f[1],
                               "context": f[2] if len(f) > 2 else "",
                               "thinking": f[4] if len(f) > 4 else ""})
        _models_cache = (time.time(), models)
        return models
    except Exception:
        return []


def spawn(session, message, model):
    args = [PI_BIN, "--print", "--mode", "json", "--session-id", session]
    if model:
        args += ["--model", model]
    args += ["--", message]
    return subprocess.Popen(
        args, cwd=REPO,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        start_new_session=True, text=True, bufsize=1)


def _run_worker(session, run_obj):
    """Execute pi, buffering its event stream; survives client disconnects."""
    try:
        proc = spawn(session, run_obj.message, run_obj.model)
    except OSError as e:
        run_obj.append({"type": "web_error", "error": f"failed to start pi: {e}"})
        with run_obj.cond:
            run_obj.running = False
            run_obj.exit = -1
            run_obj.cond.notify_all()
        return
    with run_obj.cond:
        run_obj.proc = proc

    def stderr_pump():
        try:
            for line in proc.stderr:
                run_obj.append({"type": "web_stderr", "line": line.rstrip("\n")})
        except (ValueError, OSError):
            pass

    threading.Thread(target=stderr_pump, daemon=True).start()
    try:
        for line in proc.stdout:
            run_obj.append(line)
    except (ValueError, OSError):
        pass
    proc.wait()
    # NB: append takes the cond itself; the lock is a plain Lock (not RLock),
    # so calling it inside `with run_obj.cond` would self-deadlock.
    run_obj.append({"type": "web_done", "exitCode": proc.returncode})
    with run_obj.cond:
        run_obj.running = False
        run_obj.exit = proc.returncode
        run_obj.cond.notify_all()


def start_run(session, message, model):
    """Register + launch a run. Returns None on success, else an error string."""
    with _lock:
        current = _runs.get(session)
        if current and current.running:
            return "a run is already active"
        live = sum(1 for r in _runs.values() if r.running)
        if live >= MAX_RUNNING:
            return "too many concurrent runs"
        run_obj = Run(message, model)
        _runs[session] = run_obj
        # trim finished runs (keep the newest few for reconnect replay)
        finished = sorted((s for s, r in _runs.items() if not r.running),
                          key=lambda s: _runs[s].started)
        for s in finished[:-FINISHED_RUNS_KEPT + 1]:
            _runs.pop(s, None)
    threading.Thread(target=_run_worker, args=(session, run_obj), daemon=True).start()
    return None


class Handler(BaseHTTPRequestHandler):
    server_version = "pi-chat/1.0"
    protocol_version = "HTTP/1.1"

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

    def body_json(self):
        n = int(self.headers.get("Content-Length", 0))
        try:
            return json.loads(self.rfile.read(n))
        except ValueError:
            return None

    def do_GET(self):
        u = urllib.parse.urlsplit(self.path)
        parts = [urllib.parse.unquote(p) for p in u.path.split("/") if p]
        if parts == []:
            # static shell with no secrets; the API below requires the token
            # and the page shows its own unlock form on 401
            self.send_html()
            return
        if not self.authorized():
            self.send_json(401, {"error": "unauthorized"})
            return
        q = urllib.parse.parse_qs(u.query)
        if parts[:2] == ["api", "status"]:
            st = repo_status()
            st["pi"] = pi_version()
            self.send_json(200, st)
            return
        if parts[:2] == ["api", "tree"]:
            self.send_json(200, {"files": tree()})
            return
        if parts[:2] == ["api", "models"]:
            self.send_json(200, {"models": list_models()})
            return
        if parts[:2] == ["api", "run"]:
            session = q.get("session", [""])[0]
            since = int(q.get("since", ["0"])[0] or 0)
            wait = float(q.get("wait", [str(LONG_POLL_S)])[0] or 0)
            with _lock:
                run_obj = _runs.get(session)
            if not run_obj:
                self.send_json(404, {"error": "no run for session"})
                return
            self.send_json(200, run_obj.snapshot(since, max(0, min(wait, LONG_POLL_S))))
            return
        if parts[:2] == ["api", "file"]:
            rel = safe_rel(q.get("p", [""])[0])
            if rel is None:
                self.send_json(400, {"error": "path escapes repo"})
                return
            content, err = read_file(rel)
            if err:
                self.send_json(404, {"error": err})
                return
            self.send_json(200, content)
            return
        if parts[:2] == ["api", "diff"]:
            rel = safe_rel(q.get("p", [""])[0]) if "p" in q else None
            if "p" in q and rel is None:
                self.send_json(400, {"error": "path escapes repo"})
                return
            self.send_json(200, {"diff": diff(rel)})
            return
        if parts[:2] == ["api", "log"]:
            r = git(["log", "-12", "--pretty=format:%h%x1f%ad%x1f%s", "--date=short"])
            commits = [{"hash": h, "date": d, "subject": s} for h, d, s in
                       (l.split("\x1f", 2) for l in r.stdout.splitlines() if "\x1f" in l)]
            self.send_json(200, {"commits": commits})
            return
        if parts[:2] == ["api", "history"]:
            msgs = history(q.get("session", [""])[0])
            if msgs is None:
                self.send_json(400, {"error": "bad session id"})
                return
            self.send_json(200, {"messages": msgs})
            return
        self.send_json(404, {"error": "not found"})

    def do_POST(self):
        if not self.authorized():
            self.send_json(401, {"error": "unauthorized"})
            return
        parts = [urllib.parse.unquote(p) for p in
                 urllib.parse.urlsplit(self.path).path.split("/") if p]
        if parts[:2] == ["api", "stop"]:
            body = self.body_json() or {}
            session = body.get("session", "")
            with _lock:
                run_obj = _runs.get(session)
            if not run_obj or not run_obj.running:
                self.send_json(404, {"error": "no active run for session"})
                return
            run_obj.stop()
            self.send_json(200, {"ok": True})
            return
        if parts[:2] == ["api", "chat"]:
            body = self.body_json()
            if not isinstance(body, dict):
                self.send_json(400, {"error": "bad json"})
                return
            session = body.get("session", "")
            message = body.get("message", "")
            model = body.get("model") or None
            if not SESSION_RE.match(session):
                self.send_json(400, {"error": "bad session id"})
                return
            if not isinstance(message, str) or not message.strip() \
                    or len(message) > MAX_CHAT_LEN:
                self.send_json(400, {"error": "bad message"})
                return
            err = start_run(session, message.strip(), model)
            if err:
                self.send_json(409 if "active" in err else 429, {"error": err})
                return
            # the run continues server-side; the client follows /api/run
            self.send_json(200, {"ok": True})
            return
        self.send_json(404, {"error": "not found"})

    def log_message(self, fmt, *args):
        subprocess.run(["systemd-cat", "-t", "pi-chat"],
                       input=(fmt % args + "\n").encode(), timeout=5)


if __name__ == "__main__":
    ThreadingHTTPServer.daemon_threads = True
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
