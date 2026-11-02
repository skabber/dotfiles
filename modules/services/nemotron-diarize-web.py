#!/usr/bin/env python3
"""nemotron-diarize-web: jobs API + web UI for NVIDIA Nemotron 3 Diarization
(+ optional Nemotron 3.5 ASR speaker-attributed transcription).

Mirrors the MOSS-Transcribe-Diarize jobs API (upload -> poll -> segments).
Diarization-only jobs carry speaker turns (start/end/speaker, up to 8
speakers); when an ASR model is configured (NVIDIA's documented pairing:
nemotron-3.5-asr-streaming-0.6b with masked_asr=true), jobs default to full
speaker-attributed transcription via NeMo's SpeakerTaggedASR streaming
replay, and segments carry text with SRT export.

Runs inside the nemo venv; models lazy-load on the first job and unload
in-process after idleUnloadMinutes to hand VRAM back. Verified on the RTX
3080 next to the resident moss vLLM engine: diarize-only ~0.7 GB, combined
~1.6 GB. TORCHDYNAMO_DISABLE=1 keeps flex_attention eager (the compiled
kernel fails against torch 2.14 + cu132); eager measures RTFx ~60 diarize,
~5.5 combined.
"""

import argparse
import json
import logging
import queue
import shutil
import subprocess
import threading
import time
import uuid
from pathlib import Path

from typing import Optional
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse
from pydantic import BaseModel

log = logging.getLogger("nemotron-diarize")
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

ACTIVE = ("queued", "decoding", "loading_model", "diarizing", "transcribing",
          "postprocessing")
DONE = ("done", "failed")


class Args:
    pass


ARGS = Args()
JOBS = {}          # id -> job dict (also persisted to runs/<id>/job.json)
JOBS_LOCK = threading.Lock()
QUEUE = queue.Queue()
MODEL_LAST_USED = 0.0


def now():
    return time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime()) + "Z"


def job_dir(job_id):
    return Path(ARGS.runs_dir) / job_id


def persist(job):
    d = job_dir(job["id"])
    d.mkdir(parents=True, exist_ok=True)
    (d / "job.json").write_text(json.dumps(job, indent=2))


def public(job):
    return {k: job.get(k) for k in (
        "id", "status", "media_name", "progress", "created_at", "updated_at",
        "audio_sec", "speakers", "num_segments", "transcribe", "error")}


def set_status(job, status, progress=None, **extra):
    job["status"] = status
    job["updated_at"] = now()
    if progress is not None:
        job["progress"] = progress
    job.update(extra)
    persist(job)
    log.info("job %s -> %s", job["id"], status)


def err(code, status_code, detail):
    return HTTPException(status_code=status_code,
                         detail={"code": code, "detail": detail})


def get_job(job_id):
    with JOBS_LOCK:
        job = JOBS.get(job_id)
    if not job:
        raise err("job_not_found", 404, f"no job {job_id}")
    return job


# --- inference ---------------------------------------------------------------

_model = None
_model_lock = threading.Lock()


def load_model():
    """Lazy-load SortformerEncLabelModel; logs the marker line the idle
    unload watches for."""
    global _model
    with _model_lock:
        if _model is not None:
            return _model
        import torch
        from nemo.collections.asr.models import SortformerEncLabelModel
        m = SortformerEncLabelModel.restore_from(
            restore_path=ARGS.model, map_location=ARGS.device, strict=False)
        m.eval()
        _model = m
        log.info("Nemotron diarization model loaded (device=%s)", ARGS.device)
        return _model


def set_offline_params(m):
    """Offline streaming configuration from the model card. Re-applied per
    job: the transcription path reconfigures sortformer_modules for streaming
    (configure_diar_streaming), so this state is per-call, not per-load."""
    m.sortformer_modules.chunk_len = 340
    m.sortformer_modules.chunk_right_context = 40
    m.sortformer_modules.fifo_len = 40
    m.sortformer_modules.spkcache_update_period = 300
    m._check_streaming_parameters()
    return m


