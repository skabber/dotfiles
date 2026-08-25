#!/usr/bin/env bash
# Summarize a meeting transcript with a local Ollama model, VRAM-aware.
# Input: a moss-transcribe job id (--job) or a local .txt/.srt/.vtt/.json file.
set -euo pipefail

URL="${OLLAMA_HOST:-http://127.0.0.1:11434}"
MOSS_URL="${MOSS_URL:-http://127.0.0.1:7860}"
MODEL="meeting-summarizer"
CTX=32768
FALLBACK_MODEL="qwen3.5:9b"
OUT=""
JOB=""
FILE=""
FOCUS=""

export OLLAMA_HOST="$URL"

usage() {
  cat <<'EOF'
Usage: summarize-meeting.sh [--job <moss-id> | -f <transcript.txt|.srt|.vtt|.json>]
                            [-m <model>] [-c <num_ctx>] [-o <out.md>] [--focus "<hint>"]

  --job     moss-transcribe job id (fetches diarized segments from $MOSS_URL)
  -f        transcript file (.txt raw, .srt/.vtt subtitles, .json moss segments)
  -m        ollama model (default: meeting-summarizer alias of ministral-3:14b)
  -c        max context tokens (default 32768; auto-halved if the model
            won't fit fully in VRAM: 32768 -> 16384 -> 8192)
  -o        also write the summary to this markdown file
  --focus   extra instruction, e.g. "focus on pricing decisions"

Env: OLLAMA_HOST (default http://127.0.0.1:11434), MOSS_URL (default http://127.0.0.1:7860)
EOF
  exit "${1:-1}"
}

die() { echo "error: $*" >&2; exit 1; }

for cmd in jq curl ollama; do
  command -v "$cmd" >/dev/null || die "$cmd not found in PATH"
done

while [[ $# -gt 0 ]]; do
  case "$1" in
    --job) JOB="${2:-}"; shift 2 ;;
    -f|--file) FILE="${2:-}"; shift 2 ;;
    -m|--model) MODEL="${2:-}"; shift 2 ;;
    -c|--ctx) CTX="${2:-}"; shift 2 ;;
    -o|--out) OUT="${2:-}"; shift 2 ;;
    --focus) FOCUS="${2:-}"; shift 2 ;;
    -h|--help) usage 0 ;;
    *) echo "unknown argument: $1" >&2; usage 1 ;;
  esac
done

[[ -n "$JOB" || -n "$FILE" ]] || usage 1

# ---------- gather transcript ----------
gather() {
  local src="$1"
  case "$src" in
    *.json)
      jq -r 'if type == "array" then . else .segments end
             | .[] | [(.speaker // "SPK"), (.start // 0), (.text // "")] | @tsv' "$src" \
        | awk -F'\t' '{ m = int($2 / 60); s = int($2 - m * 60); printf "[%d:%02d] %s: %s\n", m, s, $1, $3 }'
      ;;
    *.srt|*.vtt)
      awk '/^[[:space:]]*$/ { next }      # blank lines
           /^[0-9]+$/ { next }            # cue counters
           /-->/ { next }                 # timestamps
           /^WEBVTT/ { next }
           { print }' "$src"
      ;;
    *)
      cat "$src"
      ;;
  esac
}

if [[ -n "$JOB" ]]; then
  status=$(curl -sf "$MOSS_URL/api/jobs/$JOB" | jq -r '.status') \
    || die "cannot reach moss-transcribe at $MOSS_URL"
  [[ "$status" == "done" || "$status" == "waiting_review" ]] \
    || die "job $JOB status is '$status' — wait for transcription to finish"
  TRANSCRIPT=$(curl -sf "$MOSS_URL/api/jobs/$JOB/segments" \
    | jq -r '.segments[] | [(.speaker // "SPK"), (.start // 0), (.text // "")] | @tsv' \
    | awk -F'\t' '{ m = int($2 / 60); s = int($2 - m * 60); printf "[%d:%02d] %s: %s\n", m, s, $1, $3 }') \
    || die "failed to fetch segments for job $JOB"
  SOURCE="moss job $JOB"
else
  [[ -f "$FILE" ]] || die "no such file: $FILE"
  TRANSCRIPT=$(gather "$FILE")
  SOURCE="$FILE"
fi

[[ -n "$(echo "$TRANSCRIPT" | tr -d '[:space:]')" ]] || die "transcript is empty"

# ---------- ensure alias ----------
if [[ "$MODEL" == "meeting-summarizer" ]] && ! ollama show meeting-summarizer >/dev/null 2>&1; then
  MODELFILE="$(cd "$(dirname "$0")" && pwd)/meeting-summarizer.Modelfile"
  [[ -f "$MODELFILE" ]] || die "meeting-summarizer.Modelfile not found next to script"
  echo "creating ollama alias 'meeting-summarizer' from $MODELFILE" >&2
  ollama create meeting-summarizer -f "$MODELFILE" >&2
fi

