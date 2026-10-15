#!/usr/bin/env bash
set -euo pipefail

# Turn off RGB on USB-attached devices (motherboard HID, NZXT, monitor).
# RAM/GPU RGB lives on the SMBus and is not touchable on this board —
# OpenRGB SMBus access hard-freezes it (see hosts/nixos-ripper/default.nix).

if compgen -G '/dev/i2c-*' > /dev/null; then
  echo "ERROR: /dev/i2c-* present (i2c-dev loaded) — OpenRGB SMBus access hard-freezes this board. Aborting." >&2
  exit 1
fi

failed=0
for entry in \
  "ASUS ROG ZENITH II EXTREME ALPHA:static" \
  "NZXT Smart Device V2:static" \
  "Alienware AW3423DWF:direct"
do
  device="${entry%%:*}"
  mode="${entry##*:}"
  if openrgb -d "$device" -m "$mode" -c 000000; then
    echo "off: $device"
  else
    echo "FAILED: $device" >&2
    failed=1
  fi
done
exit "$failed"
