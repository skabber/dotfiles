# Common NixOS configuration shared across all machines
{ config, pkgs, lib, ... }:

{
  # Nix settings
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.optimise.automatic = true;

  # Bootloader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Networking
  networking.networkmanager.enable = true;

  # Internationalization
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Common system packages
  environment.systemPackages = with pkgs; [
    zsh
    wget
    helix
    jq
    file
    lshw
    usbutils
    gnumake
    gcc
    cmake
    openssl.dev
    mosh
    docker-compose
    tailscale
    pavucontrol
    pipewire
    networkmanagerapplet
    gnome-tweaks
    opencode
  ];

  # User account
  users.users.jay = {
    isNormalUser = true;
    description = "Jay Graves";
    extraGroups = [ "networkmanager" "wheel" "docker" "video" "render" "tty" "dialout" ];
    packages = with pkgs; [ firefox ];
    shell = pkgs.zsh;
  };

  # Common services
  services.openssh.enable = true;
  services.dbus.enable = true;
  services.tailscale.enable = true;
  services.fwupd.enable = true;
  services.printing.enable = true;

  # Programs
  programs.zsh.enable = true;
  programs._1password.enable = true;
  programs._1password-gui = {
    enable = true;
    polkitPolicyOwners = [ "jay" ];
  };
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
  };

  # Docker
  virtualisation.docker.enable = true;

  # Security
  security.rtkit.enable = true;
  security.pam.services.gdm-password.enableGnomeKeyring = true;
}
