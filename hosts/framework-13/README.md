# framework-13

Framework Laptop 13 (AMD 7735U) with RDNA 3.5 GPU and ROCm — portable dev and media machine.

## Hardware

- **CPU**: AMD 7735U
- **GPU**: AMD RDNA 3.5 (gfx1150) with ROCm enabled
- **Storage**: NVMe with swap partition
- **Connectivity**: Thunderbolt 3
- **Extras**: LED matrix, fingerprint reader
- **Lid behavior**: suspend on close
- **Kernel params**: `ttm.pages_limit=22369536`, `button.lid_init_state=open`

## Desktop

GNOME on X11/Wayland via `modules/desktop.nix` (amdgpu driver) with polkit, sudo, xss-lock.

## Framework-Specific

- LED matrix udev rules
- `framework-tool` and `via` for hardware management

## Home Manager Packages

### Development
- code-cursor, zed-editor, Android Studio
- PostgreSQL, espup, elf2uf2-rs (embedded)
- awscli2, Bruno

### Terminal
- Ghostty, Warp, Nushell, Helvum (PipeWire GUI)

### Media
- Cider (Apple Music), OBS Studio, Audacity, LM Studio
- LibreOffice

### Gaming
- Cemu (Wii U), Ryujinx (Switch), Bottles (Wine)
- Heroic game launcher

### Hardware
- framework-tool, via, dualsensectl
- nvtop (AMD), system76-keyboard-configurator

### Desktop
- GNOME resource-monitor + wireless-hid extensions
- GNOME Boxes

## Notable Config

- **ROCm** enabled by default (`rocm-dev.enable = true`)
- **ROCm architecture**: gfx1150

## Build

```bash
sudo nixos-rebuild switch --flake .#framework-13
```
