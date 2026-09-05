#!/usr/bin/env bash
# ──────────────────────────────────────────────
# Waybar audio picker — switch default sink/source via rofi + wpctl
# usage: audio-picker.sh sink|source
# ──────────────────────────────────────────────
set -euo pipefail

kind="${1:-sink}"
case "$kind" in
  sink) section="Sinks"; prompt="󰗹  Output device" ;;
  source) section="Sources"; prompt="󰡨  Input device" ;;
  *) printf 'usage: %s [sink|source]\n' "$0" >&2; exit 1 ;;
esac

list_entries() {
  wpctl status | awk -v sec="$section" '
    /^(Audio|Video|Settings)/ { block = $1 }
    block == "Audio" && index($0, "─ " sec ":") { in_sec = 1; next }
    in_sec && !/^ │/ { in_sec = 0; block = "" }
    in_sec {
      line = $0
      sub(/^ │  */, "", line)
      if (line == "") next
      d = (line ~ /^\*/)
      sub(/^\* +/, "", line)
      id = substr(line, 1, index(line, ".") - 1)
      name = substr(line, index(line, ".") + 2)
      sub(/[[:space:]]+\[.*$/, "", name)
      sub(/[[:space:]]+$/, "", name)
      if (id ~ /^[0-9]+$/) printf "%s%s\t%s\n", (d ? "● " : "  "), name, id
    }
  '
}

if [[ "${2:-}" == "--list" ]]; then
  list_entries
  exit 0
fi

entries="$(list_entries)"
[[ -n "$entries" ]] || {
  notify-send -u low "Audio picker" "No ${kind}s found"
  exit 0
}

choice="$(printf '%s\n󰚌  Open mixer\t-\n' "$entries" \
  | rofi -dmenu -i -p "$prompt" -selected-row 0)" || exit 0

[[ -n "$choice" ]] || exit 0

id="${choice##*$'\t'}"
if [[ "$id" == "-" ]]; then
  pavucontrol &
elif [[ "$id" =~ ^[0-9]+$ ]]; then
  wpctl set-default "$id"
fi
