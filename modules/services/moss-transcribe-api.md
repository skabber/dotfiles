# MOSS-Transcribe-Diarize API

Speaker-diarized transcription service exposing the same jobs API on every host
that enables it. Uploads any audio/video file and returns timestamped,
speaker-labeled segments (`S01`, `S02`, …) plus SRT/ASS/JSON exports and optional
MP4 burn-in. The backend differs per host but the API does not: `nixos-ripper`
and `framework-13` run the HF/ROCm backend in-process; `nixos` runs a loopback
vLLM engine (CUDA) that the web app proxies to.

- Base URLs (Tailscale Serve, tailnet only — requires `moss-transcribe.serve =
true`; binds loopback so all access goes through the HTTPS proxy):
  - `https://nixos-ripper.tail69fe1.ts.net:7860`
  - `https://nixos.tail69fe1.ts.net:7860`

  Raw `http://<host>:7860` works when serve is disabled. Physical-LAN access
  needs `moss-transcribe.openFirewall = true`
- Web UI: the same URL — upload, review, and export in the browser
- Service: `systemctl status moss-transcribe` (inference; on `nixos` also
  `moss-transcribe-web`, the jobs API front end)
- Model: `/home/jay/models/MOSS-Transcribe-Diarize` (`nixos`:
  `/home/jay/dotfiles/models/…`; 0.9B, lazy-loaded on first job on hf, resident
  ~4 GB VRAM)
- Storage: `/var/lib/moss-transcribe/runs/<job-id>/`

## Quickstart

```bash
BASE=https://nixos-ripper.tail69fe1.ts.net:7860   # or http://localhost:7860 on the host itself

# 1. Upload — returns job JSON with the id
JOB=$(curl -s -F file=@recording.mp3 $BASE/api/jobs)
ID=$(echo "$JOB" | jq -r .id)

# 2. Poll until status is waiting_review / done
watch -n5 "curl -s $BASE/api/jobs/$ID | jq .status,.progress"

# 3. Get diarized segments
curl -s $BASE/api/jobs/$ID/segments | jq

# 4. Download subtitles
curl -sO "$BASE/api/jobs/$ID/download?kind=srt"
```

## Endpoints

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/runtime` | Server config: ffmpeg, model, device, attention, defaults |
| GET | `/api/jobs` | List all jobs (newest first) |
| POST | `/api/jobs` | Upload file, queue transcription |
| GET | `/api/jobs/{id}` | Job status/progress/result metadata |
| DELETE | `/api/jobs/{id}` | Delete job + its files (rejected while running) |
| POST | `/api/jobs/{id}/rerun` | Re-transcribe with new options |
| GET | `/api/jobs/{id}/media` | Download the original input file |
| GET | `/api/jobs/{id}/segments` | Parsed segments (speaker/time/text) |
| PUT | `/api/jobs/{id}/segments` | Edit segments; rewrites SRT/ASS/JSON |
| POST | `/api/jobs/{id}/render` | Burn subtitles into an MP4 (async) |
| GET | `/api/jobs/{id}/download?kind=` | Download artifact |

### POST /api/jobs

Multipart upload. All fields except `file` are optional and default to the
service's configured values.

| Field | Type | Default | Notes |
|---|---|---|---|
| `file` | file | required | mp3, wav, m4a, mp4, mkv, webm, … |
| `max_new_tokens` | int | 2048 | **Raise for long audio** (see below) |
| `max_len` | int | 131072 | Total context cap; ~2.9 h audio max |
| `decoding` | str | `greedy` | `greedy` or `sample` |
| `temperature` | float | — | Only used with `decoding=sample` |
| `prompt` | str | built-in | Override the transcription instruction |

```bash
curl -F file=@meeting.mp3 \
     -F max_new_tokens=65536 \
     $BASE/api/jobs
```

Response (trimmed):

```json
{
  "id": "edd0f0e4ad90",
  "status": "queued",
  "media_name": "meeting.mp3",
  "progress": 0.0,
  "max_new_tokens": 65536
}
```

**Sizing `max_new_tokens`:** generation stops when the cap is hit and the
transcript is silently truncated. Rule of thumb: 2048 ≈ short clips;
8192 ≈ ~30 min; 65536 ≈ anything up to the ~2.9 h context ceiling.
Generation runs ~8–9 tok/s on this GPU.

**Hotwords:** pass the default prompt plus a hint appended (comma-separated):

```bash
PROMPT='请将音频转写为文本，每一段需以起始时间戳和说话人编号（[S01]、[S02]、[S03]…）开头，正文为对应的语音内容，并在段末标注结束时间戳，以清晰标明该段语音范围。热词提示：Jay, NixOS, ROCm'
curl -F file=@call.mp3 -F "prompt=$PROMPT" $BASE/api/jobs
```

### GET /api/jobs/{id}

```bash
curl -s $BASE/api/jobs/$ID | jq '{status,progress,generated_tokens,elapsed_sec,error}'
```

Job lifecycle: `queued` → `loading_model` (first job after boot) →
`transcribing` (progress 0.10–0.85) → `postprocessing` → `waiting_review`
→ `rendering` (only if you POST render) → `done`. Failures land in `failed`
with `error` set. A job stays in `waiting_review` until you edit segments,
render, or just leave it — artifacts are downloadable either way.

### GET /api/jobs/{id}/segments

```json
{
  "segments": [
    {"id": "seg_0001", "start": 1.15, "end": 2.82, "speaker": "S01", "text": "Describe your needs and goals."},
    {"id": "seg_0002", "start": 3.12, "end": 4.42, "speaker": "S01", "text": "And AI will transform..."},
    {"id": "seg_0003", "start": 4.55, "end": 5.75, "speaker": "S02", "text": "Do you get the system audio?"}
  ]
}
```

Times are seconds. The un parsed raw transcript is downloadable as
`kind=transcript`:

```
[1.15][S01] Describe your needs and goals.[2.82][3.12][S01] And AI will transform...[4.42]
```

### PUT /api/jobs/{id}/segments

Send the full corrected list (fix typos, rename speakers, merge/split). All
subtitle files are rewritten immediately.

```bash
curl -s $BASE/api/jobs/$ID/segments | jq '.segments[2].text = "Do you get the system audio?"' \
  | curl -s -X PUT -H 'Content-Type: application/json' -d @- \
      $BASE/api/jobs/$ID/segments
