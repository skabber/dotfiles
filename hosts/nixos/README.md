# nixos

AMD Threadripper server with NVIDIA GPU — runs Gitea, Wallabag, and OpenClaw behind Tailscale Serve.

## Hardware

- **CPU**: AMD Threadripper
- **GPU**: NVIDIA (beta Vulkan, proprietary drivers)
- **Storage**: ext4
- **Hostname**: `nixos.tail69fe1.ts.net`

## Desktop

GNOME on X11/Wayland via `modules/desktop-nvidia.nix` (nvidia driver, hardware cursor workaround).

## Services

| Service | Port | Description |
|---------|------|-------------|
| **Gitea** | 3000 | Self-hosted git with Actions runner |
| **Wallabag** | — | Read-it-later at `/wallabag/` (nginx subpath) |
| **Syncthing** | 8384 | File synchronization |
| **nginx** | 80 | Static site + Wallabag reverse proxy |
| **Tailscale Serve** | 443 | HTTPS termination for all services |
| **Redis** | 6380 | Caching for Wallabag |
| **Sunshine** | — | Remote streaming (disabled by default) |

### Gitea Details

- Actions runner with Docker (Ubuntu images)
- Cache server on port 8088
- Resource limits: 32GB RAM, 32 CPUs
- Dummy mailer (no email)
- Docker insecure registry configured for local Gitea

### Wallabag Details

- SQLite backend with Redis caching
- PHP 8.2 (FPM, 16 child processes)
- Nginx subpath routing with asset URL fix
- Patched AppKernel.php for absolute paths
- Systemd cache-clear on boot

## Home Manager

- **Shell**: Bash (sources `~/.bash_profile.local`)
- **OpenClaw**: Telegram integration, multi-model AI gateway
  - Loopback gateway with Tailscale auth
  - Control UI at `~/.openclaw/control-ui`

## Networking

All services proxied through Tailscale Serve:

| External | Internal |
|----------|----------|
| `:443` | nginx (static + Wallabag) |
| `:3000` | Gitea |
| `:8443` | OpenClaw gateway |

## Security

- YubiKey/U2F authentication (login + sudo)
- GNOME Keyring with PAM integration
- GnuPG agent with SSH support
- Linger enabled for user services over SSH

## Notable Config

- **Flatpak** support enabled
- **NTFS** filesystem support
- **Chrome symlink** at `/opt/google/chrome` for Playwright
- **Binary caches**: cache.nixos.org, nix-community.cachix.org, cuda-maintainers.cachix.org

## Build

```bash
sudo nixos-rebuild switch --flake .#nixos
```
