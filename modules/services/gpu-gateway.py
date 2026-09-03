#!/usr/bin/env python3
"""gpu-gateway: single-GPU time-share scheduler + buffering reverse proxy.

Two loopback front ports:
  - freetoken front: OpenAI/Anthropic API proxied to the ft server; inference
    requests are held in-process while the engine is down and released once
    healthy, while health probes (/, /health, /v1/models) fail fast and never
    count as demand.
  - moss front: the mtd-subtitle-web jobs API + web UI; mutating requests
    are held while the vLLM engine is down, GETs pass through.

The governor keeps at most one engine resident (moss preferred), waits for
VRAM release between engines, and drains in-flight work before switching:

  MOSS --(ft demand, moss idle, coalesced)--> FREETOKEN
  FREETOKEN --(moss demand, ft drained | drain timeout | ft idle)--> MOSS

Runs as root (systemctl control); loopback-only, published via Tailscale
Serve. All knobs arrive as GW_* env vars from the NixOS module.
"""
import asyncio
import logging
import os
import shutil
import subprocess
import tempfile
import time

import httpx
import uvicorn
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, PlainTextResponse, Response, StreamingResponse
from starlette.background import BackgroundTask
from starlette.requests import ClientDisconnect

log = logging.getLogger("gpu-gateway")
logging.basicConfig(
    level=os.environ.get("GW_LOG_LEVEL", "INFO"),
    format="%(asctime)s %(levelname)s %(message)s",
)
logging.getLogger("httpx").setLevel(logging.WARNING)


def env_float(name, default):
    try:
        return float(os.environ.get(name, "") or default)
    except ValueError:
        return float(default)


FT_FRONT_PORT = int(env_float("GW_FT_FRONT_PORT", 7870))
MOSS_FRONT_PORT = int(env_float("GW_MOSS_FRONT_PORT", 7871))
FT_BACKEND = os.environ.get("GW_FT_BACKEND", "http://127.0.0.1:1919")
MOSS_BACKEND = os.environ.get("GW_MOSS_BACKEND", "http://127.0.0.1:7860")
FT_HEALTH = os.environ.get("GW_FT_HEALTH", FT_BACKEND + "/v1/models")
MOSS_HEALTH = os.environ.get("GW_MOSS_HEALTH", "http://127.0.0.1:8010/v1/models")
FT_UNIT = os.environ.get("GW_FT_UNIT", "freetoken.service")
MOSS_UNIT = os.environ.get("GW_MOSS_UNIT", "moss-transcribe.service")

COALESCE = env_float("GW_COALESCE_SEC", 8)          # batch ft arrivals before switching
FT_IDLE = env_float("GW_FT_IDLE_SEC", 300)          # hysteresis before returning home
DRAIN = env_float("GW_DRAIN_TIMEOUT_SEC", 600)      # max wait for in-flight ft before cutting
FT_STALL = env_float("GW_FT_STALL_SEC", 120)        # cut an in-flight ft stream silent this long once moss waits
FT_STALL_HARD = env_float("GW_FT_STALL_HARD_SEC", 900)  # silent-stream cap: cut even with no moss work waiting
MAX_HOLD = env_float("GW_MAX_HOLD_SEC", 900)        # per-request hold cap
HEALTH_TIMEOUT = env_float("GW_HEALTH_TIMEOUT_SEC", 900)  # engine cold start (JIT/model load)
COOLDOWN = env_float("GW_SWITCH_COOLDOWN_SEC", 60)  # min dwell between switches
POLL = env_float("GW_POLL_SEC", 2)
VRAM_FREE_MIB = env_float("GW_VRAM_FREE_MIB", 2000)
VRAM_TIMEOUT = env_float("GW_VRAM_TIMEOUT_SEC", 90)
SPOOL_THRESHOLD = 8 << 20

UI_HTML_PATH = os.environ.get("GW_UI_HTML")

SYSTEMCTL = shutil.which("systemctl") or "/run/current-system/sw/bin/systemctl"
NVIDIA_SMI = shutil.which("nvidia-smi") or "/run/current-system/sw/bin/nvidia-smi"

client = httpx.AsyncClient(
    timeout=httpx.Timeout(connect=10, read=None, write=600, pool=30),
    follow_redirects=False,
)


