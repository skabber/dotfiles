# Framework 13 AMD - NixOS Configuration
{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/common.nix
    ../../modules/desktop.nix
    ../../modules/rocm-dev.nix
    ../../modules/services/comfyui.nix
  ];

  # Hostname
  networking.hostName = "nixos-framework-13";

  # ROCm development environment (RDNA 3.5)
  rocm-dev = {
    enable = true;
    architecture = "gfx1150";
  };

  # ComfyUI - Stable Diffusion node-based UI (ROCm, Python venv)
  comfyui = {
    enable = true;
    gfxVersion = "11.5.0";
    extraArgs = [ "--enable-manager" ];
  };

  # Framework 13 specific kernel params
  boot.kernelParams = [
    "ttm.pages_limit=22369536"
    "button.lid_init_state=open"
  ];

  # Custom geolocation provider
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


  # Security
  security.polkit.enable = true;
  security.sudo.enable = true;

  # Screen lock
  programs.xss-lock.enable = true;

  # libvirt for VMs
  virtualisation.libvirtd.enable = true;

  # Workaround: upstream virt-secret-init-encryption.service hardcodes /usr/bin/sh
  # which doesn't exist on NixOS. Override ExecStart with Nix store paths.
  # https://github.com/NixOS/nixpkgs/issues/496836
  systemd.services.virt-secret-init-encryption.serviceConfig.ExecStart = let
    dd = "${pkgs.coreutils}/bin/dd";
    systemd-creds = "${pkgs.systemd}/bin/systemd-creds";
  in lib.mkForce [
    ""
    "${pkgs.bash}/bin/bash -c 'umask 0077 && (${dd} if=/dev/random status=none bs=32 count=1 | ${systemd-creds} encrypt --name=secrets-encryption-key - /var/lib/libvirt/secrets/secrets-encryption-key)'"
  ];

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
    inputmodule-control
    proton-vpn
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
