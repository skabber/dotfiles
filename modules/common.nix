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

  # Graphical boot splash
  boot.plymouth.enable = true;
  boot.consoleLogLevel = 0;
  boot.kernelParams = [ "quiet" "splash" "loglevel=3" ];

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
    systemd
    zsh
    openssl
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

    # GStreamer for audio playback (respects system volume)
    gst_all_1.gstreamer
    gst_all_1.gstreamer.dev
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    gst_all_1.gst-plugins-bad
    gst_all_1.gst-plugins-ugly

    python312Packages.huggingface-hub
  ];

  # GStreamer environment setup for NixOS
  environment.variables = {
    GST_PLUGIN_PATH = lib.makeSearchPath "lib/gstreamer-1.0" [
      pkgs.gst_all_1.gstreamer.out
      pkgs.gst_all_1.gst-plugins-base
      pkgs.gst_all_1.gst-plugins-good
      pkgs.gst_all_1.gst-plugins-bad
      pkgs.gst_all_1.gst-plugins-ugly
    ];
    GST_PLUGIN_SYSTEM_PATH_1_0 = lib.makeSearchPath "lib/gstreamer-1.0" [
      pkgs.gst_all_1.gstreamer.out
      pkgs.gst_all_1.gst-plugins-base
      pkgs.gst_all_1.gst-plugins-good
      pkgs.gst_all_1.gst-plugins-bad
      pkgs.gst_all_1.gst-plugins-ugly
    ];
  };

  # User account
  users.users.jay = {
    isNormalUser = true;
    description = "Jay Graves";
    extraGroups = [ "networkmanager" "wheel" "docker" "video" "render" "tty" "dialout" "nginx" ];
    packages = [ ];
    shell = pkgs.zsh;
  };

  # Common services
  services.openssh.enable = true;
  services.dbus.enable = true;
  services.tailscale.enable = true;
  networking.firewall.trustedInterfaces = [ "tailscale0" ];
  services.fwupd.enable = true;
  services.printing.enable = true;
  services.geoclue2.enable = true;
  services.automatic-timezoned.enable = true;

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

  # nix-ld for dynamically linked binaries (e.g., cargo-installed tools)
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    openssl
  ];
}
