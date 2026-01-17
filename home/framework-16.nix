# Framework 16 - Home Manager configuration
{ config, pkgs, lib, ... }:

{
  imports = [
    ./common.nix
  ];

  # Framework 16 specific packages
  home.packages = with pkgs; [
    # Similar to framework-13, adjust as needed
    framework-tool
    inputmodule-control
    via
    nvtopPackages.amd
  ];

  # Framework 16 needs HSA override for AMD GPU
  home.sessionVariables = {
    HSA_OVERRIDE_GFX_VERSION = "10.3.0";
  };
}
