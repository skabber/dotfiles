# Framework 16 - NixOS Configuration
{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/common.nix
    ../../modules/desktop.nix
    ../../modules/rocm-dev.nix
    ../../modules/services/ollama.nix
  ];

  # Hostname
  networking.hostName = "nixos-framework";

  # ROCm development environment (RDNA 3.5)
  rocm-dev = {
    enable = false;
    architecture = "gfx1150";
  };

  # Ollama + Open WebUI
  ollama.enable = true;

  # Custom geolocation provider
  services.geoclue2.geoProviderUrl = "https://api.beacondb.net/v1/geolocate";

  # Power management
  powerManagement.enable = true;

  # Disable WiFi power save (mt7921e/MT7922 latency + throughput fix)
  networking.networkmanager.wifi.powersave = false;

  # Framework udev rules
  services.udev.packages = [ pkgs.via ];
  services.udev.extraRules = ''
    # Framework Laptop 16 - LED Matrix
    SUBSYSTEMS=="usb", ATTRS{idVendor}=="32ac", ATTRS{idProduct}=="0020", MODE="0660", TAG+="uaccess"
  '';

  # Fingerprint
  services.fprintd.enable = true;

  # Crucial X8 CIFS share (served by nixos). nofail + noauto +
  # x-systemd.automount means it mounts on first access and doesn't block
  # boot if the server is unreachable.
  fileSystems."/mnt/crucial-x8" = {
    device = "//nixos/Crucial X8";
    fsType = "cifs";
    options = [
      "guest"
      "uid=1000"
      "gid=100"
      "nofail"
      "noauto"
      "x-systemd.automount"
      "x-systemd.idle-timeout=60"
    ];
  };

  # libvirt for VMs
  virtualisation.libvirtd.enable = true;

  # Framework 16 specific packages
  environment.systemPackages = with pkgs; [
    cifs-utils
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
