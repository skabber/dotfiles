# nixos (Threadripper with NVIDIA GPU) - NixOS Configuration
{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/common.nix
    ../../modules/desktop-nvidia.nix
    ../../modules/services/sunshine.nix
    ../../modules/services/gitea.nix
    ../../modules/services/wallabag.nix
    ../../modules/services/syncthing.nix
  ];

  # Hostname
  networking.hostName = "nixos";

  # Timezone
  time.timeZone = "America/Denver";
  services.automatic-timezoned.enable = lib.mkForce false;

  # NTFS support
  boot.supportedFilesystems = [ "ntfs" ];

  # Binary caches
  nix.settings = {
    substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
      "https://cuda-maintainers.cachix.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
    ];
  };

  # Flatpak support
  services.flatpak.enable = true;
  xdg.portal.enable = true;

  # Prevent GDM from suspending before user login
  services.displayManager.gdm.autoSuspend = false;

  # Enable services
  sunshine.enable = false;

  gitea = {
    enable = true;
    openFirewall = true;
    domain = "nixos.tail69fe1.ts.net";
    mailer = {
      enable = true;
      protocol = "dummy";
    };
    runner = {
      enable = true;
      token = "07XSNFqRI37Y91ikvcJ8eUjT3F5z4G3NKSZdatfm";
      labels = [ "ubuntu-latest:docker://catthehacker/ubuntu:act-latest" ];
    };
  };

  wallabag = {
    enable = true;
    hostname = "nixos.tail69fe1.ts.net";
    basePath = "/wallabag";
    useSSL = true;
    database.type = "sqlite";
    secret = "iWIjQIh9roEBVbTm1ZpZRgjn9jd3CZbuO3YuRQ7IQ4";
  };

  # Static website at root, served via nginx (Tailscale Serve handles HTTPS)
  services.nginx.virtualHosts."nixos.tail69fe1.ts.net" = {
    root = "/var/www/public";
    locations."/" = {
      index = "index.html index.htm";
      tryFiles = "$uri $uri/ =404";
    };
  };

  # Ensure static site directory exists
  systemd.tmpfiles.rules = [
    "d /var/www/public 0775 nginx nginx -"
  ];

  services.kokoro-fastapi = {
    enable = true;
    useGpu = true;
    port = 8880;
    openFirewall = true;
  };

  syncthing = {
    enable = true;
    dataDir = /home/jay/.syncthing;
    guiAddress = "0.0.0.0:8384";
  };

  # Fingerprint reader (Goodix)
  services.fprintd.enable = true;
  services.fprintd.tod.enable = true;
  services.fprintd.tod.driver = pkgs.libfprint-2-tod1-goodix;

  # Enable linger so systemd --user starts at boot (needed for user services over SSH)
  users.users.jay.linger = true;

  # GNOME Keyring PAM (unlock keyring at login, including SSH sessions)
  security.pam.services.gdm.enableGnomeKeyring = true;
  security.pam.services.sshd.enableGnomeKeyring = true;

  # YubiKey / U2F authentication
  security.pam.services = {
    login.u2fAuth = true;
    sudo.u2fAuth = true;
  };

  # GnuPG agent with SSH support
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  # Swap file
  swapDevices = [
    {
      device = "/swapfile";
      size = 32384; # 32GB
    }
  ];

  # Docker insecure registry for local Gitea
  virtualisation.docker.daemon.settings = {
    insecure-registries = [ "nixos.tail69fe1.ts.net:3000" ];
  };

  # Spice USB redirection (for VMs)
  virtualisation.spiceUSBRedirection.enable = true;

  # Symlink Chrome to standard path for tools like Playwright that expect it
  system.activationScripts.chromeSymlink.text = ''
    mkdir -p /opt/google/chrome
    ln -sf ${pkgs.google-chrome}/bin/google-chrome-stable /opt/google/chrome/chrome
  '';

  # Additional system packages
  environment.systemPackages = with pkgs; [
    (btop.override { cudaSupport = true; })
    meson
    gnome-randr
  ];

  # Permitted insecure packages
  nixpkgs.config.permittedInsecurePackages = [
    "electron-19.1.9"
    "electron-25.9.0"
  ];

  system.stateVersion = "23.11";
}
