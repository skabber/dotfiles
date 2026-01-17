# Framework 16 - NixOS Configuration
# NOTE: hardware-configuration.nix needs to be copied from this machine
{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/common.nix
    ../../modules/desktop.nix
  ];

  # Hostname
  networking.hostName = "nixos-framework-16";

  # Timezone - automatic for laptop
  services.automatic-timezoned.enable = true;
  services.geoclue2.geoProviderUrl = "https://api.beacondb.net/v1/geolocate";

  # Power management
  powerManagement.enable = true;

  # Framework udev rules
  services.udev.packages = [ pkgs.via ];
  services.udev.extraRules = ''
    # Framework Laptop 16 - LED Matrix
    SUBSYSTEMS=="usb", ATTRS{idVendor}=="32ac", ATTRS{idProduct}=="0020", MODE="0660", TAG+="uaccess"
  '';

  # Framework 16 specific packages
  environment.systemPackages = with pkgs; [
    inputmodule-control
    (btop.override { rocmSupport = true; })
    rocmPackages.rocminfo
    rocmPackages.rocm-smi
  ];

  # Permitted insecure packages
  nixpkgs.config.permittedInsecurePackages = [
    "electron-25.9.0"
    "freeimage-3.18.0-unstable-2024-04-18"
  ];

  system.stateVersion = "25.05";
}
