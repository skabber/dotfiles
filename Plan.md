# Multi-Machine NixOS Configuration Migration Plan

## Overview
Migrate from scattered configuration files to a unified, flake-based multi-machine setup with proper version control, shared modules, and Home Manager-managed dotfiles.

## Target Machines
- **nixos-ripper** - Threadripper 1 (current machine)
- **nixos** - Threadripper 2
- **framework-13** - Framework 13 laptop
- **framework-16** - Framework 16 laptop

## Goals
1. ✅ Single repository for all machine configurations
2. ✅ Shared modules for common settings
3. ✅ Machine-specific configs easily managed
4. ✅ Home Manager manages all dotfiles
5. ✅ `/etc/nixos` symlinked to host directory
6. ✅ Simple deployment: `nixos-rebuild switch --flake .#hostname`

---

## Phase 0: Preparation

### Backup Current State
```bash
# Backup system configs
sudo cp /etc/nixos/configuration.nix /etc/nixos/configuration.nix.backup-$(date +%Y%m%d)
sudo cp /etc/nixos/homemanager.nix /etc/nixos/homemanager.nix.backup-$(date +%Y%m%d)

# Note rollback command if needed:
# sudo nix-channel --update && sudo nixos-rebuild switch --option build-use-sandbox false
```

### Generate Hardware Configs for Other Machines
Run this on each of the 3 other machines to get their hardware configurations:

```bash
# On nixos, framework-13, framework-16
sudo nixos-generate-config --root / --dir /tmp/hardware-config
cat /tmp/hardware-config/hardware-configuration.nix
# Copy output to ~/dotfiles/hosts/[hostname]/hardware-configuration.nix
```

Copy hardware configs to nixos-ripper:
```bash
# From each machine, copy hardware config to dotfiles
scp /tmp/hardware-config/hardware-configuration.nix jay@nixos-ripper:~/dotfiles/hosts/nixos/hardware-configuration.nix
scp /tmp/hardware-config/hardware-configuration.nix jay@nixos-ripper:~/dotfiles/hosts/framework-13/hardware-configuration.nix
scp /tmp/hardware-config/hardware-configuration.nix jay@nixos-ripper:~/dotfiles/hosts/framework-16/hardware-configuration.nix
```

---

## Phase 1: Create Directory Structure

### Execute on nixos-ripper
```bash
cd ~/dotfiles

# Create host directories
mkdir -p hosts/nixos-ripper
mkdir -p hosts/nixos
mkdir -p hosts/framework-13
mkdir -p hosts/framework-16

# Create module directories
mkdir -p modules/services
mkdir -p home/modules/shells
mkdir -p home/modules/programs
mkdir -p scripts

# Verify structure
tree -L 3 -d
```

### Expected Structure
```
~/dotfiles/
├── flake.nix                          # Main flake entry point
├── Plan.md                            # This file
├── hosts/                             # Machine-specific configs
│   ├── nixos-ripper/                  # Threadripper 1 (current machine)
│   │   ├── hardware-configuration.nix
│   │   └── default.nix                # Machine-specific NixOS settings
│   ├── nixos/                         # Threadripper 2
│   │   ├── hardware-configuration.nix
│   │   └── default.nix
│   ├── framework-13/                  # Framework 13
│   │   ├── hardware-configuration.nix
│   │   └── default.nix
│   └── framework-16/                  # Framework 16
│       ├── hardware-configuration.nix
│       └── default.nix
├── modules/                           # Shared NixOS modules
│   ├── common.nix                     # Common system config (base)
│   ├── amd-gpu.nix                    # AMD GPU specific
│   ├── users.nix                      # User account management
│   ├── desktop.nix                    # Desktop environment config
│   └── services/                      # Individual service modules (moved from nix-modules/)
│       ├── ollama.nix
│       ├── sunshine.nix
│       ├── gitea.nix
│       ├── retroarch.nix
│       ├── syncthing.nix
│       ├── vllm.nix
│       └── wallabag.nix
├── home/                              # Home Manager configs
│   ├── common.nix                     # Shared user config
│   ├── nixos-ripper.nix               # Machine-specific user config
│   ├── nixos.nix
│   ├── framework-13.nix
│   ├── framework-16.nix
│   └── modules/
│       ├── packages.nix               # Shared packages
│       ├── programs.nix               # Shared programs
│       └── shells/
│           ├── zsh.nix
│           └── aliases.nix
├── dotfiles/                          # Actual dotfiles (managed by Home Manager)
│   ├── gitconfig
│   ├── zshconfig
│   └── bashconfig
└── scripts/
    └── deploy.sh                      # Helper script for deployment
```

---

## Phase 2: Create Core Files

### 2.1 Create flake.nix
```bash
# Will be created as ~/dotfiles/flake.nix
```

