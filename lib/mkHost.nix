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

  # Pin LibreOffice to a separate nixpkgs instance so the openldap override in
  # modules/common.nix doesn't invalidate its binary cache.
  libreofficeOverlay = _final: _prev: {
    libreoffice = nixpkgs-libreoffice.legacyPackages.${system}.libreoffice;
  };

  # Temporary: nixpkgs lags upstream. Override until 0.32.9 lands in unstable.
  # nixpkgs has no `ollama` base attr — only ollama-cpu / -rocm / -cuda / -vulkan,
  # each a separate callPackage of the same package.nix. This flake only uses
  # ollama-rocm, so override that one. The vendorHash is wrong on first eval;
  # Nix prints the right one — paste it in and rebuild.
  ollamaBump = oldAttrs: {
    version = "0.32.9";
    src = oldAttrs.src.override {
      tag = "v0.32.9";
      hash = "sha256-6BDUXDF5pXL3stffvtNJOnhC0A1xjPv43ZpsxegXm4w=";
    };
    vendorHash = "sha256-HMwoaFBMbpoy8f0I+O+i7kIa9BslLu3FcVWeaIOkpvs=";
  };
  ollamaOverlay = _final: prev: {
    ollama-rocm = prev.ollama-rocm.overrideAttrs ollamaBump;
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
        { nixpkgs.overlays = [
          libreofficeOverlay
          ollamaOverlay
        ]; }
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
