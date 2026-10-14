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
  ambxst,
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
  # The patch goes through builtins.path so only the FILE is copied to the
  # store, content-addressed. A plain path literal (or "${root}/...") makes
  # the derivation depend on a full flake-source snapshot, so every dotfiles
  # edit recompiled torch from source.
  torchAotritonPatch = builtins.path {
    path = ../patches/torch-2.13-aotriton-0.11.patch;
    name = "torch-2.13-aotriton-0.11.patch";
  };
  torchAotritonOverlay = _final: prev: {
    pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
      (_pyFinal: pyPrev: {
        torch = pyPrev.torch.overrideAttrs (old: {
          patches = (old.patches or [ ]) ++ [ torchAotritonPatch ];
        });
      })
    ];
  };

  # ROCm 7.2.3's hip/amd_detail/host_defines.h does `#define __noinline__
  # __attribute__((noinline))`, which collides with libstdc++ 16.2's new
  # [[__gnu__::__noinline__]] attribute in <format>/<chrono_io>/<string>/
  # <memory>/...: the macro expands inside the attribute spec and parsing
  # fails with "expected an identifier for the attribute name". Any TU whose
  # include chain reaches a hip header before those std headers breaks
  # (c10/hip, ATen/hip, kineto...). Worse, hipify-clang PREPENDS
  # #include <hip/hip_runtime.h> to every file it generates from the
  # *::/cuda sources, so the macro is live before the file's own includes —
  # undef at line 1 of every source file lands right after that inserted
  # include (generated layout: [hip include][undef][rest]), and a second
  # undef after every cuda/hip/rocprofiler-sdk include covers real (non-
  # hipified) includers. Hydra never builds the ROCm variant, so upstream
  # hasn't noticed. Neither the hip/sdk headers nor torch's own code use the
  # bare macro (cutlass uses are __CUDA_ARCH__-guarded and unreachable on
  # gfx), and #undefs are guarded on __HIP_PLATFORM_AMD__ so CUDA builds are
  # untouched. Also drop kineto's own -Werror (appended after
  # CMAKE_CXX_FLAGS, so it beats nixpkgs' -Wno-error) — cheap insurance
  # across the 3300-file build. Remove when nixpkgs builds ROCm torch
  # against the GCC 16.2 stdenv.
  torchGcc16KinetoOverlay = _final: prev: {
    pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
      (_pyFinal: pyPrev: {
        torch = pyPrev.torch.overrideAttrs (old: {
          postPatch = (old.postPatch or "") + ''
            # Undef at line 1 of every source file: hipify-clang prepends
            # #include <hip/hip_runtime.h> to each hipified file, so the
            # generated layout becomes [hip include][undef][rest] — the macro
            # dies before any libstdc++ header can see it. torchgen's checked-
            # in c_shim_*.h files are byte-compared at configure time and must
            # stay pristine (they never include hip/cuda, so no hole).
            # grep -L exits 1 when an xargs batch contains only banner files,
            # so the filter stages run under `|| true` (output is complete).
            # Strip any leading UTF-8 BOM first: prepending above it would
            # strand the bytes mid-file where GCC rejects them (oneDNN and
            # cpp-httplib ship two such files).
            find c10 aten torch third_party -type f \
              \( -name '*.h' -o -name '*.hpp' -o -name '*.cpp' -o -name '*.cc' \
              -o -name '*.cu' -o -name '*.cuh' -o -name '*.hip' \) -print0 |
              { xargs -0 grep -LZ 'AUTOGENERATED BY torchgen' -- || true; } |
              xargs -0 -r sed -i -e '1s/^\xEF\xBB\xBF//' \
                -e '1i #ifdef __HIP_PLATFORM_AMD__\n#undef __noinline__\n#endif'
            # Belt and suspenders for real (non-hipified) hip/sdk includers:
            # undef right after every cuda/hip/rocprofiler-sdk include too.
            grep -rlZ --include='*.h' --include='*.hpp' --include='*.cpp' --include='*.cc' \
              --include='*.cu' --include='*.cuh' --include='*.hip' \
              -E '#include[[:space:]]+[<"](cuda|hip|rocprofiler-sdk)[/_]' \
              c10 aten torch third_party |
              { xargs -0 grep -LZ 'AUTOGENERATED BY torchgen' -- || true; } |
              xargs -0 -r sed -i \
                -e '/#include[[:space:]]\+[<"]\(cuda\|hip\|rocprofiler-sdk\)[/_]/a #ifdef __HIP_PLATFORM_AMD__\n#undef __noinline__\n#endif'
            substituteInPlace third_party/kineto/libkineto/CMakeLists.txt \
              --replace-fail " -Wall -Wextra -pedantic -Werror" " -Wall -Wextra -pedantic"
          '';
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
      specialArgs = { inherit ambxst; } // extraSpecialArgs;
      modules = [
        { nixpkgs.hostPlatform = system; }
        { nixpkgs.overlays = [ pinnedPackagesOverlay paperlessTestFixOverlay vaultwardenOverlay torchAotritonOverlay torchGcc16KinetoOverlay ]; }
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
