#!/usr/bin/env python3
"""Daily nixpkgs reporter.

Fetches the last 24h of commits to NixOS/nixpkgs master, parses out package
updates / new packages / removals / security fixes, asks local Ollama for short
commentary on the notable ones, and writes a styled HTML report to
NIXNEWS_DIR/YYYY-MM-DD.html plus a regenerated index.html.

master (not nixos-unstable) is queried because the channel branch only advances
in bursts every few days, so a rolling 24h window against it is usually empty.
master gets continuous commits daily.

Config (env):
  NIXNEWS_DIR    output directory (required)
  NIXNEWS_BRANCH git ref to query (default master)
  OLLAMA_URL     Ollama API base (default http://127.0.0.1:11434)
  OLLAMA_MODEL   model tag (default hf.co/deepreinforce-ai/Ornith-1.0-9B-GGUF:Q4_K_M)
  GITHUB_TOKEN   optional, raises the 60/hr anon rate limit
"""

import collections
import datetime
import html
import json
import os
import re
import sys
import urllib.error
import urllib.request

NIXPKGS_COMMITS_URL = (
    "https://api.github.com/repos/NixOS/nixpkgs/commits"
    "?sha={branch}&since={since}&per_page=100&page={page}"
)
DEFAULT_BRANCH = "master"
USER_AGENT = "nixnews-reporter"

DEFAULT_OLLAMA_URL = "http://127.0.0.1:11434"
DEFAULT_OLLAMA_MODEL = "hf.co/deepreinforce-ai/Ornith-1.0-9B-GGUF:Q4_K_M"

def log(msg):
    print(msg, flush=True)