class GW:
    state = "starting"  # starting | MOSS | FREETOKEN
    transitioning = False
    ft_healthy = False
    moss_healthy = False
    ft_pending = 0    # arrived, waiting for the engine
    ft_inflight = 0   # forwarded, streaming
    ft_streams = {}   # stream handle -> {start, last_active, upstream, kill}
    moss_held = 0     # mutating requests waiting for the engine
    moss_jobs = 0     # active jobs reported by the jobs API
    ft_demand_since = None
    want_moss_since = None
    ft_idle_since = None
    last_switch = 0.0
    switches = 0
    degraded = None
    moss_unit_state = ""
    ft_unit_state = ""
    gpu = None


gw = GW()

EVENTS = []
EVENTS_MAX = 60


def event(msg):
    EVENTS.append({"t": round(time.time(), 3), "msg": msg})
    del EVENTS[:-EVENTS_MAX]
    log.info("event: %s", msg)


async def sh(args, timeout=120):
    proc = await asyncio.create_subprocess_exec(
        *args, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE
    )
    try:
        out, err = await asyncio.wait_for(proc.communicate(), timeout=timeout)
    except asyncio.TimeoutError:
        proc.kill()
        await proc.communicate()
        return subprocess.CompletedProcess(args, 124, "", "timeout")
    return subprocess.CompletedProcess(args, proc.returncode,
                                      out.decode(errors="replace"),
                                      err.decode(errors="replace"))


async def systemctl(*args, timeout=180):
    return await sh([SYSTEMCTL, *args], timeout=timeout)


async def unit_active(unit):
    r = await systemctl("is-active", "--quiet", unit, timeout=15)
    return r.returncode == 0


async def wait_unit_inactive(unit, timeout):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if await unit_active(unit):
            await asyncio.sleep(1)
        else:
            return True
    return False


async def wait_vram(timeout=None):
    """Wait until the GPU looks free: either no compute processes or total
    usage back under the desktop-idle threshold."""
    if not os.access(NVIDIA_SMI, os.X_OK):
        await asyncio.sleep(3)
        return
    timeout = timeout or VRAM_TIMEOUT
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        used = None
        r = await sh([NVIDIA_SMI, "--query-gpu=memory.used", "--format=csv,noheader,nounits"], timeout=10)
        if r.returncode == 0 and r.stdout.strip():
            try:
                used = int(float(r.stdout.strip().splitlines()[0]))
            except ValueError:
                pass
        if used is not None and used < VRAM_FREE_MIB:
            return
        r = await sh([NVIDIA_SMI, "--query-compute-apps=pid", "--format=csv,noheader"], timeout=10)
        if r.returncode == 0 and not r.stdout.strip():
            return
        await asyncio.sleep(1)
    log.warning("vram release wait timed out after %ss; proceeding anyway", timeout)


async def probe(url):
    """Any HTTP response means the server is listening."""
    try:
        await client.get(url, timeout=3)
        return True
    except httpx.HTTPError:
        return False


async def wait_health(url, timeout):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if await probe(url):
            return True
        await asyncio.sleep(2)
    return False


async def start_engine(unit, health_url):
    r = await systemctl("start", unit)
    if r.returncode != 0:
        log.error("systemctl start %s failed: %s", unit, (r.stderr or "")[-300:])
    return await wait_health(health_url, HEALTH_TIMEOUT)


async def stop_engine(unit):
    r = await systemctl("stop", unit)
    if r.returncode != 0:
        log.warning("systemctl stop %s failed: %s", unit, (r.stderr or "")[-300:])
    await wait_unit_inactive(unit, 150)


