# dotfiles

NixOS declarative configuration using **Nix Flakes** and **Home Manager** to manage four machines — two Threadripper workstations and two Framework laptops.

## Hosts

| Host | Hardware | GPU | Role |
|------|----------|-----|------|
| [nixos-ripper](hosts/nixos-ripper/) | AMD Threadripper | AMD RDNA 2 (ROCm) | AI/LLM workstation, emulation |
| [nixos](hosts/nixos/) | AMD Threadripper | NVIDIA | Server — Gitea, Wallabag, OpenClaw |
| [framework-16](hosts/framework-16/) | Framework Laptop 16 | AMD RDNA 3.5 | Portable dev machine |
| [framework-13](hosts/framework-13/) | Framework Laptop 13 | AMD RDNA 3.5 (ROCm) | Portable dev machine |

## Repository Structure

```
flake.nix                  # Flake entry — inputs, all host configs, devShells
hosts/
  nixos-ripper/            # Threadripper + AMD GPU workstation
  nixos/                   # Threadripper + NVIDIA server
  framework-16/            # Framework 16 laptop
  framework-13/            # Framework 13 laptop
modules/
  common.nix               # Base config shared by all hosts
  desktop.nix              # GNOME + AMD GPU desktop
  desktop-nvidia.nix       # GNOME + NVIDIA desktop
  rocm-dev.nix             # Optional ROCm/HIP development toolchain
  services/                # Reusable NixOS service modules
    gitea.nix              # Self-hosted git + Actions runner
    wallabag.nix           # Read-it-later service (nginx + PHP-FPM)
    syncthing.nix          # File synchronization
    ollama.nix             # LLM inference with ROCm
    vllm.nix               # vLLM quantized inference
    sunshine.nix           # Remote streaming
    retroarch.nix          # Emulation (GBA, PSX, NDS, Saturn, NES, SNES)
    proton-drive.nix       # rclone Proton Drive mount (template)
home/
  common.nix               # Shared Home Manager config — editors, LSPs, dotfiles
  nixos.nix                # nixos-ripper home — OpenClaw, RetroArch, custom services
  nixos-server.nix         # nixos server home — OpenClaw gateway + Telegram
  framework-16.nix         # Framework 16 home — Cosmic DE, dev tools, gaming
  framework-13.nix         # Framework 13 home — media, dev tools, gaming
zshconfig                  # Zsh config sourced by Home Manager
bashconfig                 # Bash config for server host
gitconfig                  # Git config (SSH signing, GPG)
bin/                       # Utility scripts
scripts/                   # Deploy/rebuild/rollback helpers
```

## Shared Modules

### `modules/common.nix`
Base configuration applied to every host:
- Nix Flakes and `nix-command` experimental features
- systemd-boot, Plymouth, latest kernel
- Core packages: helix, jq, gcc, cmake, docker-compose, tailscale, mosh
- PipeWire audio with GStreamer plugins
- Services: OpenSSH, Tailscale, fwupd, CUPS printing, geoclue2
- User `jay` in wheel, docker, video, render groups
- 1Password (GUI + CLI), Steam, Docker, nix-ld

### `modules/desktop.nix` (AMD)
GNOME desktop with X11 amdgpu driver, GDM, PipeWire, Wayland support.

### `modules/desktop-nvidia.nix`
GNOME desktop with NVIDIA proprietary drivers, beta Vulkan, hardware cursor workaround.

### `modules/rocm-dev.nix`
Optional module — ROCm/HIP toolchain with configurable GPU architecture target.

## Service Modules

All under `modules/services/`, each with `enable` and configuration options:

- **gitea** — Actions runner with Docker containers, cache server, resource limits
- **wallabag** — Read-it-later with SQLite/PostgreSQL, Redis caching, nginx subpath routing, PHP-FPM
- **syncthing** — File sync with configurable user and data directory
- **ollama** — LLM server with ROCm GPU acceleration, Open-WebUI
- **vllm** — Quantized LLM inference with ROCm
- **sunshine** — Remote desktop streaming
- **retroarch** — Emulation platform with pre-configured cores

## Home Manager

All hosts share `home/common.nix` which provides:
- Development: Node.js 22, direnv, starship prompt, vim, neovim
- Language servers: TypeScript, JSON, YAML, Nix (nil, nixd), Markdown, Dockerfile
- Desktop apps: VS Code, Chrome, Slack, Discord, Obsidian
- GNOME extensions: Tailscale quick settings, Pano clipboard manager
- Git config with SSH commit signing
- Dotfiles: `.zshrc` (zshconfig), `.gitconfig` (gitconfig)

Per-host home configs layer on additional packages and services. See each host's README for details.

## Usage

### Rebuild and switch
```bash
# From the repo root
sudo nixos-rebuild switch --flake .#<hostname>
```

### Deploy script
```bash
./scripts/deploy.sh
```

### Clean old generations
```bash
./bin/trim-generations.sh
```

### Set up Tailscale Serve
```bash
./bin/setup-tailscale-serve.sh
```

## Networking

All services are exposed via **Tailscale Serve** for zero-config HTTPS:

| Port | Service |
|------|---------|
| 443 | nginx (static site + Wallabag) |
| 3000 | Gitea |
| 8443 | OpenClaw gateway |
| 8182 | Playwright MCP |
| 8444 | IronClaw |
| 9000 | RustFS (S3 API) |

## Flake Inputs

- `nixpkgs` — NixOS unstable
- `home-manager` — follows nixpkgs
- `nix-openclaw` — AI agent gateway (self-hosted Gitea)

## Dev Shells

- `whisperx` — WhisperX speech recognition environment with CUDA toolkit
