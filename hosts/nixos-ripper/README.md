# nixos-ripper

AMD Threadripper workstation with RDNA 2 GPU — primary AI/LLM and development machine.

## Hardware

- **CPU**: AMD Threadripper (KVM-enabled)
- **GPU**: AMD RDNA 2 (gfx1030) with ROCm acceleration
- **Storage**: NVMe
- **Swap**: 32GB swap file
- **Peripherals**: Razer (openrazer + polychromatic), YubiKey/U2F, fingerprint reader (Goodix)

## Desktop

GNOME on X11/Wayland via `modules/desktop.nix` (amdgpu driver).

## Services

| Service | Description |
|---------|-------------|
| **Ollama** | LLM inference with ROCm, Open-WebUI, flash attention |
| **vLLM** | Quantized LLM inference with custom ROCm overlay |
| **RetroArch** | Emulation — GBA, PSX, NDS, Saturn, NES, SNES |
| **Syncthing** | File sync on port 8384 |
| **Roon Server** | Audio server (firewall opened) |
| **LACT** | AMD GPU control daemon |

## User Services (systemd)

| Service | Description |
|---------|-------------|
| **openclaw-gateway** | AI agent gateway on port 18789 |
| **playwright-mcp** | Browser automation MCP server on port 8182 |
| **ironclaw** | AI assistant service |
| **rustfs** | S3-compatible object storage at 127.0.0.1:9000 |

## Home Manager Packages

- **Terminal**: Warp, Alacritty
- **Hardware**: system76-keyboard-configurator
- **AI/Automation**: playwright-mcp, OpenClaw (Telegram integration, multi-model)

## OpenClaw Configuration

- Telegram bot (ID 8105954598, require mentions in groups)
- Primary model: Gemini 2.5 Pro
- Fallbacks: Mistral Large, Gemini 2.0 Flash
- Heartbeat: Gemini 2.5 Flash Lite (30min interval)
- Sub-agents: Mistral Small (8 concurrent)
- Gateway: loopback binding with Tailscale auth + control UI

## Notable Config

- **Kernel modules**: iwlwifi, ath12k, snd-aloop
- **inotify limit**: 2,000,000 watches
- **GPU override**: HSA_OVERRIDE_GFX_VERSION=10.3.0
- **vLLM overlay**: Pins outlines-core version, scoped to avoid breaking other Python packages
- **Docker + Tailscale + ProtonVPN** enabled

## Build

```bash
sudo nixos-rebuild switch --flake .#nixos-ripper
```