```

Speaker renaming is just editing the `speaker` fields before PUT:

```bash
curl -s $BASE/api/jobs/$ID/segments \
  | jq '.segments |= map(.speaker |= sub("S01"; "Jay") | .speaker |= sub("S02"; "Bob"))' \
  | curl -s -X PUT -H 'Content-Type: application/json' -d @- \
      $BASE/api/jobs/$ID/segments
```

### POST /api/jobs/{id}/render

Burns the current segments into the video/audio as an MP4. Async — returns
immediately with status `rendering`; poll the job until `done`. Input must be
a video file for a meaningful output (audio-only inputs are supported but
produce a black frame). Optional JSON body carries subtitle styling; the web
UI exposes the same knobs.

```bash
curl -s -X POST $BASE/api/jobs/$ID/render | jq .status
```

### GET /api/jobs/{id}/download

| `kind` | File |
|---|---|
| `srt` | SubRip subtitles (speaker-prefixed) |
| `ass` | ASS subtitles (styled) |
| `json` or `segments` | segments.json |
| `transcript` | raw transcript text |
| `mp4` | burned-in video (after render) |

### POST /api/jobs/{id}/rerun

Re-runs inference on the same input, keeping the original file. Any option
omitted inherits the job's previous values — handy when a long recording came
back truncated:

```bash
curl -s -X POST -H 'Content-Type: application/json' \
     -d '{"max_new_tokens": 65536}' \
     $BASE/api/jobs/$ID/rerun | jq .id
```

Note: rerun creates a **new** job; the original is untouched.

## Errors

Errors come back as `{"detail": "...", "code": "..."}`.

| Code | HTTP | Meaning |
|---|---|---|
| `job_not_found` | 404 | Unknown job id |
| `job_running` | 409 | Tried to delete a running job |
| `invalid_max_new_tokens` / `invalid_max_length` / `invalid_temperature` / `invalid_decoding` | 400 | Bad option value |
| `media_missing` | 404 | Input file vanished from the runs dir |
| `subtitles_unavailable` | 503 | No segments yet |
| `ffmpeg_unavailable` | 503 | ffmpeg/ffprobe not on PATH (shouldn't happen) |
| `file_not_ready` | 404 | Artifact not generated yet (e.g. `mp4` before render) |

## Python client

```python
import time, requests

BASE = "https://nixos-ripper.tail69fe1.ts.net:7860"
f = {"file": open("meeting.mp3", "rb")}
data = {"max_new_tokens": 8192}
job = requests.post(f"{BASE}/api/jobs", files=f, data=data, timeout=120).json()

while job["status"] not in {"waiting_review", "done", "failed"}:
    time.sleep(5)
    job = requests.get(f"{BASE}/api/jobs/{job['id']}").json()
    print(job["status"], round(job.get("progress", 0), 2))

if job["status"] == "failed":
    raise SystemExit(job["error"])

segments = requests.get(f"{BASE}/api/jobs/{job['id']}/segments").json()["segments"]
for s in segments:
    print(f"[{s['start']:7.2f}–{s['end']:7.2f}] {s['speaker']}: {s['text']}")
```

Jobs are processed one at a time (single GPU lock) — submit in a loop and
poll; the queue serializes them.

## Measured on nixos-ripper (hf/ROCm)

| | |
|---|---|
| Attention | `sdpa` (flash-attn is CUDA-only; RDNA 2 uses SDPA) |
| VRAM | ~4 GB resident after first job |
| Throughput | ~8.5 generated tok/s |
| 13.7 s clip | 18 s to transcribe (incl. warm-up), 153 tokens |
| Max single pass | ~2.9 h of audio (131072-token context) — chunk longer files yourself |

## Nix configuration

In `hosts/*/default.nix` / `modules/services/moss-transcribe.nix`.
AMD hosts (in-process HF/ROCm inference):

```nix
moss-transcribe = {
  enable = true;
  serve = true;         # Tailscale Serve HTTPS + loopback-only bind
  port = 7860;          # default; same jobs API on every host
  modelPath = "/home/jay/models/MOSS-Transcribe-Diarize";
  dtype = "bf16";       # fp16 | fp32 if bf16 misbehaves on RDNA 2
  gfxVersion = "10.3.0";  # HSA override (RDNA 2); null when rocm-dev pins native kernels
  maxNewTokens = 2048;  # service default; override per-request
};
```

NVIDIA host (vLLM engine behind the same jobs API):

```nix
moss-transcribe = {
  enable = true;
  backend = "vllm";     # default is "hf"
  serve = true;
  vllmPort = 8010;      # loopback-only engine port (default)
  gpuMemoryUtilization = 0.6;
  maxBatchedTokens = 16384;  # caps audio length per request (~22 min)
};
```

Per-request options always win over the service defaults — no rebuild needed
to raise `max_new_tokens` for a long file.
