# framework-16

Framework Laptop 16 with AMD Ryzen HX170 and RDNA 3.5 GPU — portable development and gaming machine.

## Hardware

- **CPU**: AMD Ryzen HX170
- **GPU**: AMD RDNA 3.5 (gfx1150)
- **Storage**: NVMe with separate `/home/jay` partition
- **Connectivity**: Thunderbolt 3
- **Extras**: LED matrix (USB), QMK keyboard, fingerprint reader
- **Power management**: enabled

## Desktop

GNOME on X11/Wayland via `modules/desktop.nix` (amdgpu driver).

## Framework-Specific

- LED matrix control via udev rules (vendor 32ac, product 0020)
- `framework-tool` and `inputmodule-control` for hardware management
- QMK keyboard firmware support
- Custom geolocation via BeaconDB API

## Home Manager Packages

### Development
- Go (gopls), Zig, PostgreSQL, OpenTofu
- Taplo (TOML), espup + elf2uf2-rs (embedded)
- code-cursor, zed-editor, Android Studio
- awscli2, Bruno, Postman

### Terminal
- Ghostty, Warp, Nushell, Alacritty

### Gaming
- Cemu (Wii U), Ryujinx (Switch), Bottles (Wine)
- Heroic game launcher

### Hardware
- framework-tool, inputmodule-control, via, dualsensectl
- nvtop (AMD), system76-keyboard

### Desktop
- GNOME resource-monitor extension
- GNOME Boxes (VMs), gnome-firmware
- Cosmic Desktop (full stack — compositor, panel, terminal, editor, settings, files, etc.)

## Notable Config

- **HSA_OVERRIDE_GFX_VERSION**: 11.0.2
- **libvirt/KVM** for virtual machines
- **Cosmic Desktop** full suite installed for testing/future migration

## Build

```bash
sudo nixos-rebuild switch --flake .#framework-16
```
