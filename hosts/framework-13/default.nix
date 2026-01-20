# Framework 13 AMD - NixOS Configuration
{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/common.nix
    ../../modules/desktop.nix
  ];

  # Hostname
  networking.hostName = "nixos-framework-13";

  # Framework 13 specific kernel params
  boot.kernelParams = [
    "ttm.pages_limit=22369536"
    "button.lid_init_state=open"
  ];

  # Timezone - automatic for laptop
  services.automatic-timezoned.enable = true;
  services.geoclue2.geoProviderUrl = "https://api.beacondb.net/v1/geolocate";

  # Power management for laptop
  powerManagement.enable = true;

  # Lid switch behavior
  services.logind.settings.Login = {
    HandleLidSwitch = "suspend";
  };

  # Framework udev rules
  services.udev.packages = [ pkgs.via ];
  services.udev.extraRules = ''
    # Framework Laptop 13 - LED Matrix
    SUBSYSTEMS=="usb", ATTRS{idVendor}=="32ac", ATTRS{idProduct}=="0020", MODE="0660", TAG+="uaccess"
  '';

  # Fingerprint
  services.fprintd.enable = true;

  # JACK audio (for music production)
  services.jack = {
    jackd.enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    # loopback.enable = true;
  };

  # Additional user groups for Framework
  users.users.jay.extraGroups = lib.mkAfter [ "jackaudio" ];

  # Security
  security.polkit.enable = true;
  security.sudo.enable = true;

  # Screen lock
  programs.xss-lock.enable = true;

  # libvirt for VMs
  virtualisation.libvirtd.enable = true;

  # Framework-specific packages
  environment.systemPackages = with pkgs; [
    (btop.override { rocmSupport = true; })
    pulseaudio
    dwarfs
    meson
    rofi
    wofi
    fprintd
    minikube
    kubectl
    rocmPackages.rocminfo
    rocmPackages.rocm-smi
    inputmodule-control
    protonvpn-gui
    libnotify
    ffmpeg
  ];

  # Permitted insecure packages
  nixpkgs.config.permittedInsecurePackages = [
    "electron-25.9.0"
    "freeimage-3.18.0-unstable-2024-04-18"
  ];

  system.stateVersion = "25.05";
}
