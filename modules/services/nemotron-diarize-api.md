# Nemotron Transcribe/Diarize API

Speaker-attributed transcription jobs API on `nixos` (RTX 3080): NVIDIA
**Nemotron 3.5 ASR** (streaming 0.6B, 40 language-locales, auto language ID,
native punctuation) paired with **Nemotron 3 Diarization** (100M, up to 8
speakers) exactly as NVIDIA's model-card integration guide documents
(masked-ASR streaming replay). Same surface as the MOSS-Transcribe-Diarize
jobs API: upload → poll → speaker-labeled segments, plus JSON/RTTM/SRT
export. With `transcribe=0` (or transcription disabled) jobs degrade to
diarization-only speaker turns.

- Base URL (Tailscale Serve, tailnet only — `nemotron-diarize.serve = true`
binds loopback so all access goes through the HTTPS proxy):
  `https://nixos.tail69fe1.ts.net:7862`
- Web UI: the same URL — upload (with transcribe toggle), watch jobs, browse
  the color-coded transcript, download artifacts
- Service: `systemctl status nemotron-diarize` (setup:
  `nemotron-diarize-setup`, one-shot venv builder)
- Backend: NeMo Speech (`NVIDIA-NeMo/Speech` git pin, not PyPI — PyPI 3.0.0
  lacks the RoPE encoder), CUDA torch from a uv venv, bf16 weights, eager
  decoding (TORCHDYNAMO_DISABLE), RNNT CUDA graphs and the fused triton
  subsampling kernel off — VRAM headroom next to the moss engine
- Models (lazy-loaded on first job, idle-unloaded after 30 min):
  - `/home/jay/dotfiles/models/Nemotron-3-Diarization/Nemotron-3-Diarization.nemo`
  - `/home/jay/dotfiles/models/nemotron-3.5-asr-streaming-0.6b/nemotron-3.5-asr-streaming-0.6b.nemo`
- Storage: `/var/lib/nemotron-diarize/runs/<job-id>/`

## Quickstart

```bash
BASE=https://nixos.tail69fe1.ts.net:7862

# 1. Upload — returns job JSON with the id
JOB=$(curl -s -F file=@meeting.mp3 $BASE/api/jobs)
ID=$(echo "$JOB" | jq -r .id)

# 2. Poll until status is done (first job also loads both models, ~60 s)
watch -n5 "curl -s $BASE/api/jobs/$ID | jq .status,.progress"

# 3. Get speaker-attributed segments (text + speaker + times)
curl -s $BASE/api/jobs/$ID/segments | jq

# 4. Download subtitles / diarization
curl -sO "$BASE/api/jobs/$ID/download?kind=srt"
curl -sO "$BASE/api/jobs/$ID/download?kind=rttm"

# Diarization only (no text, ~10x faster):
curl -s -F file=@meeting.mp3 -F transcribe=false $BASE/api/jobs
```