def unload_model():
    global _model, _asr_model, MODEL_LAST_USED
    with _model_lock:
        if _model is None and _asr_model is None:
            return
        idle = (time.time() - MODEL_LAST_USED) / 60
        _model = None
        _asr_model = None
        import gc
        import torch
        gc.collect()
        if torch.cuda.is_available():
            torch.cuda.empty_cache()
        log.info("model unloaded (idle %.0fm)", idle)


def parse_segments(raw):
    """NeMo returns per-job lists of 'start end speaker_N' strings; sort by
    start and relabel speaker_N -> S01.. like the MOSS API."""
    out = []
    for i, s in enumerate(raw):
        try:
            start, end, spk = s.split()
            idx = int(spk.rsplit("_", 1)[1]) if "_" in spk else int(spk)
            out.append({"id": f"seg_{i+1:04d}", "start": round(float(start), 3),
                        "end": round(float(end), 3),
                        "speaker": f"S{min(idx, 7) + 1:02d}"})
        except (ValueError, IndexError):
            continue
    out.sort(key=lambda x: x["start"])
    return out


# --- speaker-attributed transcription ----------------------------------------
# NVIDIA's documented pairing (model-card ASR_INTEGRATION_GUIDE, option 2):
# nemotron-3.5-asr-streaming-0.6b with masked_asr=true, replayed through
# NeMo's SpeakerTaggedASR. bf16 weights + eager decoding keep the footprint
# at ~1.6 GB so both models co-reside next to the moss vLLM engine.

_asr_model = None


def load_asr():
    global _asr_model
    with _model_lock:
        if _asr_model is not None or not ARGS.asr_model:
            return _asr_model
        import torch
        import nemo.collections.asr as nemo_asr
        # CPU restore, bf16 cast, then move: restoring fp32 weights straight
        # onto the GPU OOMs next to the resident moss engine.
        m = nemo_asr.models.ASRModel.restore_from(
            restore_path=ARGS.asr_model, map_location="cpu")
        m.encoder.set_default_att_context_size([56, 13])
        pre = m.encoder.pre_encode
        if hasattr(pre, "conv") and hasattr(pre.conv, "fuse_triton"):
            pre.conv.fuse_triton = False  # triton autotune needs 256 MiB free
        m = m.to(dtype=torch.bfloat16).to(ARGS.device).eval()
        dec = getattr(m.decoding, "decoding", None)
        if dec is not None and hasattr(dec, "disable_cuda_graphs"):
            dec.disable_cuda_graphs()  # graph capture needs headroom + fp32
        _asr_model = m
        log.info("Nemotron ASR model loaded (bf16, device=%s)", ARGS.device)
        return _asr_model


