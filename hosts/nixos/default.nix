# nixos (Threadripper 2) - NixOS Configuration
# NOTE: hardware-configuration.nix needs to be copied from this machine
{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/common.nix
    ../../modules/desktop.nix
  ];

  # Hostname
  networking.hostName = "nixos";

  # Timezone
  time.timeZone = "America/Denver";

  # Threadripper-specific settings - configure when deploying
  # hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  system.stateVersion = "23.11";
}