Content structure:
```nix
{
  description = "Multi-machine NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, ... }: {
    nixosConfigurations = {
      nixos-ripper = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./hosts/nixos-ripper/default.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.jay = import ./home/nixos-ripper.nix;
          }
        ];
      };

      nixos = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./hosts/nixos/default.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.jay = import ./home/nixos.nix;
          }
        ];
      };

      framework-13 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./hosts/framework-13/default.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.jay = import ./home/framework-13.nix;
          }
        ];
      };

      framework-16 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./hosts/framework-16/default.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.jay = import ./home/framework-16.nix;
          }
        ];
      };
    };
  };
}
```

### 2.2 Create modules/common.nix
Extract common settings from current `/etc/nixos/configuration.nix`:
- Bootloader config
- Time zone
- Internationalization
- Networking
- Allow unfree packages
- Common system packages
- Nix settings (experimental features, optimize)

### 2.3 Move Modules
Move existing service modules from `nix-modules/` to `modules/services/`:
```bash
mv ~/dotfiles/nix-modules/ollama.nix ~/dotfiles/modules/services/
mv ~/dotfiles/nix-modules/sunshine.nix ~/dotfiles/modules/services/
mv ~/dotfiles/nix-modules/gitea.nix ~/dotfiles/modules/services/
mv ~/dotfiles/nix-modules/retroarch.nix ~/dotfiles/modules/services/
mv ~/dotfiles/nix-modules/syncthing.nix ~/dotfiles/modules/services/
mv ~/dotfiles/nix-modules/vllm.nix ~/dotfiles/modules/services/
mv ~/dotfiles/nix-modules/wallabag.nix ~/dotfiles/modules/services/
mv ~/dotfiles/nix-modules/programs.nix ~/dotfiles/modules/
mv ~/dotfiles/nix-modules/hostname.nix ~/dotfiles/modules/
```

### 2.4 Create Host Configurations

#### hosts/nixos-ripper/default.nix
```nix
{ config, pkgs, lib, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/common.nix
    ../../modules/amd-gpu.nix
    ../../modules/users.nix
    ../../modules/desktop.nix
    ../../modules/services/ollama.nix
    ../../modules/services/sunshine.nix
  ];

  # Machine-specific settings
  ollama.enable = false;  # Adjust based on this machine
  sunshine.enable = true;

  # Threadripper-specific
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
```

#### hosts/nixos/default.nix, framework-13/default.nix, framework-16/default.nix
Similar structure with appropriate service enables/disables.

### 2.5 Create Home Manager Configs

#### home/common.nix
Extract from `/etc/nixos/homemanager.nix`:
- Shared packages
- Shared programs (starship, direnv, git)
- Common home settings

#### home/modules/shells/zsh.nix
Transform current `zshconfig` content using Home Manager's `programs.zsh.enable = true`:
```nix
{ config, pkgs, lib, ... }:
{
  programs.zsh = {
    enable = true;
    initExtra = ''
      eval "$(starship init zsh)"
      eval "$(direnv hook zsh)"

      export PATH=$PATH:$HOME/.cargo/bin
      export PATH=$PATH:$HOME/go/bin
      export PATH=$PATH:$HOME/bin
      export PATH=$PATH:$HOME/.local/bin

      export EDITOR=hx

      ${if config.networking.hostName == "framework-16" then "export HSA_OVERRIDE_GFX_VERSION=10.3.0" else ""}

      source $HOME/dotfiles/export-esp.sh

      function y() {
        local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
        yazi "$@" --cwd-file="$tmp"
        if cwd="$(command cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
          builtin cd -- "$cwd"
        fi
        rm -f -- "$tmp"
      }
    '';
  };
}
```

#### home/nixos-ripper.nix
```nix
{ config, pkgs, ... }:
{
  imports = [
    ./common.nix
    ./modules/shells/zsh.nix
  ];

  home.packages = with pkgs; [
    # Threadripper-specific packages
    libreoffice
    android-studio
    # Add other machine-specific packages
  ];

  # Dotfile management
  home.file.".gitconfig".source = ../../dotfiles/gitconfig;

  # Machine-specific settings
  home.sessionVariables = {
    # Threadripper specific vars
  };
}
```

Create similar files for other hosts.

---

## Phase 3: Symlink & Deploy on nixos-ripper

### 3.1 Copy hardware config
```bash
cp /etc/nixos/hardware-configuration.nix ~/dotfiles/hosts/nixos-ripper/
```