def transcribe_attributed(wav_path, target_lang="auto"):
    """Run the combined streaming replay; returns segments with text."""
    import torch
    from omegaconf import OmegaConf
    from nemo.collections.asr.parts.submodules.subsampling import FeatureStacking
    from nemo.collections.asr.parts.utils.multispk_transcribe_utils import (
        SpeakerTaggedASR, configure_diar_streaming,
        validate_feature_frame_strides)
    from nemo.collections.asr.parts.utils.streaming_utils import (
        CacheAwareStreamingAudioBuffer)

    asr = load_asr()
    if asr is None:
        raise RuntimeError("transcription requested but no ASR model configured")
    diar = load_model()
    diar = diar.to(dtype=torch.bfloat16)

    if hasattr(asr, "set_inference_prompt"):
        asr.set_inference_prompt(target_lang)
        asr.decoding.set_strip_lang_tags(True)

    torch.set_float32_matmul_precision("highest")
    autocast = torch.amp.autocast(device_type="cuda", dtype=torch.bfloat16,
                                  enabled=ARGS.device == "cuda")
    validate_feature_frame_strides(asr_model=asr, diar_model=diar)
    cfg = OmegaConf.create({
        "device": str(asr.device), "sample_rate": 16000, "deploy_mode": True,
        "streaming_mode": True, "max_num_of_spks": 8, "batch_size": 1,
        "parallel_speaker_strategy": True, "masked_asr": True,
        "mask_preencode": False, "single_speaker_mode": False,
        "cache_gating": True, "cache_gating_buffer_size": 2,
        "binary_diar_preds": True, "spkcache_len": None,
        "spkcache_update_period": 222, "fifo_len": 264, "diar_right_context": 0,
        "att_context_size": [56, 13], "use_amp": True, "precision": "bf16",
        "online_normalization": False, "pad_and_drop_preencoded": False,
        "feat_len_sec": 0.01, "discarded_frames": 8, "word_window": 50,
        "sent_break_sec": 1.0, "fix_prev_words_count": 5,
        "update_prev_words_sentence": 5, "left_frame_shift": -1,
        "right_frame_shift": 0, "min_sigmoid_val": 1e-2,
        "ignored_initial_frame_steps": 5, "chunk_size": -1, "shift_size": -1,
        "left_chunks": 5, "target_lang": target_lang,
        "strip_lang_tags": True, "spk_supervision": "diar", "log": False,
        "verbose": False,
    })
    diar_chunk_len = (asr.encoder.streaming_cfg.valid_out_len
                      + asr.encoder.streaming_cfg.cache_drop_size)
    configure_diar_streaming(
        diar_model=diar, cfg=cfg,
        output_subsampling_factor=asr.encoder.subsampling_factor,
        diar_chunk_len=diar_chunk_len)
    if isinstance(diar.encoder.pre_encode, FeatureStacking) and not cfg.pad_and_drop_preencoded:
        cfg.pad_and_drop_preencoded = True

    samples = [{"audio_filepath": str(wav_path)}]
    buffer = CacheAwareStreamingAudioBuffer(
        model=asr, online_normalization=cfg.online_normalization,
        pad_and_drop_preencoded=cfg.pad_and_drop_preencoded)
    buffer.append_audio_file(audio_filepath=samples[0]["audio_filepath"], stream_id=-1)

    streamer = SpeakerTaggedASR(cfg, asr, diar)
    for step_num, (chunk_audio, chunk_lengths, diar_chunk_audio,
                   diar_chunk_lengths) in enumerate(
            buffer.iter_with_right_context(
                cfg.diar_right_context * diar.encoder.subsampling_factor)):
        drop = (0 if step_num == 0 and not cfg.pad_and_drop_preencoded
                else asr.encoder.streaming_cfg.drop_extra_pre_encoded)
        with torch.inference_mode(), autocast, torch.no_grad():
            streamer.perform_parallel_streaming_stt_spk(
                step_num=step_num, chunk_audio=chunk_audio,
                chunk_lengths=chunk_lengths, diar_chunk_audio=diar_chunk_audio,
                diar_chunk_lengths=diar_chunk_lengths,
                is_buffer_empty=buffer.is_buffer_empty(),
                drop_extra_pre_encoded=drop)

    seglst = streamer.generate_seglst_dicts_from_parallel_streaming(samples=samples)
    out = []
    for i, s in enumerate(seglst):
        try:
            idx = int(str(s["speaker"]).rsplit("_", 1)[1])
        except (ValueError, IndexError):
            continue
        text = str(s.get("words", "")).strip()
        if not text:
            continue
        out.append({"id": f"seg_{i+1:04d}",
                    "start": round(float(s["start_time"]), 3),
                    "end": round(float(s["end_time"]), 3),
                    "speaker": f"S{min(idx, 7) + 1:02d}", "text": text})
    out.sort(key=lambda x: x["start"])
    return out


def write_rttm(job, segments):
    name = Path(job["media_name"]).stem
    lines = []
    for s in segments:
        dur = max(0.0, s["end"] - s["start"])
        lines.append(f"SPEAKER {name} 1 {s['start']:.3f} {dur:.3f} "
                     f"<NA> <NA> {s['speaker']} <NA> <NA>")
    (job_dir(job["id"]) / "diarization.rttm").write_text("\n".join(lines) + "\n")


def fmt_ts(sec):
    ms = int(round(sec * 1000))
    h, ms = divmod(ms, 3600000)
    m, ms = divmod(ms, 60000)
    s, ms = divmod(ms, 1000)
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"


