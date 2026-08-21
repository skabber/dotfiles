# Build a NixOS system configuration for a single host.
#
# Usage from flake.nix:
#
#   let
#     inherit (import ./lib/mkHost.nix {
#       inherit self nixpkgs nixpkgs-libreoffice home-manager system;
#     }) mkHost;
#   in {
#     nixosConfigurations = {
#       nixos = mkHost { hostname = "nixos"; extraModules = [ ... ]; extraSpecialArgs = { ... }; };
#       ...
#     };
#   };
{
  self,
  nixpkgs,
  nixpkgs-libreoffice,
  home-manager,
  system,
}:

let
  inherit (nixpkgs) lib;

  # Root of the flake (self) — paths below are resolved relative to this.
  root = self;

  # Packages pinned to a second, older nixpkgs instance:
  # - libreoffice: the openldap override in modules/common.nix invalidates its
  #   binary cache, so it comes from a clean instance (see flake.nix).
  # - dwarfs: 0.14.0 bundles 2023-era folly/fbthrift that no longer builds
  #   against current fmt/GCC (broken on hydra repeatedly since 2026-06,
  #  no upstream commits since). Drop when nixpkgs fixes it.
  pinnedPackagesOverlay = _final: _prev: {
    libreoffice = nixpkgs-libreoffice.legacyPackages.${system}.libreoffice;
    dwarfs = nixpkgs-libreoffice.legacyPackages.${system}.dwarfs;
  };

  # Small inline modules baked into every host.
  googleCloudSdkModule = { pkgs, ... }: {
    environment.systemPackages = [ pkgs.google-cloud-sdk ];
  };

  nixLdModule = {
    programs.nix-ld.enable = true;
  };
in
{
  mkHost =
    {
      hostname,
      extraModules ? [ ],
      extraSpecialArgs ? { },
    }:
    nixpkgs.lib.nixosSystem {
      specialArgs = extraSpecialArgs;
      modules = [
        { nixpkgs.hostPlatform = system; }
        { nixpkgs.overlays = [ pinnedPackagesOverlay ]; }
        "${root}/hosts/${hostname}/default.nix"
        googleCloudSdkModule
        nixLdModule
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "backup";
          home-manager.users.jay = import "${root}/home/${hostname}.nix";
        }
      ] ++ extraModules;
    };
}
