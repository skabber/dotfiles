#!/usr/bin/env bash
set -euo pipefail

if ! command -v hyprctl >/dev/null 2>&1; then
  echo '{"text":"󰹑  n/a","class":"error","tooltip":"hyprctl not found"}'
  exit 0
fi

MON="$(hyprctl monitors all -j)"
INT_RE='^(eDP|LVDS|DSI)-'
VIRT='(.make == "" and .model == "" and .description == "")'

jq_str() { local filter=$1; shift; jq -r "$filter" "$@" <<<"$MON"; }

INT="$(jq_str "[.[] | select($VIRT | not) | select(.name | test(\"$INT_RE\")) | .name] | first // empty")"
INT_ON="$(jq_str '[.[] | select(.name == $n) | select(.disabled | not) | .name] | first // empty' --arg n "$INT")"

EXTS_ALL=(); EXTS_ON=(); VIRTS=()
while IFS= read -r n; do [[ -n $n ]] && EXTS_ALL+=("$n"); done \
  < <(jq_str "[.[] | select($VIRT | not) | select((.name | test(\"$INT_RE\")) | not) | .name] | .[]")
while IFS= read -r n; do [[ -n $n ]] && EXTS_ON+=("$n"); done \
  < <(jq_str "[.[] | select($VIRT | not) | select((.name | test(\"$INT_RE\")) | not) | select(.disabled | not) | .name] | .[]")
while IFS= read -r n; do [[ -n $n ]] && VIRTS+=("$n"); done \
  < <(jq_str "[.[] | select($VIRT) | .name] | .[]")

scale_of() { jq -r --arg n "$1" '[.[] | select(.name == $n) | .scale] | first // 1' <<<"$MON"; }

mon_enable() { hyprctl keyword monitor "$1,preferred,auto,$(scale_of "$1")" >/dev/null; }
mon_disable() { hyprctl keyword monitor "$1,disable" >/dev/null; }
mon_mirror() { hyprctl keyword monitor "$1,preferred,auto,1,mirror,$INT" >/dev/null; }

apply_mode() {
  local mode=$1 e
  case $mode in
    extend)
      [[ -n $INT ]] && mon_enable "$INT"
      for e in "${EXTS_ALL[@]}"; do mon_enable "$e"; done
      ;;
    internal)
      for e in "${EXTS_ALL[@]}"; do mon_disable "$e"; done
      [[ -n $INT ]] && mon_enable "$INT"
      ;;
    external)
      [[ -n $INT ]] && mon_disable "$INT"
      for e in "${EXTS_ALL[@]}"; do mon_enable "$e"; done
      ;;
    mirror)
      [[ -n $INT ]] && mon_enable "$INT"
      [[ ${#EXTS_ALL[@]} -gt 0 ]] && mon_mirror "${EXTS_ALL[0]}"
      ;;
  esac
}

status() {
  local real virt text tooltip count class
  # hide the pill entirely when there's nothing but the internal panel
  if (( ${#EXTS_ALL[@]} == 0 && ${#VIRTS[@]} == 0 )); then
    jq -nc '{text: "", tooltip: "", class: "hidden"}'
    return
  fi
  real="$(jq_str "[.[] | select($VIRT | not) | select(.disabled | not) | .name] | join(\" + \")")"
  virt="$(jq_str "[.[] | select($VIRT) | select(.disabled | not) | \"~\" + .name] | join(\" + \")")"
  text="$real"
  [[ -n $virt ]] && text="${real:+$real + }$virt"
  tooltip="$(jq_str "[.[] | if $VIRT then \"\(.name) — \(.width)x\(.height)@\(.refreshRate | round)Hz · virtual\"
    elif .disabled then \"\(.name) — disabled\"
    else \"\(.name) — \(.width)x\(.height)@\(.refreshRate | round)Hz · scale \(.scale) · \(.x),\(.y)\" end] | join(\"\n\")")"
  count="$(jq_str "[.[] | select($VIRT | not) | select(.disabled | not)] | length")"
  class="single"
  (( count > 1 )) && class="multi"
  [[ -n $INT && -z $INT_ON && count -gt 0 ]] && class="external"
  [[ ${#VIRTS[@]} -gt 0 ]] && class="virtual"
  jq -nc --arg t "󰹑  $text" --arg tt "$tooltip" --arg c "$class" \
    '{text: $t, tooltip: $tt, class: $c}'
}

cycle() {
  if [[ ${#EXTS_ALL[@]} -eq 0 ]]; then
    notify-send -t 2000 "Screens" "No external display connected"
    return
  fi
  if [[ -n $INT_ON && ${#EXTS_ON[@]} -gt 0 ]]; then
    apply_mode internal
    notify-send -t 2000 "Screens" "Internal only"
  elif [[ -n $INT_ON ]]; then
    apply_mode external
    notify-send -t 2000 "Screens" "External only"
  else
    apply_mode extend
    notify-send -t 2000 "Screens" "Extend"
  fi
}

menu() {
  local opts=() choice v
  if [[ ${#EXTS_ALL[@]} -gt 0 ]]; then
    opts+=("Extend" "Internal only" "External only" "Mirror")
  fi
  opts+=("Add virtual screen")
  [[ ${#VIRTS[@]} -gt 0 ]] && opts+=("Remove virtual screens")
  choice=$(printf '%s\n' "${opts[@]}" | rofi -dmenu -p "Screens" -i) || return
  case $choice in
    Extend) apply_mode extend ;;
    "Internal only") apply_mode internal ;;
    "External only") apply_mode external ;;
    Mirror) apply_mode mirror ;;
    "Add virtual screen")
      hyprctl output create headless >/dev/null
      ;;
    "Remove virtual screens")
      for v in "${VIRTS[@]}"; do hyprctl output remove "$v" >/dev/null; done
      ;;
    *) return ;;
  esac
  notify-send -t 2000 "Screens" "$choice"
}

case ${1:-status} in
  status) status ;;
  cycle) cycle ;;
  menu) menu ;;
esac
