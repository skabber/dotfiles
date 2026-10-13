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
        Target GPU architecture or architectures, used only for the
        HIP_ARCHITECTURES env var (own hipcc builds). nixpkgs ROCm packages
        are left stock so their Hydra-built binaries substitute from
        cache.nixos.org; the default target matrix (gfx900 through gfx1201)
        covers every host here natively, gfx1030 and gfx1150 included.
      '';
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