def write_srt(job, segments):
    """SRT from speaker-attributed segments (only meaningful with text)."""
    blocks = []
    for i, s in enumerate(segments, 1):
        text = s.get("text", "").strip()
        if not text:
            continue
        blocks.append(f"{i}\n{fmt_ts(s['start'])} --> {fmt_ts(s['end'])}\n"
                      f"[{s['speaker']}] {text}\n")
    (job_dir(job["id"]) / "transcript.srt").write_text("\n".join(blocks))


def write_segments(job, segments):
    (job_dir(job["id"]) / "segments.json").write_text(
        json.dumps({"segments": segments}, indent=2))
    write_rttm(job, segments)
    if any(s.get("text") for s in segments):
        write_srt(job, segments)
    job["num_segments"] = len(segments)
    job["speakers"] = len({s["speaker"] for s in segments})


def decode_audio(src, dst):
    r = subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-i", str(src),
         "-ac", "1", "-ar", "16000", str(dst)],
        capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"ffmpeg decode failed: {r.stderr.strip()[:500]}")


def audio_seconds(wav):
    r = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "csv=p=0", str(wav)],
        capture_output=True, text=True)
    try:
        return round(float(r.stdout.strip()), 3)
    except ValueError:
        return None


def worker():
    while True:
        job_id = QUEUE.get()
        with JOBS_LOCK:
            job = JOBS.get(job_id)
        if not job or job.get("status") not in ACTIVE:
            continue
        try:
            d = job_dir(job_id)
            media = d / job["media_name"]
            if not media.exists():
                raise RuntimeError("input file vanished")
            set_status(job, "decoding", 0.05)
            wav = d / "audio16k.wav"
            decode_audio(media, wav)
            job["audio_sec"] = audio_seconds(wav)

            set_status(job, "loading_model", 0.15)
            global MODEL_LAST_USED
            want_text = job.get("transcribe", True) and bool(ARGS.asr_model)
            if want_text:
                load_asr()
            load_model()
            MODEL_LAST_USED = time.time()

            if want_text:
                set_status(job, "transcribing", 0.3)
                segments = transcribe_attributed(wav, job.get("target_lang", "auto"))
            else:
                set_status(job, "diarizing", 0.3)
                model = load_model()
                import torch
                model = model.to(dtype=torch.float32)
                set_offline_params(model)
                raw = model.diarize(audio=[str(wav)], batch_size=1)[0]
                segments = parse_segments(raw)
            MODEL_LAST_USED = time.time()

            set_status(job, "postprocessing", 0.9)
            if not segments:
                raise RuntimeError("diarization produced no segments")
            write_segments(job, segments)
            set_status(job, "done", 1.0)
        except Exception as e:  # noqa: BLE001 - job isolation
            log.exception("job %s failed", job_id)
            set_status(job, "failed", 0.0, error=str(e)[:500])


def idle_watchdog():
    if ARGS.idle_unload_minutes <= 0:
        return
    while True:
        time.sleep(60)
        if (_model is not None or _asr_model is not None) and \
                time.time() - MODEL_LAST_USED > ARGS.idle_unload_minutes * 60:
            unload_model()


# --- API ----------------------------------------------------------------------

app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)


class SegmentsBody(BaseModel):
    segments: list[dict]


@app.get("/api/runtime")
def runtime():
    return {
        "service": "nemotron-diarize",
        "backend": "nemo",
        "model": ARGS.model,
        "model_name": "Nemotron-3-Diarization",
        "asr_model": ARGS.asr_model,
        "asr_model_name": "nemotron-3.5-asr-streaming-0.6b" if ARGS.asr_model else None,
        "transcription": bool(ARGS.asr_model),
        "device": ARGS.device,
        "max_speakers": 8,
        "sample_rate": 16000,
        "model_loaded": _model is not None,
        "asr_loaded": _asr_model is not None,
        "idle_unload_minutes": ARGS.idle_unload_minutes,
    }


@app.get("/api/jobs")
def list_jobs():
    with JOBS_LOCK:
        jobs = sorted(JOBS.values(), key=lambda j: j["created_at"], reverse=True)
    return {"jobs": [public(j) for j in jobs]}


