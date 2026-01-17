# Threadripper 1 (nixos-ripper) - NixOS Configuration
{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/common.nix
    ../../modules/desktop.nix
    # TODO: Add vscode-server as a flake input if needed
    # (fetchTarball "https://github.com/nix-community/nixos-vscode-server/tarball/master")
  ];

  # Hostname
  networking.hostName = "nixos-ripper";

  # Timezone - static for desktop
  time.timeZone = "America/Denver";

  # VSCode Server (requires adding to flake inputs)
  # services.vscode-server.enable = true;

  # Razer peripherals
  hardware.openrazer.enable = true;
  users.users.jay.extraGroups = lib.mkAfter [ "openrazer" ];

  # ROCm support
  nixpkgs.config.rocmSupport = true;

  # GNOME Keyring PAM
  security.pam.services.gdm.enableGnomeKeyring = true;

  # U2F auth
  security.pam.services = {
    login.u2fAuth = true;
    sudo.u2fAuth = true;
  };

  # Fonts
  fonts.packages = with pkgs; [
    fira-code
    fira-code-symbols
    nerd-fonts.fira-code
    nerd-fonts.droid-sans-mono
  ];

  # Android SDK
  environment.variables = {
    NIXPKGS_ACCEPT_ANDROID_SDK_LICENSE = "1";
  };

  # Disk/mount services
  services.udisks2.enable = true;
  services.devmon.enable = true;
  services.gvfs.enable = true;

  # Via udev rules
  services.udev.packages = [ pkgs.via ];
  services.udev.extraRules = ''
    # Framework Laptop 16 - LED Matrix
    SUBSYSTEMS=="usb", ATTRS{idVendor}=="32ac", ATTRS{idProduct}=="0020", MODE="0660", TAG+="uaccess"
  '';

  # Threadripper-specific packages
  environment.systemPackages = with pkgs; [
    openrazer-daemon
    polychromatic
    onedrive
    minikube
    kubectl
    tmux
  ];

  system.stateVersion = "23.11";
}