async def transition(target):
    if gw.transitioning or gw.state == target:
        return False
    gw.transitioning = True
    origin = gw.state
    log.info("switching %s -> %s", origin, target)
    event(f"switching {origin} -> {target}")
    try:
        await stop_engine(MOSS_UNIT if origin == "MOSS" else FT_UNIT)
        await wait_vram()
        if target == "FREETOKEN":
            ok = await start_engine(FT_UNIT, FT_HEALTH)
        else:
            ok = await start_engine(MOSS_UNIT, MOSS_HEALTH)
        if not ok:
            log.error("%s engine failed health check within %ss; reverting to %s",
                      target, HEALTH_TIMEOUT, origin)
            event(f"{target} failed health check — reverting to {origin}")
            gw.degraded = f"{target} failed to start"
            await stop_engine(target == "FREETOKEN" and FT_UNIT or MOSS_UNIT)
            await wait_vram()
            await start_engine(origin == "FREETOKEN" and FT_UNIT or MOSS_UNIT,
                               FT_HEALTH if origin == "FREETOKEN" else MOSS_HEALTH)
            return False
        gw.state = target
        gw.last_switch = time.monotonic()
        gw.switches += 1
        gw.ft_demand_since = gw.want_moss_since = gw.ft_idle_since = None
        gw.degraded = None
        log.info("now resident: %s", target)
        event(f"now resident: {target}")
        return True
    finally:
        gw.transitioning = False


async def unit_state(unit):
    r = await systemctl("show", unit, "--property=ActiveState", "--property=SubState",
                        "--value", timeout=15)
    if r.returncode != 0:
        return "unknown"
    lines = r.stdout.strip().splitlines()
    if len(lines) < 2:
        return lines[0] if lines else "unknown"
    active, sub = lines[0], lines[1]
    return f"{active} ({sub})" if sub else active


def parse_csv(stdout):
    rows = []
    for line in stdout.strip().splitlines():
        f = [p.strip() for p in line.split(",")]
        if f and f[0]:
            rows.append(f)
    return rows


async def gpu_stats():
    if not os.access(NVIDIA_SMI, os.X_OK):
        return None
    r = await sh([NVIDIA_SMI,
                  "--query-gpu=memory.used,memory.total,utilization.gpu",
                  "--format=csv,noheader,nounits"], timeout=10)
    if r.returncode != 0:
        return None
    rows = parse_csv(r.stdout)
    if not rows:
        return None
    try:
        out = {"memUsedMiB": int(float(rows[0][0])),
               "memTotalMiB": int(float(rows[0][1])),
               "utilPct": int(float(rows[0][2])), "processes": []}
    except (ValueError, IndexError):
        return None
    r = await sh([NVIDIA_SMI,
                  "--query-compute-apps=pid,process_name,used_memory",
                  "--format=csv,noheader,nounits"], timeout=10)
    if r.returncode == 0:
        for f in parse_csv(r.stdout):
            if len(f) >= 3 and f[0].isdigit():
                try:
                    out["processes"].append({"pid": int(f[0]), "name": f[1] or f"pid {f[0]}",
                                             "vramMiB": int(float(f[2]))})
                except ValueError:
                    continue
        out["processes"].sort(key=lambda p: p["vramMiB"], reverse=True)
    return out


async def moss_active_jobs():
    try:
        r = await client.get(MOSS_BACKEND + "/api/jobs", timeout=5)
        jobs = r.json().get("jobs", [])
        return sum(1 for j in jobs
                   if j.get("status") in ("queued", "running", "rendering"))
    except Exception:
        return 0


async def governor():
    # Startup reconcile: adopt whichever engine is already running, else
    # bring up moss (the preferred tenant) for a warm engine at boot.
    if await unit_active(FT_UNIT):
        if await probe(FT_HEALTH):
            gw.state = "FREETOKEN"
        else:
            await stop_engine(FT_UNIT)
            await wait_vram()
            await start_engine(MOSS_UNIT, MOSS_HEALTH)
            gw.state = "MOSS"
    else:
        if not await unit_active(MOSS_UNIT):
            log.info("startup: starting %s", MOSS_UNIT)
            await start_engine(MOSS_UNIT, MOSS_HEALTH)
        gw.state = "MOSS"
    gw.last_switch = time.monotonic()
    log.info("startup reconcile complete: state=%s", gw.state)
    event(f"startup reconcile: state={gw.state}")
    while True:
        try:
            await cycle()
        except Exception:
            log.exception("governor cycle failed")
        await asyncio.sleep(POLL)