def github_request(url, token=None):
    headers = {"User-Agent": USER_AGENT, "Accept": "application/vnd.github+json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(url, headers=headers)
    return urllib.request.urlopen(req, timeout=30)


def fetch_commits(since_iso, branch=DEFAULT_BRANCH, token=None):
    """Paginate the commits endpoint. Stops on empty page or rate-limit/error."""
    all_commits = []
    page = 1
    while True:
        url = NIXPKGS_COMMITS_URL.format(branch=branch, since=since_iso, page=page)
        try:
            with github_request(url, token) as r:
                data = json.loads(r.read())
        except urllib.error.HTTPError as e:
            log(f"  GitHub HTTP {e.code} on page {page}: {e.reason}")
            if e.code in (403, 429):
                log("  rate limited or forbidden; stopping pagination early")
            elif e.code == 422:
                log("  unprocessable request (bad window?); stopping")
            break
        except (urllib.error.URLError, TimeoutError) as e:
            log(f"  network error on page {page}: {e}; stopping")
            break
        if not data:
            break
        all_commits.extend(data)
        log(f"  fetched page {page}: {len(data)} commits (total {len(all_commits)})")
        if len(data) < 100:
            break
        page += 1
    return all_commits


def parse_commits(commits):
    updates = []
    new_pkgs = []
    removals = []
    fixes = []

    for c in commits:
        msg = c["commit"]["message"].split("\n")[0].strip()
        sha = (c.get("sha") or "")[:8]
        author = c.get("commit", {}).get("author", {}).get("name", "unknown")
        entry = {"pkg": None, "old": None, "new": None, "version": None,
                 "sha": sha, "author": author, "msg": msg}

        m = re.match(r"^([\w.+-]+):\s*v?([\w.+-]+)\s*->\s*v?([\w.+-]+)", msg)
        if m:
            updates.append({**entry, "pkg": m.group(1), "old": m.group(2), "new": m.group(3)})
            continue

        m = re.match(r"^([\w.+-]+):\s*(?:init|add)\s+(?:at\s+)?v?([\w.+-]+)", msg, re.IGNORECASE)
        if m:
            new_pkgs.append({**entry, "pkg": m.group(1), "version": m.group(2)})
            continue

        m = re.match(r"^([\w.+-]+):\s*remove", msg, re.IGNORECASE) or \
            re.match(r"^remove\s+([\w.+-]+)", msg, re.IGNORECASE)
        if m:
            removals.append({**entry, "pkg": m.group(1)})
            continue

        m = re.match(r"^([\w.+-]+):\s*(?:update|upgrade)\s+(?:to\s+)?v?([\w.+-]+)", msg, re.IGNORECASE)
        if m:
            updates.append({**entry, "pkg": m.group(1), "new": m.group(2)})
            continue

        m = re.match(r"^([\w.+-]+):\s*(fix|patch|security|CVE.+)", msg, re.IGNORECASE)
        if m:
            fixes.append({**entry, "pkg": m.group(1), "desc": m.group(2)})

    return {"updates": updates, "new_pkgs": new_pkgs, "removals": removals, "fixes": fixes}


# Curated top-level packages whose updates matter to a broad NixOS audience.
# Matched by exact (case-insensitive) top-level name only — NOT against the
# <lang>Packages.<lib> namespace, which would flood the notable set with minor
# dependency bumps. Kept small so a single LLM call can comment on all of them.
NOTABLE_NAMES = {
    # browsers / mail
    "firefox", "firefox-beta", "firefox-esr", "chromium", "google-chrome",
    "brave", "thunderbird",
    # kernel / core system
    "linux", "linux_latest", "linux_zen", "systemd", "mesa", "xorg-server",
    "wayland", "wayland-protocols", "pipewire", "wireplumber",
    # desktops / compositors
    "gnome-shell", "gnome-session", "plasma-desktop", "plasma-workspace",
    "kdeplasma-addons", "xfce", "cosmic-comp", "cosmic-session", "sway",
    "sway-unwrapped", "hyprland",
    # language runtimes / toolchains (top-level only)
    "python3", "python311", "python312", "python313", "ruby", "perl",
    "php", "php81", "php82", "php83", "nodejs", "nodejs_22", "deno", "bun",
    "go", "go_1_22", "go_1_23", "rustc", "cargo", "rust-platform", "zig",
    "nim", "gcc", "gcc13", "gcc14", "clang", "llvm", "gdb",
    # build / containers / nix itself
    "docker", "podman", "buildah", "nix", "nixVersions.stable",
    "nixos-install-tools", "nixfmt-rfc-style",
    # security / networking / editors
    "openssl", "gnutls", "curl", "wget", "git", "openssh", "sudo",
    "vim", "neovim", "emacs", "vscode", "vscodium",
    # core libs / shells
    "glibc", "musl", "busybox", "coreutils", "bash", "zsh", "fish",
}
NOTABLE_MAX = 15


def is_notable(pkg):
    if not pkg:
        return False
    return pkg.lower() in NOTABLE_NAMES


def notable_packages(parsed):
    """Return deduped notable update entries, capped to NOTABLE_MAX, for commentary.

    Security fixes are prioritized, then version bumps, so a short model call
    covers the most important changes. Always sorted by name for stable output.
    """
    seen = {}
    for f in parsed["fixes"]:
        if is_notable(f["pkg"]):
            seen.setdefault(f["pkg"], f)
    for u in parsed["updates"]:
        if is_notable(u["pkg"]):
            seen.setdefault(u["pkg"], u)
    ranked = [seen[k] for k in sorted(seen)]
    return ranked[:NOTABLE_MAX]


def ollama_commentary(notables, base_url, model):
    """Ask Ollama for 1-3 sentences per notable package. Returns {pkg: text} or {}."""
    if not notables:
        return {}
    lines = []
    for u in notables:
        if u.get("old") and u.get("new"):
            lines.append(f"- {u['pkg']}: {u['old']} -> {u['new']}")
        elif u.get("new"):
            lines.append(f"- {u['pkg']}: updated to {u['new']}")
        elif u.get("desc"):
            lines.append(f"- {u['pkg']}: {u['desc']}")
        else:
            lines.append(f"- {u['pkg']}")
    payload = {
        "model": model,
        "stream": False,
        "options": {"temperature": 0.4, "num_predict": 768},
        "messages": [
            {"role": "system", "content": (
                "You summarize package updates in the NixOS nixpkgs repository. "
                "For each listed package, write 1-3 plain-text sentences noting "
                "what the change is and why it matters to NixOS users, using "
                "general software-ecosystem knowledge. Be concise and factual. "
                "Respond as a JSON object mapping each exact package name to its "
                "commentary string. No markdown, no prose outside the JSON.")},
            {"role": "user", "content": "Packages updated today:\n" + "\n".join(lines)},
        ],
    }
    body = json.dumps(payload).encode()
    req = urllib.request.Request(
        base_url.rstrip("/") + "/api/chat",
        data=body,
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            data = json.loads(r.read())
        content = data.get("message", {}).get("content", "").strip()
        if not content:
            return {}
        start, end = content.find("{"), content.rfind("}")
        if start == -1 or end == -1 or end <= start:
            log("  Ollama returned no parseable JSON object; data-only fallback")
            return {}
        obj = json.loads(content[start: end + 1])
        commentary = {str(k): str(v) for k, v in obj.items()}
        log(f"  Ollama commentary: {len(commentary)}/{len(notables)} packages covered")
        return commentary
    except Exception as e:
        log(f"  Ollama commentary failed ({e}); falling back to data-only")
        return {}


def esc(s):
    return html.escape(str(s) if s is not None else "")


def fmt_version(u):
    if u.get("old") and u.get("new"):
        return f"{esc(u['old'])} &rarr; {esc(u['new'])}"
    if u.get("new"):
        return f"&rarr; {esc(u['new'])}"
    return "&mdash;"


CSS = """
body { font: 15px/1.55 -apple-system, system-ui, Segoe UI, Roboto, Helvetica, Arial, sans-serif;
       max-width: 980px; margin: 2rem auto; padding: 0 1rem; color: #1b1b1b; background: #fafafa; }
h1 { font-size: 1.6rem; margin-bottom: .2rem; }
h2 { margin-top: 2rem; border-bottom: 2px solid #7e22ce; padding-bottom: .2rem; color: #5b21b6; }
a { color: #6d28d9; }
blockquote { color: #555; border-left: 3px solid #ccc; margin: .5rem 0; padding: .2rem .8rem; }
.summary { background: #ede9fe; border: 1px solid #c4b5fd; border-radius: 8px;
           padding: .6rem 1rem; margin: 1rem 0; }
table { border-collapse: collapse; width: 100%; margin: 1rem 0; }
th, td { border: 1px solid #ddd; padding: .35rem .5rem; text-align: left; vertical-align: top; }
th { background: #f3f0ff; }
tr:nth-child(even) td { background: #f8f7fc; }
code, .mono { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; font-size: .9em; }
.sha { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; color: #6b7280; }
ul.index { list-style: none; padding: 0; }
ul.index li { padding: .3rem 0; border-bottom: 1px solid #eee; }
.note { background: #fff7ed; border: 1px solid #fdba74; border-radius: 8px; padding: .5rem .8rem; }
"""


def render_report(today, parsed, total_commits, commentary, data_only_note=""):
    n = lambda k: len(parsed[k])
    parts = [
        "<!DOCTYPE html>",
        '<html lang="en"><head><meta charset="utf-8">',
        '<meta name="viewport" content="width=device-width, initial-scale=1">',
        f"<title>nixpkgs unstable updates — {esc(today)}</title>",
        f"<style>{CSS}</style></head><body>",
        f'<h1>nixpkgs unstable updates &mdash; {esc(today)}</h1>',
        '<blockquote>Automatically generated from commits to the '
        '<code>master</code> branch in the past 24 hours.</blockquote>',
        f'<p class="summary"><strong>Summary:</strong> {total_commits} commits '
        f"| {n('updates')} package updates | {n('new_pkgs')} new packages "
        f"| {n('removals')} removals | {n('fixes')} security/fix commits</p>",
    ]
    if data_only_note:
        parts.append(f'<p class="note">{data_only_note}</p>')

    notables = notable_packages(parsed)
    parts.append("<h2>Notable Updates</h2>")
    if not notables:
        parts.append("<p>No notable packages among today's updates.</p>")
    else:
        parts.append("<ul>")
        for u in sorted(notables, key=lambda x: x["pkg"]):
            ver = fmt_version(u)
            comm = commentary.get(u["pkg"])
            parts.append(
                f'<li><strong class="mono">{esc(u["pkg"])}</strong> ({ver}) '
                f'<span class="sha">{esc(u["sha"])}</span>'
                + (f"<br>{esc(comm)}" if comm else "")
                + "</li>"
            )
        parts.append("</ul>")

    parts.append("<h2>All Package Updates</h2>")
    if parsed["updates"]:
        parts.append('<table><thead><tr><th>Package</th><th>Versions</th>'
                     '<th>Commit</th><th>Author</th></tr></thead><tbody>')
        for u in sorted(parsed["updates"], key=lambda x: x["pkg"].lower()):
            parts.append(
                f'<tr><td class="mono">{esc(u["pkg"])}</td><td>{fmt_version(u)}</td>'
                f'<td class="sha">{esc(u["sha"])}</td><td>{esc(u["author"])}</td></tr>'
            )
        parts.append("</tbody></table>")
    else:
        parts.append("<p>None.</p>")

    parts.append("<h2>New Packages</h2>")
    if parsed["new_pkgs"]:
        parts.append('<table><thead><tr><th>Package</th><th>Version</th>'
                     "<th>Commit</th><th>Author</th></tr></thead><tbody>")
        for p in sorted(parsed["new_pkgs"], key=lambda x: x["pkg"].lower()):
            parts.append(
                f'<tr><td class="mono">{esc(p["pkg"])}</td><td class="mono">{esc(p["version"])}</td>'
                f'<td class="sha">{esc(p["sha"])}</td><td>{esc(p["author"])}</td></tr>'
            )
        parts.append("</tbody></table>")
    else:
        parts.append("<p>None.</p>")

    parts.append("<h2>Removed Packages</h2>")
    if parsed["removals"]:
        parts.append('<table><thead><tr><th>Package</th><th>Commit</th>'
                     "<th>Author</th></tr></thead><tbody>")
        for p in sorted(parsed["removals"], key=lambda x: x["pkg"].lower()):
            parts.append(
                f'<tr><td class="mono">{esc(p["pkg"])}</td>'
                f'<td class="sha">{esc(p["sha"])}</td><td>{esc(p["author"])}</td></tr>'
            )
        parts.append("</tbody></table>")
    else:
        parts.append("<p>None.</p>")

    parts.append("<h2>Security Fixes</h2>")
    if parsed["fixes"]:
        parts.append('<table><thead><tr><th>Package</th><th>Description</th>'
                     "<th>Commit</th><th>Author</th></tr></thead><tbody>")
        for f in sorted(parsed["fixes"], key=lambda x: x["pkg"].lower()):
            parts.append(
                f'<tr><td class="mono">{esc(f["pkg"])}</td><td>{esc(f["desc"])}</td>'
                f'<td class="sha">{esc(f["sha"])}</td><td>{esc(f["author"])}</td></tr>'
            )
        parts.append("</tbody></table>")
    else:
        parts.append("<p>None.</p>")

    top = collections.Counter()
    for group in ("updates", "new_pkgs", "removals", "fixes"):
        for e in parsed[group]:
            top[e["author"]] += 1
    top5 = top.most_common(5)

    parts.append("<h2>Statistics</h2><ul>")
    parts.append(f"<li>Total commits analyzed: {total_commits}</li>")
    parts.append(f"<li>Package version bumps: {n('updates')}</li>")
    parts.append(f"<li>New packages added: {n('new_pkgs')}</li>")
    parts.append(f"<li>Packages removed: {n('removals')}</li>")
    parts.append(f"<li>Security/fix commits: {n('fixes')}</li>")
    parts.append("<li>Most active contributors: "
                 + ", ".join(f"{esc(a)} ({c})" for a, c in top5)
                 + "</li>")
    parts.append("</ul>")
    parts.append("</body></html>")
    return "\n".join(parts)


def render_index(entries):
    """entries: list of (date_str, summary_html) sorted desc."""
    parts = [
        "<!DOCTYPE html>",
        '<html lang="en"><head><meta charset="utf-8">',
        '<meta name="viewport" content="width=device-width, initial-scale=1">',
        "<title>nixpkgs unstable — daily reports</title>",
        f"<style>{CSS}</style></head><body>",
        "<h1>nixpkgs unstable &mdash; daily reports</h1>",
        '<blockquote>One report per day, generated from the last 24 hours of '
        "commits to the <code>master</code> branch.</blockquote>",
        '<ul class="index">',
    ]
    for date_str, summary in entries:
        parts.append(
            f'<li><a href="{esc(date_str)}.html">{esc(date_str)}</a> '
            f"&mdash; <span class=\"summary-text\">{summary}</span></li>"
        )
    parts.append("</ul></body></html>")
    return "\n".join(parts)


def extract_summary(html_text):
    """Pull the <p class="summary">…</p> inner text for the index listing."""
    m = re.search(r'<p class="summary">(.*?)</p>', html_text, re.S)
    if not m:
        return "report"
    inner = re.sub(r"<[^>]+>", "", m.group(1))
    return html.escape(inner.strip())


def main():
    data_dir = os.environ.get("NIXNEWS_DIR")
    if not data_dir:
        log("ERROR: NIXNEWS_DIR not set")
        return 2
    os.makedirs(data_dir, exist_ok=True)

    ollama_url = os.environ.get("OLLAMA_URL", DEFAULT_OLLAMA_URL)
    ollama_model = os.environ.get("OLLAMA_MODEL", DEFAULT_OLLAMA_MODEL)
    branch = os.environ.get("NIXNEWS_BRANCH", DEFAULT_BRANCH)
    token = os.environ.get("GITHUB_TOKEN") or None

    now = datetime.datetime.now()
    since = (now - datetime.timedelta(hours=24)).strftime("%Y-%m-%dT%H:%M:%SZ")
    today = now.date().isoformat()

    log(f"nixnews-reporter: fetching {branch} commits since {since}")
    commits = fetch_commits(since, branch, token)
    log(f"total commits fetched: {len(commits)}")
    if not commits:
        log("WARNING: no commits fetched; writing an empty report")

    parsed = parse_commits(commits)
    log(f"parsed: updates={len(parsed['updates'])} new={len(parsed['new_pkgs'])} "
        f"removed={len(parsed['removals'])} fixes={len(parsed['fixes'])}")

    notables = notable_packages(parsed)
    log(f"notable packages selected for commentary: {len(notables)}")
    commentary = ollama_commentary(notables, ollama_url, ollama_model)
    data_only_note = ""
    if notables and not commentary:
        data_only_note = ("LLM commentary unavailable; listing notable packages "
                          "without prose. Check Ollama and re-run.")

    report_html = render_report(today, parsed, len(commits), commentary, data_only_note)
    report_path = os.path.join(data_dir, f"{today}.html")
    with open(report_path, "w") as f:
        f.write(report_html)
    log(f"wrote {report_path}")

    entries = []
    for name in sorted(os.listdir(data_dir), reverse=True):
        if not re.fullmatch(r"\d{4}-\d{2}-\d{2}\.html", name):
            continue
        date_str = name[:-5]
        try:
            with open(os.path.join(data_dir, name)) as f:
                txt = f.read()
        except OSError:
            continue
        entries.append((date_str, extract_summary(txt)))
    with open(os.path.join(data_dir, "index.html"), "w") as f:
        f.write(render_index(entries))
    log(f"regenerated index.html ({len(entries)} reports)")

    log(f"\n=== REPORT READY ===\nfile://{report_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