### 3.2 Create deployment script
Create `scripts/deploy.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

HOSTNAME=$(hostname)
CONFIG_DIR="$HOME/dotfiles/hosts/$HOSTNAME"

echo "🔧 Deploying to: $HOSTNAME"
echo "📁 Config directory: $CONFIG_DIR"

# Create symlink to /etc/nixos
echo "🔗 Creating symlink: /etc/nixos -> $CONFIG_DIR"
sudo ln -sfn "$CONFIG_DIR" /etc/nixos

# Build configuration
echo "🏗️  Building configuration..."
sudo nixos-rebuild build --flake "$HOME/dotfiles#$HOSTNAME"

# Show new generation info
echo ""
echo "✅ Build complete! Review the generation info above."
echo ""
read -p "Switch to new configuration? (y/n): " answer

if [[ "$answer" =~ ^[Yy]$ ]]; then
  echo "🔄 Switching to new configuration..."
  sudo nixos-rebuild switch --flake "$HOME/dotfiles#$HOSTNAME"

  echo ""
  echo "✅ Configuration switched successfully!"
  echo "💡 Rollback command: sudo nixos-rebuild switch --rollback"
else
  echo "❌ Build cancelled."
  exit 1
fi
```

Make it executable:
```bash
chmod +x ~/dotfiles/scripts/deploy.sh
```

### 3.3 Create rollback script
Create `scripts/rollback.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

echo "🔄 Rolling back to previous configuration..."
sudo nixos-rebuild switch --rollback
echo "✅ Rollback complete!"
```

Make it executable:
```bash
chmod +x ~/dotfiles/scripts/rollback.sh
```

### 3.4 Test build
```bash
cd ~/dotfiles

# Verify flake
nix flake check

# Test build (doesn't apply changes)
sudo nixos-rebuild build --flake .#nixos-ripper

# If successful, review the output and continue
# If failed, check errors and fix before proceeding
```

### 3.5 Switch to new configuration
```bash
# Apply the new configuration
sudo nixos-rebuild switch --flake .#nixos-ripper

# Verify everything works
hostname
systemctl status
# Test basic functionality: network, display, etc.
```

### 3.6 Update Home Manager
```bash
# Update Home Manager configuration
home-manager switch --flake .#nixos-ripper

# Verify dotfiles are managed
ls -la ~/.zshrc ~/.gitconfig
# Should be symlinks to /nix/store/...
```

---

## Phase 4: Deploy to Other Machines

### 4.1 Push to git
```bash
cd ~/dotfiles

# Stage all changes
git add .

# Review changes
git status

# Commit
git commit -m "Migrate to multi-machine flake structure

- Created flake-based configuration
- Organized modules and host configs
- Migrated to Home Manager-managed dotfiles
- Added deployment scripts"

# Push to remote (if configured)
git push
```

### 4.2 Deploy to each machine

#### On nixos (Threadripper 2)
```bash
# SSH to machine
ssh jay@nixos

# Cd to dotfiles, ensure it's git repo
cd ~/dotfiles
git pull

# Copy hardware config (if not done in Phase 0)
# sudo cp /etc/nixos/hardware-configuration.nix hosts/nixos/

# Create symlink
sudo ln -sfn ~/dotfiles/hosts/nixos /etc/nixos

# Test build
sudo nixos-rebuild build --flake .#nixos

# If successful, switch
sudo nixos-rebuild switch --flake .#nixos

# Update Home Manager
home-manager switch --flake .#nixos
```

#### On framework-13
```bash
ssh jay@framework-13
cd ~/dotfiles && git pull
sudo ln -sfn ~/dotfiles/hosts/framework-13 /etc/nixos
sudo nixos-rebuild build --flake .#framework-13
sudo nixos-rebuild switch --flake .#framework-13
home-manager switch --flake .#framework-13
```

#### On framework-16
```bash
ssh jay@framework-16
cd ~/dotfiles && git pull
sudo ln -sfn ~/dotfiles/hosts/framework-16 /etc/nixos
sudo nixos-rebuild build --flake .#framework-16
sudo nixos-rebuild switch --flake .#framework-16
home-manager switch --flake .#framework-16
```

---

## Phase 5: Cleanup (After Successful Deployment)

### Only run after ALL machines are working correctly!

```bash
cd ~/dotfiles

# Remove old config files from root
rm -f amd_configuration.nix
rm -f configuration.nix
rm -f homemanager.nix
rm -f hardware-configuration.nix
rm -f proton-drive.nix
rm -f python-overrides.nix

# Remove old nix-modules directory (if empty after moving files)
# First verify all files were moved
ls nix-modules/
# If empty or only contains README, remove it
rm -rf nix-modules/

# Remove backups directory
rm -rf backups/

# Verify structure
tree -L 3 -a
```

---

## Rollback Procedures

### If system build fails
```bash
# Backup symlink points to working config, so just rebuild with it
sudo nixos-rebuild switch /etc/nixos/configuration.nix.backup-$(date +%Y%m%d)

# Or use nix rollback
sudo nixos-rebuild switch --rollback
```

