#!/usr/bin/env bash
# ──────────────────────────────────────────────
# Waybar Tailscale module — status, tooltip, toggle
# Emits waybar JSON (return-type: json)
# ──────────────────────────────────────────────
set -euo pipefail

status="$(tailscale status --json 2>/dev/null)" || status=""

if [[ "${1:-}" == "toggle" ]]; then
  state="$(jq -r '.BackendState // "Stopped"' <<<"$status")"
  if [[ "$state" == "Running" ]]; then
    tailscale down 2>/dev/null || pkexec tailscale down
  else
    tailscale up 2>/dev/null || pkexec tailscale up
  fi
  exec "$0"
fi

if [[ -z "$status" ]]; then
  jq -n '{text: "󰛳  ?", tooltip: "Tailscale\n tailscaled unreachable", class: "error"}'
  exit 0
fi

jq '
  def esc: gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;");
  . as $s |
  ($s.BackendState // "Unknown") as $state |
  ([ $s.Peer[]? ]) as $peers |
  ([ $peers[] | select(.Online == true) ]) as $online |
  (($s.Self.ExitNodeStatus? // {}).ID // $s.Self.ExitNodeID // null) as $exitId |
  (if $exitId == null or $exitId == ""
   then null
   else (($peers[]? | select(.ID == $exitId)
           | (((.DNSName // "") | split(".")[0] | select(. != "")) // .HostName)) // "exit node") end) as $exit |
  if $state != "Running" then {
    text: "󰛳  " + (if $state == "Stopped" then "Off"
                   elif $state == "NeedsLogin" then "Login"
                   else ($state | esc) end),
    class: "stopped",
    tooltip: "Tailscale\nstate: " + ($state | esc)
  } else {
    text: "󰛳 " + (if $exit != null then " 󰌾 " else "  " end)
          + (if ($peers | length) == 0 then ""
             else (($online | length) | tostring) + "/" + (($peers | length) | tostring) end),
    class: (if $exit != null then "exit-node" else "up" end),
    tooltip: ([
      "󰛳  <b>" + (($s.CurrentTailnet.Name // "tailnet") | esc) + "</b>   <span color=\"#a6adc8\">" + ($s.Self.TailscaleIPs[0] // "") + "</span>",
      "Peers: " + (($online | length) | tostring) + " online / " + (($peers | length) | tostring),
      "Exit node: " + (if $exit != null then "<b>" + ($exit | esc) + "</b>"
                       else "<span color=\"#a6adc8\">none</span>" end)
    ] + ([ $online[]
           | "  " + (((.DNSName // "") | split(".")[0] | select(. != "")) // .HostName // "" | esc)
              + "  <span color=\"#a6adc8\">" + (.TailscaleIPs[0] // "?") + "</span>" ]
         ) | join("\n"))
  } end' <<<"$status"
