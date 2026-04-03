# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Multi-machine NixOS declarative configuration using Nix Flakes and Home Manager to manage four hosts — two Threadripper workstations and two Framework laptops.

## Common Commands

```bash
# Rebuild and switch to new system configuration
sudo nixos-rebuild switch --flake .#<hostname>

# Clean up old NixOS generations (keeps 30 generations, 30-day history)
./bin/trim-generations.sh

# Deploy script
./scripts/deploy.sh
```

## Architecture

### Hosts

- **nixos** — Threadripper + NVIDIA server (Gitea, Wallabag, Kokoro TTS, WhisperX)
- **nixos-ripper** — Threadripper + AMD RDNA 2 workstation (Ollama, ROCm)
- **framework-16** — Framework Laptop 16, AMD RDNA 3.5, Cosmic DE
- **framework-13** — Framework Laptop 13, AMD RDNA 3.5, ROCm + ComfyUI

### Directory Layout

- `hosts/<hostname>/default.nix` — Per-host NixOS system configuration
- `modules/common.nix` — Base config shared by all hosts
- `modules/desktop.nix` / `desktop-nvidia.nix` — GNOME desktop (AMD / NVIDIA)
- `modules/rocm-dev.nix` — Optional ROCm/HIP development toolchain
- `modules/services/` — Composable service modules with enable options
- `home/common.nix` — Shared Home Manager config (editors, LSPs, dotfiles)
- `home/<hostname>.nix` — Per-host Home Manager config
- `zshconfig` / `bashconfig` — Shell configs sourced by Home Manager
- `bin/` — Utility scripts
- `scripts/` — Deploy/rebuild/rollback helpers

### Key Details

- **Desktop**: GNOME on X11/Wayland
- **Editor**: Helix (hx) as primary, Neovim, VSCode
- **Languages**: Rust, Go, Zig, Python
- **Services**: Docker, Tailscale, SSH, PipeWire, Proton Drive sync
- **Networking**: Services exposed via Tailscale Serve for zero-config HTTPS