### If Home Manager breaks
```bash
# Rollback to previous Home Manager generation
home-manager switch --rollback

# Or regenerate from specific generation
home-manager switch --generation <generation-number>
```

### Quick rollback script
```bash
# Use the rollback script we created
~/dotfiles/scripts/rollback.sh
```

---

## Testing Checklist

After deploying to each machine, verify:

- [ ] Hostname is correct
- [ ] Network connection works
- [ ] Desktop environment loads
- [ ] User can login
- [ ] Shell functions work (`y` command aliases, etc.)
- [ ] Dotfiles are correct (~/.gitconfig, ~/.zshrc)
- [ ] Programs work (git, helix, etc.)
- [ ] Services are running (enabled services per machine)
- [ ] Hardware acceleration works (AMD GPU, etc.)

---

## Common Issues & Solutions

### Issue: "outlines-core version mismatch"
**Solution**: Keep the overlay in `modules/common.nix` to downgrade packages

### Issue: "electron-25.9.0" insecure
**Solution**: Remove from permittedInsecurePackages, update packages in homemanager config

### Issue: Module not found
**Solution**:
1. Check import paths are correct relative to host config
2. Verify files exist in expected locations
3. Ensure files have proper Nix syntax

### Issue: Home Manager dotfiles not updating
**Solution**:
```bash
# Force Home Manager to recreate symlinks
home-manager switch --flake .#hostname --force
```

### Issue: Symlink loop in /etc/nixos
**Solution**:
```bash
# Check what /etc/nixos points to
ls -la /etc/nixos

# Fix if wrong
sudo rm /etc/nixos
sudo ln -s ~/dotfiles/hosts/$(hostname) /etc/nixos
```

---

## Benefits After Migration

✅ **Single Repository**: All configs in one version-controlled place
✅ **Easy Deployment**: One command per machine
✅ **Shared Configs**: Common settings automatically applied
✅ **Machine-Specific**: Easy overrides per host
✅ **Rollback**: Flake-based rollbacks for system and home
✅ **Auto Dotfiles**: Home Manager manages all dotfiles
✅ **Better Organization**: Clear separation of concerns
✅ **Scalable**: Easy to add new machines or update existing ones

---

## Maintenance

### Adding a new machine
1. Generate hardware config: `sudo nixos-generate-config`
2. Create host directory: `mkdir -p hosts/new-hostname`
3. Add host to `flake.nix` outputs
4. Create `hosts/new-hostname/default.nix` with appropriate imports
5. Create `home/new-hostname.nix` for user config
6. Deploy: `sudo nixos-rebuild switch --flake .#new-hostname`

### Adding new packages
- System-wide: Add to `modules/common.nix` or specific host config
- User packages: Add to `home/common.nix` or host-specific home config

### Updating configs
1. Edit files in `~/dotfiles/`
2. Test: `sudo nixos-rebuild build --flake .#hostname`
3. Deploy: `sudo nixos-rebuild switch --flake .#hostname`
4. Update Home Manager: `home-manager switch --flake .#hostname`
5. Git commit and push

---

## Security Notes

### Secrets Management
Consider using these for sensitive data:
- **agenix**: Age-based encryption for secrets
- **sops-nix**: SOPS-based secrets management

Current setup:
- Gitea tokens stored inline (should use tokenFile)
- Signing key paths exposed (gitconfig:16)

Future improvements:
```
secrets/
  ├── gitea-runner-token.age
  └── ssh-keys/
```

---

## Appendix: Quick Reference

### Deploy to current machine
```bash
cd ~/dotfiles
./scripts/deploy.sh
# or manually
sudo nixos-rebuild switch --flake .#$(hostname)
```

### Update Home Manager
```bash
cd ~/dotfiles
home-manager switch --flake .#$(hostname)
```

### Rollback system
```bash
sudo nixos-rebuild switch --rollback
# or
./scripts/rollback.sh
```

### List generations
```bash
nix-env --list-generations --profile /nix/var/nix/profiles/system
home-manager generations
```

### Check flake
```bash
nix flake check
nix flake show
```

---

## Progress Tracking

- [ ] Phase 0: Preparation & backups
- [ ] Phase 1: Directory structure created
- [ ] Phase 2: Core files created (flake.nix, modules, host configs)
- [ ] Phase 3: Deployed to nixos-ripper (current machine)
- [ ] Phase 4: Deployed to nixos
- [ ] Phase 4: Deployed to framework-13
- [ ] Phase 4: Deployed to framework-16
- [ ] Phase 5: Cleanup old files
- [ ] All machines tested and verified

---

*Last Updated: $(date)*
*Author: Migration Plan for Multi-Machine NixOS Configuration*
