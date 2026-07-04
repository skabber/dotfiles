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
      type = types.str;
      default = "gfx1030";
      description = "Target GPU architecture (e.g., gfx1030, gfx1150)";
    };
  };

  config = mkIf cfg.enable {
    # Enable ROCm support in nixpkgs
    nixpkgs.config.rocmSupport = true;

    # Build ROCm GPU code for ONLY this machine's architecture. nixpkgs exposes a
    # per-arch rocmPackages scope (e.g. rocmPackages.gfx1150) that pins
    # clr.localGpuTargets; every ROCm lib (rccl, rocblas, hipblaslt, ...) and
    # ollama read that to set their AMDGPU_TARGETS. Without it they compile for
    # the full upstream target matrix (~12 gfx arches), which is enormously slow.
    nixpkgs.overlays = [
      (_final: prev: {
        rocmPackages = prev.rocmPackages.${cfg.architecture};
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
      HIP_ARCHITECTURES = cfg.architecture;
    };
  };
}
