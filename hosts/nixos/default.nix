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
    ../../modules/services/whisperx.nix
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

  # NVIDIA Container Toolkit for GPU access in Docker
  # enableNvidia is deprecated but needed to register the nvidia runtime
  # for docker-compose files that use deploy.resources.reservations.devices
  hardware.nvidia-container-toolkit.enable = true;
  virtualisation.docker.enableNvidia = true;

  services.kokoro-fastapi = {
    enable = true;
    useGpu = true;
    port = 8881;
    openFirewall = true;
  };

  # Override kokoro-fastapi to use docker compose v2 (has buildx support)
  # The upstream Dockerfile uses --platform=$BUILDPLATFORM which requires buildx
  systemd.services.kokoro-fastapi.serviceConfig = let
    dataDir = "/var/lib/kokoro-fastapi";
    dockerDir = "${dataDir}/Kokoro-FastAPI/docker/gpu";
  in lib.mkForce {
    Type = "exec";
    User = "kokoro-fastapi";
    Group = "kokoro-fastapi";
    WorkingDirectory = dataDir;
    Restart = "always";
    RestartSec = "10";
    TimeoutStartSec = "300";
    TimeoutStopSec = "60";
    ExecStartPre = [
      "${pkgs.coreutils}/bin/mkdir -p ${dataDir}"
      "${pkgs.coreutils}/bin/chown kokoro-fastapi:kokoro-fastapi ${dataDir}"
      "${pkgs.bash}/bin/bash -c 'cd ${dataDir} && if [ ! -d Kokoro-FastAPI ]; then ${pkgs.git}/bin/git clone https://github.com/remsky/Kokoro-FastAPI.git; else cd Kokoro-FastAPI && ${pkgs.git}/bin/git fetch origin && ${pkgs.git}/bin/git reset --hard origin/master; fi'"
      # chown what we can (Docker-created files may be owned by container UID)
      "${pkgs.bash}/bin/bash -c '${pkgs.coreutils}/bin/chown -R kokoro-fastapi:kokoro-fastapi ${dataDir}/Kokoro-FastAPI || true'"
      # Make api dir writable by container's appuser (UID 1001)
      "${pkgs.bash}/bin/bash -c '${pkgs.coreutils}/bin/chmod -R a+w ${dataDir}/Kokoro-FastAPI/api || true'"
      # Patch port mapping (upstream hardcodes 8880:8880, we use 8881 to avoid Tailscale Serve conflict)
      "${pkgs.gnused}/bin/sed -i 's/8880:8880/8881:8880/' ${dockerDir}/docker-compose.yml"
      "${pkgs.bash}/bin/bash -c 'cd ${dockerDir} && ${pkgs.docker}/bin/docker compose down || true'"
    ];
    ExecStart = "${pkgs.bash}/bin/bash -c 'cd ${dockerDir} && ${pkgs.docker}/bin/docker compose up --build'";
    ExecStop = "${pkgs.bash}/bin/bash -c 'cd ${dockerDir} && ${pkgs.docker}/bin/docker compose down'";
  };

  syncthing = {
    enable = true;
    dataDir = /home/jay/.syncthing;
    guiAddress = "0.0.0.0:8384";
  };

  whisperx = {
    enable = true;
    openFirewall = true;
    # hfTokenFile = "/run/secrets/hf-token";  # uncomment to enable diarization
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