async def cycle():
    gw.ft_healthy = await probe(FT_HEALTH)
    gw.moss_healthy = await probe(MOSS_HEALTH)
    gw.moss_jobs = await moss_active_jobs()
    gw.moss_unit_state = await unit_state(MOSS_UNIT)
    gw.ft_unit_state = await unit_state(FT_UNIT)
    gw.gpu = await gpu_stats()
    if gw.transitioning:
        return
    now = time.monotonic()

    if gw.state == "MOSS":
        ft_demand = gw.ft_pending > 0
        moss_busy = gw.moss_jobs > 0 or gw.moss_held > 0
        if ft_demand and not moss_busy:
            gw.ft_demand_since = gw.ft_demand_since or now
            aged = now - gw.ft_demand_since
            if (aged >= COALESCE and now - gw.last_switch >= COOLDOWN
                    and gw.moss_healthy):
                log.info("ft demand coalesced (%.0fs), moss idle: switching", aged)
                event(f"ft demand coalesced ({aged:.0f}s), moss idle — switching")
                await transition("FREETOKEN")
        else:
            gw.ft_demand_since = None

    elif gw.state == "FREETOKEN":
        want_moss = gw.moss_held > 0 or gw.moss_jobs > 0
        if want_moss:
            gw.want_moss_since = gw.want_moss_since or now
            # Cut stalled streams early: an ft response producing no bytes for
            # FT_STALL while moss work waits gets killed instead of pinning the
            # GPU through the whole drain window (hung SSE streams otherwise
            # force every moss request to wait out DRAIN).
            for h in list(gw.ft_streams.values()):
                idle = now - h["last_active"]
                if idle >= FT_STALL and h.get("kill"):
                    event(f"cutting stalled freetoken stream "
                          f"(silent {idle:.0f}s, moss waiting)")
                    h["kill"]()
            # Re-check after the sweep: cutting the stragglers may have just
            # made freetoken idle.
            ft_idle = gw.ft_pending == 0 and gw.ft_inflight == 0
            forced = now - gw.want_moss_since >= DRAIN
            if (ft_idle and now - gw.last_switch >= COOLDOWN) or forced:
                event("returning to MOSS" +
                      (" — drain timeout, cutting in-flight" if not ft_idle else " — ft drained"))
                await transition("MOSS")
        else:
            gw.want_moss_since = None
            # Ghost or hung streams with no moss work waiting would pin
            # freetoken forever (ft_idle can never become true): cut them at
            # FT_STALL_HARD — well past any legitimate silent non-streaming
            # generation — so the idle hysteresis can fire.
            for h in list(gw.ft_streams.values()):
                idle = now - h["last_active"]
                if idle >= FT_STALL_HARD and h.get("kill"):
                    event(f"cutting stalled freetoken stream "
                          f"(silent {idle:.0f}s, hard cap)")
                    h["kill"]()
            ft_idle = gw.ft_pending == 0 and gw.ft_inflight == 0
            if ft_idle:
                gw.ft_idle_since = gw.ft_idle_since or now
                if (now - gw.ft_idle_since >= FT_IDLE
                        and now - gw.last_switch >= COOLDOWN):
                    event(f"freetoken idle for {FT_IDLE:.0f}s — returning to MOSS")
                    await transition("MOSS")
            else:
                gw.ft_idle_since = None


HOP_HEADERS = {
    "connection", "keep-alive", "proxy-authenticate", "proxy-authorization",
    "te", "trailer", "trailers", "transfer-encoding", "upgrade", "host",
}


def fwd_req_headers(request: Request):
    return [(k.decode(), v.decode()) for k, v in request.headers.raw
            if k.decode().lower() not in HOP_HEADERS]


def fwd_resp_headers(headers):
    return {k.decode(): v.decode() for k, v in headers.raw
            if k.decode().lower() not in HOP_HEADERS}


async def read_body(request: Request):
    """Fully read a held request body, spooling to a temp file past the
    threshold (moss audio uploads reach ~200 MB). Returns (content, cleanup)."""
    buf = bytearray()
    f = None
    async for chunk in request.stream():
        if f is not None:
            f.write(chunk)
        else:
            buf += chunk
            if len(buf) > SPOOL_THRESHOLD:
                f = tempfile.TemporaryFile()
                f.write(buf)
                del buf[:]
    if f is None:
        return bytes(buf), None
    f.seek(0)
    held = f

    async def gen():
        try:
            while True:
                chunk = await asyncio.to_thread(held.read, 1 << 20)
                if not chunk:
                    break
                yield chunk
        finally:
            held.close()
    return gen(), lambda: held.close()