# ---------- token estimate ----------
WORDS=$(echo "$TRANSCRIPT" | wc -w)
EST=$((WORDS * 4 / 3 + 1024))
echo "transcript: $WORDS words (~$EST tokens incl. prompt+output), source: $SOURCE" >&2

# ---------- VRAM pre-flight: probe-load, halve ctx until fully in VRAM ----------
SYS="You are an expert meeting-minutes assistant. Produce concise, factual minutes in Markdown with sections: ## Overview, ## Key Decisions, ## Action Items (checkbox list with owner in bold, 'unassigned' if unclear), ## Discussion Summary (grouped by topic, reference speakers by S-labels), ## Open Questions. Omit empty sections. Never invent facts, names, numbers, or decisions; quote exact figures. If a speaker names themselves, note the mapping (e.g. S02 (Maria)). Write in the same language as the transcript. If the transcript is not a meeting, say so and summarize its content instead."

probe() {
  local payload
  payload=$(jq -nc --arg m "$MODEL" --argjson c "$1" \
    '{model: $m, prompt: "hi", stream: false, keep_alive: "2m", options: {num_ctx: $c, num_predict: 1}}')
  curl -sf "$URL/api/generate" -d "$payload" | jq -e '.done_reason' >/dev/null
}

unload() {
  curl -sf "$URL/api/generate" \
    -d "$(jq -nc --arg m "$MODEL" '{model: $m, keep_alive: 0}')" >/dev/null 2>&1 || true
}

CHOSEN_CTX=""
BAILOUT=""
LAST=""
gb() { awk -v b="$1" 'BEGIN { printf "%.1f", b / 1e9 }'; }
for c in "$CTX" 16384 8192; do
  [[ "$c" -gt "$CTX" ]] && continue
  [[ "$c" == "$LAST" ]] && continue
  LAST=$c
  if [[ $EST -gt $((c - 512)) ]]; then
    BAILOUT="transcript (~$EST tokens) exceeds the $c-token context window — split the audio or summarize in parts"
    break
  fi
  echo "probing $MODEL at num_ctx=$c ..." >&2
  probe "$c" || die "ollama failed to load $MODEL (see journalctl -u ollama)"
  read -r SIZE VRAM < <(curl -sf "$URL/api/ps" \
    | jq -r '.models[0] | "\(.size) \(.size_vram)"' )
  OFFLOAD=$((SIZE - VRAM))
  if (( OFFLOAD < 700000000 )); then
    CHOSEN_CTX=$c
    if (( OFFLOAD > 50000000 )); then
      echo "loaded $(gb "$SIZE")GB ($(gb "$OFFLOAD")GB on CPU), num_ctx=$c" >&2
    else
      echo "loaded $(gb "$SIZE")GB, 100% in VRAM, num_ctx=$c" >&2
    fi
    break
  fi
  echo "spill: $(gb "$OFFLOAD")GB of $(gb "$SIZE")GB would land on CPU at num_ctx=$c" >&2
  unload
done

if [[ -z "$CHOSEN_CTX" ]]; then
  unload
  if [[ -n "$BAILOUT" ]]; then
    die "$BAILOUT"
  fi
  die "transcript (~$EST tokens) doesn't fit with available VRAM.
Try: (a) close VRAM-heavy apps (browsers, games), then re-run
     (b) $0 ... --model $FALLBACK_MODEL
     (c) enable flash attention + q8_0 KV cache (see modules/services/ollama.nix)"
fi

# ---------- summarize ----------
if [[ -n "$FOCUS" ]]; then
  USERMSG="Transcript:\n\n$TRANSCRIPT\n\nAdditional instruction: $FOCUS"
else
  USERMSG="Transcript:\n\n$TRANSCRIPT"
fi

PAYLOAD=$(jq -nc --arg m "$MODEL" --argjson c "$CHOSEN_CTX" --arg sys "$SYS" --arg user "$USERMSG" \
  '{model: $m, stream: true, keep_alive: "2m",
    options: {num_ctx: $c, temperature: 0.2, num_predict: 4096},
    messages: [{role: "system", content: $sys}, {role: "user", content: $user}]}')

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
if ! curl -sN "$URL/api/chat" -d "$PAYLOAD" -o "$TMP"; then
  unload
  die "ollama api request failed"
fi
if jq -e '.error' "$TMP" >/dev/null 2>&1; then
  unload
  die "ollama: $(jq -r '.error' "$TMP")"
fi

header="# Meeting Summary — ${SOURCE} — $(date '+%Y-%m-%d %H:%M')
_Model: ${MODEL}, context: ${CHOSEN_CTX} tokens, transcript: ~${WORDS} words_

"
if [[ -n "$OUT" ]]; then
  { printf '%s' "$header"; jq -rj 'select(.message.content) | .message.content' "$TMP"; echo; } | tee "$OUT"
else
  printf '%s' "$header"
  jq -rj 'select(.message.content) | .message.content' "$TMP"
  echo
fi
