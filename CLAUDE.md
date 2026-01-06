# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a NixOS declarative configuration repository using Nix Flakes and Home Manager to manage system and user configurations for a Framework Laptop 16 with AMD GPU.

## Common Commands

```bash
# Rebuild and switch to new system configuration
sudo nixos-rebuild switch -I nixpkgs=<nixpkgs> -I /etc/nixos

# Clean up old NixOS generations (keeps 30 generations, 30-day history)
./bin/trim-generations.sh
```

## Architecture

### Configuration Layers

- **configuration.nix** - Main NixOS system configuration (hardware, services, desktop)
- **amd_configuration.nix** - Alternative AMD-specific system configuration
- **homemanager.nix** - Home Manager user-level configuration (packages, dotfiles, programs)
- **hardware-configuration.nix** - Auto-generated hardware settings

### Custom Nix Modules (`nix-modules/`)

Composable service modules with enable options:
- `ollama.nix` - LLM service with AMD ROCm GPU acceleration
- `sunshine.nix` - Remote streaming service
- `gitea.nix` - Self-hosted git server with CI/CD runners
- `programs.nix` - Custom system programs
- `hostname.nix` - Hostname settings

### Shell Configuration

- **zshconfig** / **bashconfig** - Shell configs sourced by Nix
- Environment variables set: PATH extensions (.cargo, go, deno, .local, .fly), HSA_OVERRIDE_GFX_VERSION for AMD GPU, EDITOR=hx
- ESP32/Xtensa toolchain via `export-esp.sh`

### Key Hardware/Software Details

- **GPU**: AMD RDNA 3 (gfx1030) with ROCm support
- **Desktop**: GNOME on X11/Wayland
- **Editor**: Helix (hx) as primary, Neovim, VSCode
- **Languages**: Rust, Go, Zig, Python, Deno
- **Services**: Docker, Tailscale, SSH, PipeWire, Proton Drive sync
