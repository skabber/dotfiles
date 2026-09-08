#!/usr/bin/env bash
# ──────────────────────────────────────────────
# Waybar bluetooth picker — connect/disconnect known devices via rofi
# usage: bluetooth-picker.sh [power]   (power = toggle controller on/off)
# ──────────────────────────────────────────────
set -euo pipefail

toggle_power() {
  if bluetoothctl show | grep -q 'Powered: yes'; then
    bluetoothctl power off >/dev/null 2>&1 || true
    notify-send -u low "Bluetooth" "Controller off"
  else
    bluetoothctl power on >/dev/null 2>&1 || true
    notify-send -u low "Bluetooth" "Controller on"
  fi
  exit 0
}

[[ "${1:-}" == "power" ]] && toggle_power

list_entries() {
  while read -r _ mac name; do
    [[ -n "$mac" ]] || continue
    if bluetoothctl info "$mac" | grep -q 'Connected: yes'; then
      printf '󰂱  %s\t%s\n' "$name" "$mac"
    else
      printf '󰂲  %s\t%s\n' "$name" "$mac"
    fi
  done < <(bluetoothctl devices)
}

if [[ "${1:-}" == "--list" ]]; then
  list_entries
  exit 0
fi

entries="$(list_entries)"
[[ -n "$entries" ]] || {
  notify-send -u low "Bluetooth" "No known devices"
  exit 0
}

choice="$(printf '%s\n󰚌  Power on/off\t-\n' "$entries" \
  | rofi -dmenu -i -p '󰂯  Bluetooth' -selected-row 0)" || exit 0

[[ -n "$choice" ]] || exit 0

mac="${choice##*$'\t'}"
if [[ "$mac" == "-" ]]; then
  toggle_power
fi

name="${choice%%$'\t'*}"
name="${name#*  }"

if bluetoothctl info "$mac" | grep -q 'Connected: yes'; then
  bluetoothctl disconnect "$mac" >/dev/null 2>&1 || true
  notify-send -u low "Bluetooth" "Disconnected $name"
else
  bluetoothctl power on >/dev/null 2>&1 || true
  if bluetoothctl connect "$mac" >/dev/null 2>&1; then
    notify-send -u low "Bluetooth" "Connected $name"
  else
    notify-send -u critical "Bluetooth" "Failed to connect to $name"
  fi
fi
