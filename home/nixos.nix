# nixos (Threadripper 2) - Home Manager configuration
{ config, pkgs, lib, ... }:

{
  imports = [
    ./common.nix
  ];

  # Add machine-specific packages here
  home.packages = with pkgs; [
    # Placeholder - configure when deploying to this machine
  ];
}