async def wait_until(pred, timeout, request=None):
    """Wait for the gate, bailing on client disconnect so held-request
    counters never count dead connections (phantom demand)."""
    deadline = time.monotonic() + timeout
    while not pred():
        if time.monotonic() >= deadline:
            return False
        if request is not None:
            try:
                if await request.is_disconnected():
                    return False
            except Exception:
                pass
        await asyncio.sleep(0.25)
    return True


def hold_timeout():
    return JSONResponse(
        status_code=503,
        content={"error": "gpu-gateway: engine not available within hold window"},
        headers={"Retry-After": "60"},
    )


async def proxy_pass(request: Request, backend: str, *, spool: bool, on_done=None,
                     handle=None):
    """Streaming reverse proxy. When spool is set the body was consumed while
    holding; otherwise the request body streams straight through."""
    url = backend + request.url.path
    if request.url.query:
        url += "?" + request.url.query
    if spool:
        try:
            content, cleanup = await read_body(request)
        except ClientDisconnect:
            return JSONResponse(status_code=499,
                                content={"error": "client disconnected while held"})
    else:
        content, cleanup = request.stream(), None

    req = client.build_request(request.method, url,
                               headers=fwd_req_headers(request), content=content)
    send = asyncio.ensure_future(client.send(req, stream=True))

    def kill():
        # Governor-initiated cut: close the upstream response (stream ends,
        # finally-release runs) or cancel the in-flight send. Idempotent.
        if handle is None or handle.get("killed"):
            return
        handle["killed"] = True
        up = handle.get("upstream")
        if up is not None:
            asyncio.ensure_future(up.aclose())
        else:
            send.cancel()

    if handle is not None:
        handle["kill"] = kill
    try:
        upstream = await send
        if handle is not None:
            handle["upstream"] = upstream
    except asyncio.CancelledError:
        if cleanup:
            cleanup()
        if on_done:
            on_done()
        raise
    except httpx.HTTPError as e:
        if cleanup:
            cleanup()
        if on_done:
            on_done()
        return JSONResponse(status_code=502,
                            content={"error": f"gpu-gateway: upstream unavailable: {e}"})
    except ClientDisconnect:
        if cleanup:
            cleanup()
        if on_done:
            on_done()
        return PlainTextResponse("gpu-gateway: client disconnected",
                                 status_code=499)

    def finish():
        if cleanup:
            cleanup()
        if on_done:
            on_done()

    async def body_stream():
        try:
            async for chunk in upstream.aiter_raw():
                if handle is not None:
                    handle["last_active"] = time.monotonic()
                yield chunk
        finally:
            # Runs on normal end, error, AND kill (upstream closed) — releasing
            # the inflight slot here means a force-cut can never leak a ghost
            # counter (BackgroundTask is skipped when a stream dies mid-flight).
            # ensure_future: no awaits while the generator is being closed.
            asyncio.ensure_future(upstream.aclose())
            if on_done:
                on_done()

    return StreamingResponse(body_stream(), status_code=upstream.status_code,
                             headers=fwd_resp_headers(upstream.headers),
                             background=BackgroundTask(finish))


def status_payload():
    now = time.monotonic()
    streams = list(gw.ft_streams.values())
    oldest_idle = max((now - h["last_active"] for h in streams), default=None)
    return {
        "state": gw.state,
        "transitioning": gw.transitioning,
        "degraded": gw.degraded,
        "switches": gw.switches,
        "ft": {"pending": gw.ft_pending, "inflight": gw.ft_inflight,
               "oldestIdleSec": round(oldest_idle, 1) if oldest_idle is not None else None,
               "stalledInflight": sum(1 for h in streams
                                       if now - h["last_active"] >= FT_STALL),
               "healthy": gw.ft_healthy, "unit": FT_UNIT,
               "unitState": gw.ft_unit_state},
        "moss": {"held": gw.moss_held, "jobs": gw.moss_jobs,
                 "healthy": gw.moss_healthy, "unit": MOSS_UNIT,
                 "unitState": gw.moss_unit_state},
        "gpu": gw.gpu,
        "events": EVENTS[-30:],
        "policy": {"coalesceSec": COALESCE, "ftIdleSec": FT_IDLE,
                   "drainTimeoutSec": DRAIN, "maxHoldSec": MAX_HOLD,
                   "ftStallSec": FT_STALL, "ftStallHardSec": FT_STALL_HARD,
                   "switchCooldownSec": COOLDOWN},
    }