@app.post("/api/jobs")
def create_job(file: UploadFile = File(...),
               transcribe: Optional[bool] = Form(None),
               target_lang: Optional[str] = Form(None)):
    job_id = uuid.uuid4().hex[:12]
    d = job_dir(job_id)
    d.mkdir(parents=True, exist_ok=True)
    safe = Path(file.filename or "input").name
    dest = d / safe
    with dest.open("wb") as f:
        shutil.copyfileobj(file.file, f)
    job = {"id": job_id, "status": "queued", "media_name": safe,
           "progress": 0.0, "created_at": now(), "updated_at": now(),
           "num_segments": 0, "speakers": 0,
           # text+speakers when an ASR model is configured, unless asked off
           "transcribe": bool(ARGS.asr_model) if transcribe is None else transcribe,
           "target_lang": target_lang or "auto"}
    with JOBS_LOCK:
        JOBS[job_id] = job
    persist(job)
    QUEUE.put(job_id)
    log.info("job %s queued (%s, %d bytes, transcribe=%s)",
             job_id, safe, dest.stat().st_size, job["transcribe"])
    return public(job)


@app.get("/api/jobs/{job_id}")
def job_status(job_id: str):
    return public(get_job(job_id))


@app.delete("/api/jobs/{job_id}")
def delete_job(job_id: str):
    job = get_job(job_id)
    if job["status"] in ACTIVE:
        raise err("job_running", 409, "cannot delete a running job")
    with JOBS_LOCK:
        JOBS.pop(job_id, None)
    shutil.rmtree(job_dir(job_id), ignore_errors=True)
    return {"deleted": job_id}


@app.post("/api/jobs/{job_id}/rerun")
def rerun_job(job_id: str):
    """New job from the same input, MOSS rerun semantics (original untouched)."""
    job = get_job(job_id)
    src = job_dir(job_id) / job["media_name"]
    if not src.exists():
        raise err("media_missing", 404, "input file vanished from the runs dir")
    new_id = uuid.uuid4().hex[:12]
    d = job_dir(new_id)
    d.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, d / job["media_name"])
    new = {"id": new_id, "status": "queued", "media_name": job["media_name"],
           "progress": 0.0, "created_at": now(), "updated_at": now(),
           "num_segments": 0, "speakers": 0,
           "transcribe": job.get("transcribe", bool(ARGS.asr_model)),
           "target_lang": job.get("target_lang", "auto")}
    with JOBS_LOCK:
        JOBS[new_id] = new
    persist(new)
    QUEUE.put(new_id)
    return public(new)


@app.get("/api/jobs/{job_id}/media")
def job_media(job_id: str):
    job = get_job(job_id)
    media = job_dir(job_id) / job["media_name"]
    if not media.exists():
        raise err("media_missing", 404, "input file vanished from the runs dir")
    return FileResponse(media, filename=job["media_name"])


@app.get("/api/jobs/{job_id}/segments")
def job_segments(job_id: str):
    job = get_job(job_id)
    seg = job_dir(job_id) / "segments.json"
    if not seg.exists():
        raise err("subtitles_unavailable", 503, "no segments yet")
    return json.loads(seg.read_text())


@app.put("/api/jobs/{job_id}/segments")
def put_segments(job_id: str, body: SegmentsBody):
    job = get_job(job_id)
    segs = []
    for s in body.segments:
        try:
            segs.append({"id": str(s.get("id", f"seg_{len(segs)+1:04d}")),
                         "start": round(float(s["start"]), 3),
                         "end": round(float(s["end"]), 3),
                         "speaker": str(s["speaker"]),
                         "text": str(s.get("text", "")).strip()})
        except (KeyError, TypeError, ValueError):
            raise err("invalid_segments", 400, "segments need start/end/speaker")
    segs.sort(key=lambda x: x["start"])
    with JOBS_LOCK:
        write_segments(job, segs)
        set_status(job, job["status"], job["progress"])
    return {"segments": len(segs)}


