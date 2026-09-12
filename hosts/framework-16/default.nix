# Framework 16 - NixOS Configuration
{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/common.nix
    ../../modules/desktop.nix
    ../../modules/rocm-dev.nix
    ../../modules/services/ollama.nix
    ../../modules/services/agentgateway.nix
    ../../modules/services/flatpak.nix
    ../../modules/services/crucial-x8.nix
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

  # Agentgateway (LLM/MCP/A2A proxy, UI at http://localhost:4000/ui)
  agentgateway.enable = true;

  # Flatpak support (orion-beta remote is set by the flatpak module by default)
  flatpak.enable = true;

  # Custom geolocation provider
  services.geoclue2.geoProviderUrl = "https://api.beacondb.net/v1/geolocate";

  # Power management
  powerManagement.enable = true;

  # Hibernation: resume from the /swapfile on root (nvme1n1p2; see
  # hardware-configuration.nix). The offset below is the physical extent of
  # the swapfile as created by the 2025-09 rebuild; if /swapfile is ever
  # deleted/recreated (e.g. size changed), re-read it with
  #   sudo filefrag -v /swapfile | sed -n '4p' | awk '{print $4}' | tr -d '.'
  # and update it here, or hibernate will fail to find its image.
  boot.resumeDevice = "/dev/disk/by-uuid/899d2560-5b59-4faa-a283-fccb0efa4c83";
  boot.kernelParams = [ "resume_offset=164333568" ];

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

  # Crucial X8 CIFS share (served by nixos)
  crucial-x8.enable = true;

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
