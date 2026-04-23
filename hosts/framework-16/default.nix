# Framework 16 - NixOS Configuration
{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/common.nix
    ../../modules/desktop-cosmic.nix
    ../../modules/rocm-dev.nix
  ];

  # Hostname
  networking.hostName = "nixos-framework";

  # ROCm development environment (RDNA 3.5)
  rocm-dev = {
    enable = false;
    architecture = "gfx1150";
  };

  # Custom geolocation provider
  services.geoclue2.geoProviderUrl = "https://api.beacondb.net/v1/geolocate";

  # Power management
  powerManagement.enable = true;

  # Framework udev rules
  services.udev.packages = [ pkgs.via ];
  services.udev.extraRules = ''
    # Framework Laptop 16 - LED Matrix
    SUBSYSTEMS=="usb", ATTRS{idVendor}=="32ac", ATTRS{idProduct}=="0020", MODE="0660", TAG+="uaccess"
  '';

  # Fingerprint
  services.fprintd.enable = true;

  # libvirt for VMs
  virtualisation.libvirtd.enable = true;

  # Framework 16 specific packages
  environment.systemPackages = with pkgs; [
    inputmodule-control
    (btop.override { rocmSupport = true; })
    fprintd
    meson
  ];

  # Permitted insecure packages
  nixpkgs.config.permittedInsecurePackages = [
    "electron-25.9.0"
    "freeimage-3.18.0-unstable-2024-04-18"
  ];

  system.stateVersion = "23.11";
}