@app.get("/api/jobs/{job_id}/download")
def download(job_id: str, kind: str = "json"):
    job = get_job(job_id)
    d = job_dir(job_id)
    files = {"json": "segments.json", "segments": "segments.json",
             "rttm": "diarization.rttm", "srt": "transcript.srt"}
    name = files.get(kind)
    if not name:
        raise err("invalid_kind", 400, f"kind must be one of {sorted(files)}")
    f = d / name
    if not f.exists():
        raise err("file_not_ready", 404, f"{kind} not generated yet")
    return FileResponse(f, filename=f"{job['media_name'].rsplit('.', 1)[0]}.{kind}")


@app.get("/", response_class=HTMLResponse)
def index():
    return UI_HTML


UI_HTML = """<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Nemotron Diarization</title>
<style>
  :root { color-scheme: dark; }
  body { margin:0; padding:24px; font:14px/1.5 ui-monospace,Menlo,monospace;
         background:#0e1116; color:#c9d1d9; }
  .wrap { max-width:880px; margin:0 auto; }
  h1 { font-size:16px; color:#e6edf3; margin:0 0 2px; }
  .sub { color:#768390; font-size:12px; margin-bottom:18px; }
  .up { display:flex; gap:8px; margin-bottom:18px; }
  input[type=file] { flex:1; background:#161b22; border:1px solid #21262d;
                     border-radius:6px; color:#c9d1d9; padding:8px; }
  button { background:#1f6f3f; color:#d8ffe3; border:0; border-radius:6px;
           padding:8px 18px; font-weight:600; cursor:pointer; }
  button:disabled { opacity:.5; cursor:default; }
  .job { background:#161b22; border:1px solid #21262d; border-radius:8px;
         padding:12px 14px; margin-bottom:10px; }
  .job h3 { margin:0 0 6px; font-size:13px; color:#e6edf3; display:flex;
            justify-content:space-between; gap:8px; }
  .chip { font-size:11px; padding:2px 8px; border-radius:10px; font-weight:600; }
  .chip.done { background:#1f6f3f; color:#d8ffe3; }
  .chip.failed { background:#7a1f1f; color:#ffd6d6; }
  .chip.run { background:#5a3a00; color:#ffe0a3; }
  .meta { color:#768390; font-size:12px; margin-bottom:6px; }
  .turns { margin:4px 0 6px; }
  .turns div { padding:2px 0 2px 10px; border-left:2px solid #30363d;
              font-size:12px; }
  .links a { color:#58a6ff; text-decoration:none; margin-right:12px; font-size:12px; }
  .err { color:#ff7b72; font-size:12px; }
</style></head><body><div class="wrap">
<h1>Nemotron Diarization</h1>
<div class="sub" id="sub">who spoke when — up to 8 speakers · jobs API at /api/jobs</div>
<div class="up">
  <input type="file" id="f">
  <button id="go" onclick="up()">Run</button>
</div>
<div class="opts" style="color:#768390;font-size:12px;margin-bottom:18px;">
  <label><input type="checkbox" id="tr" checked> transcribe (speaker-attributed text)</label>
</div>
<div id="jobs"></div>
</div>
<script>
const S = {queued:"run", decoding:"run", loading_model:"run", diarizing:"run",
           transcribing:"run", postprocessing:"run", done:"done", failed:"failed"};
const C = ["#58a6ff","#3fb950","#d29922","#bc8cff","#ff7b72","#39c5cf","#e3b341","#f778ba"];
async function up() {
  const f = document.getElementById("f").files[0];
  if (!f) return;
  document.getElementById("go").disabled = true;
  try {
    const fd = new FormData();
    fd.append("file", f);
    fd.append("transcribe", document.getElementById("tr").checked);
    const r = await fetch("/api/jobs", {method:"POST", body: fd});
    await r.json(); document.getElementById("f").value = "";
  } finally { document.getElementById("go").disabled = false; refresh(); }
}
async function refresh() {
  let jobs, rt;
  try {
    jobs = (await (await fetch("/api/jobs")).json()).jobs;
    rt = await (await fetch("/api/runtime")).json();
  } catch (e) { return; }
  document.getElementById("sub").textContent =
    (rt.transcription ? "speaker-attributed transcription" : "who spoke when") +
    " — up to 8 speakers · jobs API at /api/jobs";
  document.getElementById("tr").disabled = !rt.transcription;
  document.getElementById("jobs").innerHTML = jobs.slice(0, 12).map(j => {
    let body = "";
    if (j.status === "done") {
      body = '<div class="links"><a href="/api/jobs/' + j.id + '/segments">segments JSON</a>' +
        '<a href="/api/jobs/' + j.id + '/download?kind=rttm">RTTM</a>' +
        (j.transcribe && rt.transcription ?
          '<a href="/api/jobs/' + j.id + '/download?kind=srt">SRT</a>' : "") +
        '<a href="/api/jobs/' + j.id + '/media">source</a></div>' +
        '<div class="turns" id="t-' + j.id + '"></div>';
    }
    if (j.status === "failed") body = '<div class="err">' + (j.error || "") + "</div>";
    return '<div class="job"><h3><span>' + j.media_name + "</span>" +
      '<span class="chip ' + S[j.status] + '">' + j.status +
      (j.status === "failed" ? "" : " " + Math.round(100 * (j.progress || 0)) + "%") +
      "</span></h3>" +
      '<div class="meta">' + (j.audio_sec ? j.audio_sec.toFixed(1) + "s audio · " : "") +
      (j.speakers ? j.speakers + " speakers · " + j.num_segments + " turns" : "") +
      "</div>" + body + "</div>";
  }).join("");
  for (const j of jobs.slice(0, 12)) {
    if (j.status !== "done" || !j.transcribe) continue;
    fetch("/api/jobs/" + j.id + "/segments").then(r => r.json()).then(d => {
      const el = document.getElementById("t-" + j.id);
      if (!el) return;
      el.innerHTML = d.segments.slice(0, 40).map(s => {
        const n = (parseInt(s.speaker.slice(1)) || 1) - 1;
        return '<div style="border-color:' + C[n % 8] + '"><b style="color:' +
          C[n % 8] + '">' + s.speaker + "</b> " + s.start.toFixed(1) + "s " +
          (s.text || "") + "</div>";
      }).join("");
    }).catch(() => {});
  }
}
refresh(); setInterval(refresh, 3000);
</script></body></html>
"""


