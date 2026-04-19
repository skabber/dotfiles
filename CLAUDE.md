# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Multi-machine NixOS declarative configuration using Nix Flakes and Home Manager to manage four hosts — two Threadripper workstations and two Framework laptops.

## Common Commands

```bash
# Rebuild and switch (preferred — handles hostname automatically)
./scripts/rebuild.sh [--upgrade] [hostname]

# Rebuild with flake update (upgrades all inputs first)
./scripts/rebuild.sh --upgrade

# Quick rollback to previous generation
./scripts/rollback.sh

# Deploy script (creates /etc/nixos symlink, prompts before switching)
./scripts/deploy.sh

# Clean up old NixOS generations (keeps 30 generations, 30-day history)
./bin/trim-generations.sh

# Re-apply Tailscale Serve port mappings after config changes
./bin/setup-tailscale-serve.sh
```

## Architecture

### Hosts

| Flake name | Hostname on system | Hardware | Role |
|---|---|---|---|
| `nixos` | nixos | Threadripper + NVIDIA | Server (Gitea, Wallabag, Kokoro TTS, WhisperX) |
| `nixos-ripper` | nixos-ripper | Threadripper + RDNA 2 | Workstation (Ollama, ROCm, vLLM) |
| `framework-13` | nixos-framework-13 | Framework 13 + RDNA 3.5 | Dev laptop (ComfyUI, ROCm) |
| `framework-16` | nixos-framework | Framework 16 + RDNA 3.5 | Dev laptop (Cosmic DE) |

> The flake name (`.#nixos-ripper`) and the system hostname differ for framework hosts — keep this in mind when targeting builds.

### Module Composition

All hosts import `modules/common.nix` (base system) plus optional modules:

- `modules/desktop-base.nix` — GNOME + GDM + PipeWire (shared base)
- `modules/desktop.nix` — extends desktop-base with `amdgpu` driver
- `modules/desktop-nvidia.nix` — extends desktop-base with proprietary NVIDIA + vulkan_beta
- `modules/rocm-dev.nix` — ROCm/HIP toolchain; exposes `rocm-dev.enable` and `rocm-dev.architecture` options (gfx1030 for nixos-ripper, gfx1150 for framework-13/16)
- `modules/services/*.nix` — each service is a NixOS module with an `enable` option and service-specific options (see each file for available options)

The `mkHost` helper in `flake.nix` wires Home Manager into every host with a shared `specialArgs` and the `jay` user account.

### Services Architecture

Services use different deployment patterns:

- **Docker Compose**: Gitea Actions runner, Kokoro FastAPI TTS
- **NixOS services**: Gitea, Wallabag (PHP/nginx), Syncthing, Ollama, Open-WebUI
- **Python venvs** (set up by one-shot systemd units): WhisperX (`~/Projects/whisperx-service`), ComfyUI
- **Systemd user services** (on `nixos` host): `ironclaw`, `playwright-mcp`, `rustfs` — source dirs expected at `~/Projects/<name>`

External services that depend on project directories (`whisperx-service`, `ironclaw`, `rustfs`) are not managed by Nix — only their systemd wrappers are.

### Networking

All external services are exposed via Tailscale Serve at `nixos.tail69fe1.ts.net`. Run `./bin/setup-tailscale-serve.sh` to (re)configure the port mappings. Key ports: Gitea :3000, Wallabag at /wallabag/ (nginx), WhisperX :8000, Ollama/Open-WebUI :8443, Playwright MCP :8182, Kokoro TTS :8880, RustFS :9000.

### Key Details

- **Channel**: `nixos-unstable` (all hosts track unstable)
- **Flake inputs**: `home-manager`, `kokoro-fastapi-nix`, `wallbag-rust`, `google-workspace-cli`
- **Editor**: Helix (`hx`) as primary; Neovim, VS Code, Zed also installed
- **Shell**: Zsh with Starship, direnv/nix-direnv, zoxide, fzf, zsh-syntax-highlighting
- **Git signing**: GPG/OpenPGP (configured in `home/common.nix` and `gitconfig`)
- **Binary caches**: `nix-community.cachix.org`, `cuda-maintainers.cachix.org` (configured on `nixos` host)
