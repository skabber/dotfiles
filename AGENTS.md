# AGENTS.md

This guide is for agentic coding agents (like yourself) working in this repository. It outlines the core workflows, environment, and code style standards for this NixOS dotfiles configuration.

## System Overview
- **OS**: NixOS (using Flakes and Home Manager)
- **Hardware**: Framework Laptop 16 (AMD RDNA 3, gfx1030/gfx1150)
- **Editor**: Helix (`hx`) is the primary editor.
- **Languages**: Nix, Shell, Rust, Go, Zig, Python, Deno.
- **User**: `jay`

## Repository Structure
```
~/dotfiles/
├── flake.nix                    # Main flake entry point
├── hosts/                       # Machine-specific configs (framework-16, framework-13, nixos, nixos-ripper)
├── modules/                     # Shared NixOS modules (common.nix, desktop.nix, rocm-dev.nix, services/)
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
./bin/trim-generations.sh         # Clean up old generations
```

### Validation & Testing
```bash
nix flake check                   # Verify flake syntax and evaluation
nix build .#nixosConfigurations.framework-16.config.system.build.toplevel  # Build host config
nix eval .#nixosConfigurations.framework-16.config.services.openssh.enable # Quick validation
nix flake show                    # Show flake outputs
nix flake lock --update-input <name>  # Update specific input
nix search nixpkgs <package>      # Search for package
```

## Code Style & Conventions

### Nix Formatting
- **Indentation**: 2 spaces (strictly no tabs).
- **Filenames**: `kebab-case.nix` (e.g., `rocm-dev.nix`).
- **Attributes**: `camelCase` for attribute names (e.g., `stateVersion`).
- **Imports**: Relative paths from file location (e.g., `../../modules/common.nix`).
- **Comments**: Use `#` for line comments. Add brief descriptions at module top.

### Nix Module Structure
```nix
# Brief description of the module
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.custom-service;
in
{
  options.services.custom-service = {
    enable = mkEnableOption "Custom Service";
    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Port to listen on";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ pkgs.some-package ];
    systemd.services.custom-service = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig.ExecStart = "${pkgs.some-package}/bin/some-binary";
    };
  };
}
```

### Types and Options
- Use `lib.types` for all options: `types.str`, `types.bool`, `types.int`, `types.port`, `types.enum`, `types.attrsOf`, `types.listOf`.
- Provide sensible defaults. Always include `description` for new options.
- Use `mkEnableOption` for boolean enable flags.

### Imports Pattern
Host configurations import modules in order:
1. `./hardware-configuration.nix` (always first)
2. `../../modules/common.nix` (base system config)
3. Desktop/GPU modules (`desktop.nix`, `rocm-dev.nix`)
4. Service modules from `../../modules/services/`

### Shell Scripts
- **Shebang**: `#!/usr/bin/env bash`
- **Safety**: Always include `set -euo pipefail`
- **Formatting**: 2-space indentation, `kebab-case.sh` naming

### Error Handling
- **Nix**: Use `assert` for invariants, `throw` for critical errors, `lib.warn` for warnings.
- **Shell**: Rely on `set -e` and check exit codes.
- **Validation**: Always run `nix flake check` after structural changes.

### Git & Commits
- **Messages**: Concise, focus on "why" (e.g., `feat: add ollama module with ROCm support`).
- **Style**: Follow Conventional Commits (feat, fix, refactor, docs, chore).

## Hardware/GPU Support
This repo targets AMD RDNA 3 hardware:
- **RDNA 3** (gfx1030): Use `HSA_OVERRIDE_GFX_VERSION=10.3.0`
- **RDNA 3.5** (gfx1150): See `rocm-dev.nix` for architecture setting
- Prefer `amdgpu` drivers and `mesa` for graphics.

## Service Module Patterns
Service modules in `modules/services/` should:
1. Define `enable` option using `mkEnableOption`
2. Use `mkIf cfg.enable` for conditional configuration
3. Set environment variables for GPU support when needed
4. Include systemd service configuration
5. Open firewall ports only when necessary

## Editor Integration
- **Helix**: Configuration managed via Home Manager.
- **LSP**: `nil` and `nixd` for Nix language support.

## AI Assistant Instructions
- **Proactiveness**: If adding a new service, look at `modules/services/` for patterns.
- **Structure**: Host-specific → `hosts/[hostname]/default.nix`. Shared user → `home/common.nix`.
- **Safety**: Never modify `hardware-configuration.nix` directly; it is auto-generated.
- **Verification**: Run `nix flake check` or `./scripts/deploy.sh` after structural changes.
- **Secrets**: Do NOT add secrets to the repository. Use `sops-nix` if available.

## Common Tasks

### Adding a package
- System-wide: `modules/common.nix` → `environment.systemPackages`
- User-level: `home/common.nix` → `home.packages`

### Adding a service
1. Create `modules/services/<name>.nix` following the module pattern
2. Add `enable = true;` in the host config
3. Validate: `nix flake check`

### Adding a host
1. `mkdir hosts/<hostname>` && `sudo nixos-generate-config`
2. Create `default.nix` with imports
3. Add to `flake.nix` outputs and `home-manager.users`

## Troubleshooting

- **Module not found**: Check import paths, verify file exists, check syntax
- **Home Manager conflicts**: `home-manager switch --flake .#$(hostname) --force`
- **GPU/ROCm**: Verify `HSA_OVERRIDE_GFX_VERSION`, check `rocmSupport`, use `rocm-smi`
