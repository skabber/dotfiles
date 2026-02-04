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

      # CPU backends
      mkl
      oneDNN
    ];

    environment.variables = {
      HIP_ARCHITECTURES = cfg.architecture;
    };
  };
}