## Endpoints

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/runtime` | Server config: models, device, max speakers, loaded state |
| GET | `/api/jobs` | List all jobs (newest first) |
| POST | `/api/jobs` | Upload file, queue transcription/diarization |
| GET | `/api/jobs/{id}` | Job status/progress/metadata |
| DELETE | `/api/jobs/{id}` | Delete job + its files (rejected while running) |
| POST | `/api/jobs/{id}/rerun` | Re-run the same input (creates a NEW job) |
| GET | `/api/jobs/{id}/media` | Download the original input file |
| GET | `/api/jobs/{id}/segments` | Parsed segments (speaker/time/text) |
| PUT | `/api/jobs/{id}/segments` | Edit segments; rewrites JSON/RTTM/SRT |
| GET | `/api/jobs/{id}/download?kind=` | Download artifact (`json`, `rttm`, `srt`) |

### POST /api/jobs

Multipart upload. All fields except `file` are optional.

| Field | Type | Default | Notes |
|---|---|---|---|
| `file` | file | required | mp3, wav, m4a, flac, ogg, opus, mp4, mkv, webm, mov — anything ffmpeg decodes |
| `transcribe` | bool | true (when an ASR model is configured) | `false` = diarization-only speaker turns |
| `target_lang` | str | `auto` | ASR language-locale prompt, e.g. `en-US`, `zh-CN`; `auto` detects and emits the language tag |

Job lifecycle: `queued` → `decoding` (ffmpeg → 16 kHz mono WAV) →
`loading_model` (first job after boot/idle-unload only) → `transcribing`
(or `diarizing` for diarize-only) → `postprocessing` → `done`. Failures land
in `failed` with `error` set. Progress is coarse (stage constants).

### GET /api/jobs/{id}/segments

Transcribed job:

```json
{
  "segments": [
    {"id": "seg_0001", "start": 0.4, "end": 9.68, "speaker": "S01",
     "text": "To celebrate the release of Nemotron Three diorization, we invited seven more open text to speech voices to the party."},
    {"id": "seg_0002", "start": 9.52, "end": 14.4, "speaker": "S02",
     "text": "Hi everybody, thanks for having me. I'm Jane, a pocket voice."}
  ]
}
```

Times are seconds; adjacent segments may overlap slightly (sentence turns).
Speakers are ordered by first arrival in the recording. Diarize-only jobs
carry speaker-activity turns (no `text`), which can be finer-grained.
Renaming speakers or fixing text is just editing fields before
`PUT /api/jobs/{id}/segments` (send the full list; SRT/RTTM are rewritten).

### Downloads

| `kind` | File |
|---|---|
| `json` / `segments` | segments.json |
| `rttm` | standard diarization RTTM |
| `srt` | SubRip subtitles, `[S01]`-prefixed (transcribed jobs) |

## Errors

`{"detail": {"code": ..., "detail": ...}}` shape, codes: `job_not_found`
(404), `job_running` (409), `media_missing` (404), `subtitles_unavailable`
(503, no segments yet), `file_not_ready` (404), `invalid_segments` /
`invalid_kind` (400).

## Measured on nixos (RTX 3080, bf16 eager, next to the resident moss engine)

| | diarize-only | transcribe (ASR + diarizer) |
|---|---|---|
| VRAM | 708 MiB | 1.9 GiB |
| Throughput | RTFx ~60 | RTFx ~5.5 warm (~1 h audio ≈ 11 min GPU) |
| First job | ~20 s | ~85 s (both models load) |
| Speakers | up to 8, overlaps preserved | up to 8, overlap-masked ASR |
| Languages | n/a | 32 locales out of the box + auto-detect (verified: en + hi in one file) |

Jobs run one at a time (single worker); jobs survive service restarts
(mid-flight jobs are marked failed on adopt).

## gpu-gateway integration

When the gateway is enabled, it fronts the service on its loopback sidecar
port (published under 7862 as usual) and treats it as a co-resident sidecar,
not a time-share tenant — its short jobs never evict the moss or freetoken
engines:

- Mutating requests (uploads/edits) are held while the sidecar is down and
  the governor starts it on demand (only while MOSS is resident)
- GETs fail fast (503 + Retry-After) while it is down and never count as
  demand
- A FREETOKEN transition drains in-flight jobs (≤ `diarDrainTimeoutSec`,
  default 120 s) and stops the sidecar first so freetoken's memory-fit
  solver sees the full card; returning to MOSS restarts it
- Status: the `diar` block in `/__gw/status` and the gateway UI card

With the gateway enabled set `nemotron-diarize.serve = false` (the gateway's
serve unit owns the public port, same rule as moss).

## Versus MOSS-Transcribe (:7860)

Use MOSS for Mandarin-first content, hotword prompting, and single-pass
90-minute contexts; use this service for English/multilingual meetings
(overlap-aware 8-speaker attribution, auto language ID, no token-count
truncation, seconds-scale diarize-only passes). Both share the same jobs API
shape.

## Nix configuration

`modules/services/nemotron-diarize.nix`, enabled in `hosts/nixos/default.nix`:

```nix
nemotron-diarize = {
  enable = true;
  enableTranscription = true;   # + nemotron-3.5-asr (text on segments, SRT)
  serve = true;                 # Tailscale Serve HTTPS + loopback-only bind
  port = 7862;                  # default
  modelPath = "/home/jay/dotfiles/models/Nemotron-3-Diarization/Nemotron-3-Diarization.nemo";
  asrModelPath = "/home/jay/dotfiles/models/nemotron-3.5-asr-streaming-0.6b/nemotron-3.5-asr-streaming-0.6b.nemo";
  device = "cuda";              # cpu is the emergency fallback (~60x slower)
  idleUnloadMinutes = 30;       # unload resident models when idle
  nemoSpec = "nemo-toolkit[asr] @ git+https://github.com/NVIDIA-NeMo/Speech.git@16b0ff2584c6";
};
```

Bumping `nemoSpec` re-runs the setup unit (uv upgrades in place). The venv
rebuilds when the pinned Python minor changes.