app_ft = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)
app_moss = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)


@app_ft.get("/__gw")
@app_ft.get("/__gw/")
@app_moss.get("/__gw")
@app_moss.get("/__gw/")
async def ui():
    if not UI_HTML_PATH:
        return PlainTextResponse("gpu-gateway: UI not configured", status_code=503)
    try:
        with open(UI_HTML_PATH, "rb") as f:
            return Response(content=f.read(), media_type="text/html")
    except OSError:
        return PlainTextResponse("gpu-gateway: UI html missing", status_code=503)


@app_ft.get("/__gw/status")
@app_moss.get("/__gw/status")
async def status():
    return status_payload()


@app_ft.api_route("/{path:path}",
                  methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD"])
async def ft_proxy(request: Request, path: str):
    if (request.method not in MUTATING
            and request.url.path.rstrip("/") in NON_DEMAND):
        if not (gw.state == "FREETOKEN" and gw.ft_healthy):
            return JSONResponse(
                status_code=503,
                content={"error": "gpu-gateway: engine down; non-inference requests are not held"},
                headers={"Retry-After": "60"},
            )
        return await proxy_pass(request, FT_BACKEND, spool=False)
    gw.ft_pending += 1
    spool = False
    try:
        gate = lambda: gw.state == "FREETOKEN" and gw.ft_healthy
        spool = not gate()
        if spool:
            ok = await wait_until(gate, MAX_HOLD, request)
            if not ok:
                return hold_timeout()
    finally:
        gw.ft_pending -= 1
    gw.ft_inflight += 1
    h = {"start": time.monotonic(), "last_active": time.monotonic(),
         "upstream": None, "kill": None}
    gw.ft_streams[id(h)] = h
    released = False

    def release():
        nonlocal released
        if not released:
            released = True
            gw.ft_inflight -= 1
            gw.ft_streams.pop(id(h), None)

    h["release"] = release
    try:
        return await proxy_pass(request, FT_BACKEND, spool=spool, on_done=release,
                                handle=h)
    except BaseException:
        # CancelledError (client disconnect mid-send, governor kill) is a
        # BaseException and must release the inflight slot too, or ft_idle
        # never returns true.
        release()
        raise


MUTATING = {"POST", "PUT", "PATCH", "DELETE"}

# Probes that must never register as ft demand: a once-a-minute GET / or
# /v1/models health poll would otherwise boot the engine and pin the model
# in VRAM all day. They fail fast while the engine is down instead of being
# held, and pass through untracked (no inflight slot) when it is up.
NON_DEMAND = {"", "health", "v1/models"}


@app_moss.api_route("/{path:path}",
                    methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD"])
async def moss_proxy(request: Request, path: str):
    spool = False
    if request.method in MUTATING:
        gw.moss_held += 1
        try:
            gate = lambda: gw.state == "MOSS" and gw.moss_healthy
            spool = not gate()
            if spool:
                ok = await wait_until(gate, MAX_HOLD, request)
                if not ok:
                    return hold_timeout()
        finally:
            gw.moss_held -= 1
    return await proxy_pass(request, MOSS_BACKEND, spool=spool)


async def main():
    servers = [
        uvicorn.Server(uvicorn.Config(app_ft, host="127.0.0.1", port=FT_FRONT_PORT,
                                      log_level="warning", access_log=False, lifespan="off")),
        uvicorn.Server(uvicorn.Config(app_moss, host="127.0.0.1", port=MOSS_FRONT_PORT,
                                      log_level="warning", access_log=False, lifespan="off")),
    ]
    tasks = [asyncio.create_task(s.serve(), name=f"uvicorn:{s.config.port}")
             for s in servers]
    gov = asyncio.create_task(governor(), name="governor")
    done, _ = await asyncio.wait(tasks + [gov], return_when=asyncio.FIRST_COMPLETED)
    for s in servers:
        s.should_exit = True
    gov.cancel()
    await asyncio.gather(*tasks, return_exceptions=True)
    for t in done:
        if t.exception() is not None:
            raise t.exception()


if __name__ == "__main__":
    asyncio.run(main())
