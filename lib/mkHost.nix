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

  # spacy 3.8.16 fails its test suite on Python 3.14
  # (test_span_ruler_multiprocessing: multiprocessing can't pickle a local
  # lambda), which blocks paperless-ngx and the whole system build. Upstream
  # already deselects other 3.14-only failures; drop this when nixpkgs ships
  # the same fix.
  spacyTestFixOverlay = _final: prev: {
    python314 = prev.python314.override {
      packageOverrides = _pyFinal: pyPrev: {
        spacy = pyPrev.spacy.overridePythonAttrs (old: {
          disabledTests = (old.disabledTests or [ ]) ++ [
            "test_span_ruler_multiprocessing"
          ];
        });
      };
    };
  };

  # torch 2.13.0 doesn't compile against the aotriton 0.11.x that nixpkgs
  # unstable pins (its pre-0.12 code paths are broken: undeclared `cookie`
  # identifier in aotriton_adapter.h and attn_options::deterministic, which
  # only exists in aotriton >= 0.12). Only ROCm builds compile these files,
  # so CUDA/CPU hosts are unaffected. Drop when nixpkgs ships aotriton >= 0.12
  # or a fixed torch.
  torchAotritonOverlay = _final: prev: {
    pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
      (_pyFinal: pyPrev: {
        torch = pyPrev.torch.overrideAttrs (old: {
          patches = (old.patches or [ ]) ++ [
            "${root}/patches/torch-2.13-aotriton-0.11.patch"
          ];
        });
      })
    ];
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
        { nixpkgs.overlays = [ pinnedPackagesOverlay spacyTestFixOverlay torchAotritonOverlay ]; }
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
