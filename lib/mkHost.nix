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

  # spacy 3.8.16 fails its test suite on Python 3.14. Root cause:
  # test_doc_retokenize_merge_extension_attrs_invalid registers a local
  # lambda as a global Doc extension setter without cleanup; every later
  # n_process>1 test then dies pickling it (schedule-dependent — different
  # victims each run). Deselect the poisoner plus the known dependents
  # (the check hook feeds disabledTests into pytest -k, whose expression
  # grammar can't express parametrized ids, so families are substring-
  # matched whole). Drop this when nixpkgs ships the same fix.
  #
  # Must go through pythonPackagesExtensions (applies to python3.pkgs et
  # al.); overriding prev.python314 only rebuilds the python314 alias and
  # paperless pulls spacy via python3Packages, which wouldn't see it.
  spacyTestFixOverlay = _final: prev: {
    pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
      (_pyFinal: pyPrev: {
        spacy = pyPrev.spacy.overridePythonAttrs (old: {
          disabledTests = (old.disabledTests or [ ]) ++ [
            "test_doc_retokenize_merge_extension_attrs_invalid"
            "test_span_ruler_multiprocessing"
            "test_language_pipe"
          ];
        });
      })
    ];
  };

  # paperless-ngx 3.1.3's test_consumer.py::TestConsumer::testNormalOperation
  # counts files while the consume-dir watcher is live; under parallel test
  # load it intermittently sees one extra event (AssertionError: 22 != 21).
  # 3266 other tests pass; drop this when upstream stabilizes it.
  #
  # The paperless NixOS module re-enters the package via
  # `pkg.override { tesseract5 = ... }` (to enable PAPERLESS_OCR_LANGUAGE
  # detection modules), but overridePythonAttrs drops that passthru — so
  # restore an override that re-applies the test patch after the module's
  # re-invocation.
  paperlessTestFixOverlay = _final: prev:
    let
      patchTests =
        pkg:
        pkg.overridePythonAttrs (old: {
          disabledTests = (old.disabledTests or [ ]) ++ [
            "testNormalOperation"
          ];
        });
    in
    {
      paperless-ngx = patchTests prev.paperless-ngx // {
        inherit (prev.paperless-ngx) tesseract5;
        override = args: patchTests (prev.paperless-ngx.override args);
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
        { nixpkgs.overlays = [ pinnedPackagesOverlay spacyTestFixOverlay paperlessTestFixOverlay vaultwardenOverlay torchAotritonOverlay ]; }
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
