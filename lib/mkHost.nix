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

  # vaultwarden 1.37.2 cannot parse the new password-change payload that
  # web-vault/client 2026.7.0+ send, so changing the master password fails
  # with 422 "missing field `newMasterPasswordHash`". 1.37.3 fixes this
  # (upstream PR #7634), but nixpkgs hasn't bumped past 1.37.2 yet.
  # TEMPORARY: remove this overlay once nixpkgs ships vaultwarden >= 1.37.3.
  vaultwardenOverlay =
    _final: prev:
    let
      vwSrc = prev.fetchFromGitHub {
        owner = "dani-garcia";
        repo = "vaultwarden";
        tag = "1.37.3";
        hash = "sha256-T2sTVsBCvsvgxjlTeBPSvA96mJ7TLYqLNvldCI73by0=";
      };
    in
    {
      vaultwarden = prev.vaultwarden.overrideAttrs (_old: {
        version = "1.37.3";
        src = vwSrc;
        # cargoHash doesn't survive overrideAttrs, so vendor explicitly
        cargoDeps = prev.rustPlatform.fetchCargoVendor {
          src = vwSrc;
          hash = "sha256-gUQxnGPo8jYTfG+Zsz8W35h8lkYDxI3mGnCdxNXYB4k=";
        };
      });
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
        { nixpkgs.overlays = [ pinnedPackagesOverlay spacyTestFixOverlay vaultwardenOverlay ]; }
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