def load_persisted_jobs():
    """Readopt run dirs; anything that was mid-flight when the service died is
    marked failed so polls don't hang."""
    runs = Path(ARGS.runs_dir)
    runs.mkdir(parents=True, exist_ok=True)
    with JOBS_LOCK:
        for d in runs.iterdir():
            f = d / "job.json"
            if not f.is_file():
                continue
            try:
                job = json.loads(f.read_text())
            except ValueError:
                continue
            if job.get("status") in ACTIVE:
                job["status"] = "failed"
                job["error"] = "service restarted during job"
                job["updated_at"] = now()
                f.write_text(json.dumps(job, indent=2))
            JOBS[job["id"]] = job


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--model", required=True, help="path to the .nemo checkpoint")
    p.add_argument("--asr-model", default=None,
                   help="optional nemotron-3.5-asr .nemo checkpoint; enables "
                        "speaker-attributed transcription (text on segments)")
    p.add_argument("--runs-dir", required=True)
    p.add_argument("--host", default="127.0.0.1")
    p.add_argument("--port", type=int, default=7862)
    p.add_argument("--device", default="cuda", choices=["cuda", "cpu"])
    p.add_argument("--idle-unload-minutes", type=int, default=30,
                   help="unload the resident model after this many idle "
                        "minutes (0 disables)")
    p.parse_args(namespace=ARGS)
    ARGS.runs_dir = str(Path(ARGS.runs_dir).resolve())

    load_persisted_jobs()
    threading.Thread(target=worker, daemon=True, name="worker").start()
    threading.Thread(target=idle_watchdog, daemon=True, name="idle-unload").start()

    import uvicorn
    uvicorn.run(app, host=ARGS.host, port=ARGS.port, log_level="info",
                access_log=False)


if __name__ == "__main__":
    main()
