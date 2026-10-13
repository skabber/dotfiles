# ROCm/HIP development environment module
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.rocm-dev;
in
{
  options.rocm-dev = {
    enable = mkEnableOption "ROCm/HIP development environment";

    architecture = mkOption {
      type = types.either types.str (types.listOf types.str);
      default = "gfx1030";
      description = ''
        Target GPU architecture or architectures. Accepts a single string
        (e.g. "gfx1150") or a list when more than one is needed. Pinning to
        only this host's arch speeds up ROCm builds enormously (otherwise
        nixpkgs compiles for the full ~12-arch upstream matrix).

        Caveat: composable_kernel (pulled in by torch/vLLM with rocmSupport)
        only builds for gfx9-class (MFMA) hardware and is marked broken when
        no gfx9 target is present. If a host runs vLLM, include a gfx9 MFMA
        target (gfx908/gfx90a/gfx942/gfx950) alongside this host's real arch
        so CK stays evaluable.
      '';
    };
  };

  config = mkIf cfg.enable {
    # Enable ROCm support in nixpkgs
    nixpkgs.config.rocmSupport = true;

    # Build ROCm GPU code for ONLY the targets above. Every ROCm lib
    # (rccl, rocblas, hipblaslt, miopen, ...) and ollama derive their target
    # list from clr.localGpuTargets. Note: per-arch `rocmPackages.${arch}`
    # scopes rename packages with an -arch suffix and force evaluation of
    # broken per-arch variants downstream, so we overrideScope the main scope
    # instead — mirroring how nixpkgs builds its own per-arch scopes.
    nixpkgs.overlays = [
      (final: prev: {
        rocmPackages = prev.rocmPackages.overrideScope (_sfinal: sprev: {
          clr = sprev.clr.override {
            localGpuTargets =
              let v = cfg.architecture;
              in if builtins.isList v then v else [ v ];
          };
        });
        # magma 2.9.0 supports no AMD arch past gfx1033, and nixpkgs derives
        # its target list from clr.localGpuTargets — a host pinned to gfx1150
        # alone then fails to evaluate with "No supported GPU targets
        # specified". magma-hip.override can't fix this: the assert evaluates
        # while forcing the original callPackage'd derivation (makeOverridable's
        # `result // { override = ...; }`), before override args merge. So
        # re-callPackage magma fresh with explicit gpuTargets (host arches
        # stripped to CMake form and intersected with magma's supported list —
        # which notably lacks gfx90a; 908 fallback when none) and the PINNED
        # rocmPackages — an unpinned scope here made magma's rocblas/hipblaslt
        # deps build the full 9-arch matrix, whose Tensile codegen alone eats
        # ~26 GiB and swap-thrashes the machine. Drop when magma learns gfx1150.
        magma-hip =
          let
            archList = if builtins.isList cfg.architecture then cfg.architecture else [ cfg.architecture ];
            # magma 2.9.0 supportedGpuTargets (gfx7 omitted — nothing targets it)
            magmaArches = [
              "900" "902" "904" "906" "908" "909" "90c"
              "1010" "1011" "1012" "1030" "1031" "1032" "1033"
            ];
            hostArches = map (removePrefix "gfx") archList;
            magmaSupported = builtins.filter (t: builtins.elem t magmaArches) hostArches;
          in
          prev.callPackage (prev.path + "/pkgs/by-name/ma/magma/package.nix") {
            rocmPackages = final.rocmPackages;
            gpuTargets = if magmaSupported == [ ] then [ "908" ] else magmaSupported;
            cudaSupport = false;
            rocmSupport = true;
          };
      })
    ];

    environment.systemPackages = with pkgs; [
      # ROCm/HIP toolchain
      rocmPackages.clr
      rocmPackages.hip-common
      rocmPackages.hipblas
      rocmPackages.rocprim
      rocmPackages.rocthrust
      rocmPackages.hipcub
      rocmPackages.hiprand
      rocmPackages.rocrand
      rocmPackages.rocminfo
      rocmPackages.rocm-smi

      # Build tools
      cmake
      ninja
      pkg-config
      gnumake
      clang
      llvm

      # CPU backends
      mkl
      oneDNN
    ];

    environment.variables = {
      HIP_ARCHITECTURES =
        let v = cfg.architecture;
        in if builtins.isList v then concatStringsSep "," v else v;
    };
  };
}
