# AGENTS.md

This guide is for agentic coding agents (like yourself) working in this repository. It outlines the core workflows, environment, and code style standards for this NixOS dotfiles configuration.

## System Overview
- **OS**: NixOS (using Flakes and Home Manager)
- **Hardware**: Framework Laptop 16 (AMD RDNA 3, gfx1030/gfx1150)
- **Editor**: Helix (`hx`) is the primary editor.
- **Languages**: Nix, Shell, Rust, Go, Zig, Python, Deno.

## Core Commands

### System Rebuild & Deployment
Always use the provided scripts for system operations to ensure flake consistency.

```bash
# Update flake and switch to new configuration (current hostname)
./scripts/rebuild.sh

# Build configuration without switching (useful for validation)
./scripts/deploy.sh

# Rollback to the previous generation
./scripts/rollback.sh

# Clean up old generations (retains 30 generations/30 days)
./bin/trim-generations.sh
```

### Manual Nix Operations
```bash
# Verify flake syntax and evaluation
nix flake check

# Build a specific host configuration (e.g., framework-16)
nix build .#nixosConfigurations.framework-16.config.system.build.toplevel

# Run a specific check or test (if defined in flake.nix)
nix flake check -L --filter "checks/x86_64-linux/some-check"

# Update specific flake input
nix flake lock --update-input <input_name>

# Search for a package in nixpkgs
nix search nixpkgs <package_name>
```

### Development Shells
Some directories may have local `flake.nix` or specific dev shells.
```bash
# Enter the whisperx development shell
nix develop .#whisperx
```

## Code Style & Conventions

### Nix Formatting
- **Indentation**: 2 spaces (strictly no tabs).
- **Filenames**: Use `kebab-case.nix` (e.g., `amdgpu-config.nix`).
- **Attributes**: Use `camelCase` for Nix attribute names (e.g., `stateVersion`).
- **Imports**: Prefer absolute paths relative to the flake root or clear relative paths.
- **Cleanliness**: Avoid trailing whitespace and ensure a final newline.

### Nix Module Structure
Follow the standard NixOS module pattern. Use `options` and `config` to make services composable:
```nix
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.custom-service;
in
{
  options.services.custom-service = {
    enable = mkEnableOption "Custom Service";
    # Add other options using lib.types
    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Port to listen on";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ pkgs.some-package ];
    # Implementation logic using config and pkgs
    services.nginx.virtualHosts."localhost" = {
      locations."/".proxyPass = "http://127.0.0.1:${toString cfg.port}";
    };
  };
}
```

### Types and Options
- Use `lib.types` for all options (e.g., `types.str`, `types.bool`, `types.enum`, `types.attrsOf`).
- Provide sensible defaults for optional settings.
- Always include `description` for new options to aid in configuration.

### Shell Scripts
- **Shebang**: Use `#!/usr/bin/env bash` or `#!/usr/bin/env sh`.
- **Safety**: Always include `set -euo pipefail`.
- **Formatting**: Use 2-space indentation.
- **Naming**: `kebab-case.sh`.

### Error Handling
- **Nix**: Use `assert` or `throw` for critical configuration-level errors.
- **Shell**: Rely on `set -e` and check exit codes for critical operations.
- **Validation**: Use `nix flake check` to catch syntax errors and evaluation failures.

### Git & Commits
- **Messages**: Concise, focus on "why" (e.g., `feat: add ollama module with ROCm support`).
- **Scope**: Avoid massive commits; separate system changes from home-manager changes where possible.
- **Style**: Follow Conventional Commits where applicable (feat, fix, refactor, docs, etc.).

## Key Hardware/GPU Support
This repo targets AMD RDNA 3 hardware (Framework Laptop 16). When modifying GPU-related modules (like `ollama.nix` or `amdgpu.nix`):
- Ensure `HSA_OVERRIDE_GFX_VERSION=10.3.0` (or appropriate) is set for ROCm compatibility.
- Prefer `amdgpu` drivers and `mesa` for graphics.
- Check `modules/amd-gpu.nix` for global GPU settings.

## Editor Integration
- **Helix**: Configuration is managed in `home/common.nix` or dedicated helix modules.
- **LSP**: `nil` and `nixd` are used for Nix language support.
- **Formatting**: Use `nixfmt` if available, otherwise follow 2-space standard.

## AI Assistant Instructions
- **Proactiveness**: If adding a new service, look at `modules/services/` for existing patterns.
- **Structure**: Host-specific settings go in `hosts/[hostname]/default.nix`. Shared user settings go in `home/common.nix`.
- **Safety**: Never modify `hardware-configuration.nix` directly; it is auto-generated.
- **Verification**: Always run `nix flake check` or `./scripts/deploy.sh` after structural changes.
- **Secrets**: Do NOT add secrets (API keys, passwords) to the repository. Use `sops-nix` or similar if available (check for `.sops.yaml`).
- **Single Test**: To test a specific module change without a full rebuild, use `nix eval .#nixosConfigurations.<hostname>.config.<module_path>` to verify evaluation.

## Additional Rules (Cursor/Copilot)
No dedicated `.cursorrules` or `.github/copilot-instructions.md` were found in this repository. All agent instructions should follow this `AGENTS.md` and the `Plan.md` for architectural context.
