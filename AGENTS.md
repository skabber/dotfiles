# AGENTS.md

This guide provides instructions and conventions for AI agents working in this repository. It outlines the core workflows, environment, and code style standards for this NixOS dotfiles configuration.

## System Overview
- **OS**: NixOS (using Flakes and Home Manager)
- **Hardware Targets**: 
  - Framework Laptop 16 (AMD RDNA 3, `gfx1030`/`gfx1150`)
  - Framework Laptop 13
  - Desktops with NVIDIA GPUs (`desktop-nvidia.nix`)
- **Editor**: Helix (`hx`) is the primary editor.
- **Languages**: Nix, Shell, Rust, Go, Zig, Python, Deno.
- **User**: `jay`

## Repository Structure
```
~/dotfiles/
├── flake.nix                    # Main flake entry point
├── hosts/                       # Machine-specific configs (framework-16, framework-13, nixos, nixos-ripper)
├── modules/                     # Shared NixOS modules (common.nix, desktop.nix, desktop-nvidia.nix, rocm-dev.nix)
│   └── services/                # Custom services (gitea, ollama, comfyui, proton-drive, etc.)
├── home/                        # Home Manager configs (common.nix, [hostname].nix)
└── scripts/                     # Deployment scripts (rebuild.sh, deploy.sh, rollback.sh)
```

## Core Commands

### System Rebuild & Deployment
```bash
./scripts/rebuild.sh              # Rebuild and switch (current hostname)
./scripts/rebuild.sh --upgrade    # Rebuild with flake update
./scripts/rebuild.sh framework-16 # Rebuild specific host
./scripts/deploy.sh               # Build without switching (validation)
./scripts/rollback.sh             # Rollback to previous generation
```

### Validation & Testing
```bash
nix flake check                   # Verify flake syntax and evaluation
nix build .#nixosConfigurations.framework-16.config.system.build.toplevel  # Build host config
nix eval .#nixosConfigurations.framework-16.config.services.openssh.enable # Quick validation
nix search nixpkgs <package>      # Search for package
```

## Code Style & Conventions

### Nix Formatting
- **Indentation**: 2 spaces (strictly no tabs).
- **Filenames**: `kebab-case.nix` (e.g., `rocm-dev.nix`).
- **Attributes**: `camelCase` for attribute names (e.g., `stateVersion`).
- **Imports**: Relative paths from file location (e.g., `../../modules/common.nix`).
- **Comments**: Use `#` for line comments. Add brief descriptions at module top.

### Custom Service Modules (`modules/services/*.nix`)
When adding or modifying a service module, follow this pattern:
1. Wrap the module configuration in an enable option using `lib.mkEnableOption`.
2. Define custom options using `lib.mkOption` and appropriate `lib.types` (e.g., `types.port`, `types.str`).
3. Use `lib.mkIf cfg.enable { ... }` to conditionally apply the `systemd.services` and environment configurations.
4. Ensure appropriate ports are opened in `networking.firewall.allowedTCPPorts` only when the service is enabled.

### Shell Scripts
- **Shebang**: `#!/usr/bin/env bash`
- **Safety**: Always include `set -euo pipefail`
- **Formatting**: 2-space indentation, `kebab-case.sh` naming

### Git & Commits
- **Messages**: Concise, focus on "why". Follow Conventional Commits format (`feat: ...`, `fix: ...`, `chore: ...`).

## Hardware & Environment Specifics

### GPU Support
- **AMD (RDNA 3):** Primary support for `gfx1030`/`gfx1150`. AI services like Ollama often require `HSA_OVERRIDE_GFX_VERSION=10.3.0` exported in systemd services or shell environments. (See `modules/rocm-dev.nix`).
- **NVIDIA:** Handled via `modules/desktop-nvidia.nix`, utilizing `vulkan_beta` packages and specific Wayland overrides (`WLR_NO_HARDWARE_CURSORS="1"`).

## AI Assistant Instructions (Gotchas & Patterns)

- **Secrets:** DO NOT commit raw secrets to the repository. Rely on tools like `sops-nix` if secret management is introduced, or local `.env` files.
- **Flake Immutability:** When modifying shell scripts referenced by Nix configurations, remember to commit them (or stage them via `git add`) so the Flake daemon can read the updated content.
- **Hardware Config:** Never manually edit `hosts/*/hardware-configuration.nix` directly; they are auto-generated.
- **Validation First:** After making structural changes, always run `nix flake check` or execute `./scripts/deploy.sh` to ensure the flake evaluates successfully.
- **Home Manager:** The `jay` user is the primary target for user packages and dotfiles. Shared modules exist in `home/common.nix`.