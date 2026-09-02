# nixos (Threadripper with NVIDIA GPU) - NixOS Configuration
{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/common.nix
    ../../modules/desktop-nvidia.nix
    ../../modules/services/sunshine.nix
    ../../modules/services/gnome-remote-desktop.nix
    ../../modules/services/gitea.nix
    ../../modules/services/wallabag.nix
    ../../modules/services/syncthing.nix
    ../../modules/services/moss-transcribe.nix
    ../../modules/services/wallabag-tts.nix
    ../../modules/services/defuddle.nix
    ../../modules/services/freetoken.nix
    ../../modules/services/service-panel.nix
    ../../modules/services/paperless.nix
    ../../modules/services/paperless-ai.nix
    ../../modules/services/paperless-gpt.nix
    ../../modules/services/romm.nix
    ../../modules/services/show-friends-preview.nix
    ../../modules/services/samba.nix
    ../../modules/services/flatpak.nix
  ];

  # Hostname
  networking.hostName = "nixos";

  # Timezone
  time.timeZone = "America/Denver";
  services.automatic-timezoned.enable = lib.mkForce false;

  # NTFS + exFAT support
  boot.supportedFilesystems = [ "ntfs" "exfat" ];

  # External ROM library drive (Crucial X8)
  fileSystems."/run/media/jay/Crucial X8" = {
    device = "/dev/disk/by-uuid/A89B-F756";
    fsType = "exfat";
    options = [ "nofail" "noauto" "x-systemd.automount" "x-systemd.idle-timeout=600" "uid=1000" "gid=100" "iocharset=utf8" "errors=remount-ro" ];
  };

  # Flatpak support (orion-beta remote is set by the flatpak module by default)
  flatpak.enable = true;
  xdg.portal.enable = true;

  # Prevent GDM from suspending before user login
  services.displayManager.gdm.autoSuspend = false;

  # Enable services
  sunshine.enable = false;

  gnome-remote-desktop = {
    enable = true;
    credentialsFile = "/home/jay/.secrets/grd-rdp.env";
  };

  gitea = {
    enable = true;
    openFirewall = true;
    domain = "nixos.tail69fe1.ts.net";
    rootUrl = "https://nixos.tail69fe1.ts.net:3000/";
    mailer = {
      enable = true;
      protocol = "dummy";
    };
    runner = {
      enable = true;
      url = "http://127.0.0.1:3000";
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
  # enableNvidia is deprecated but still required — it creates config.toml
  # and registers the nvidia runtime with Docker for legacy --gpus/driver:nvidia support.
  # hardware.nvidia-container-toolkit.enable alone only sets up CDI specs.
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
  systemd.services.kokoro-fastapi.wantedBy = lib.mkForce [ ];
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

  # MOSS-Transcribe-Diarize: same jobs API as the AMD hosts (:7860) backed by
  # a loopback vLLM engine (:8010, vllmPort default)
  moss-transcribe = {
    enable = true;
    backend = "vllm";
    openFirewall = true;
    serve = true;
    autoStart = true;
    maxBatchedTokens = 24576;
  };

  # FreeToken: MoE serving engine on the RTX 3080. FP8 35B (~35 GB of experts
  # in host RAM via the offload backend) fits the 62 GiB; BF16 would not.
  freetoken = {
    enable = true;
    model = "Qwen/Qwen3.6-35B-A3B-FP8";
    host = "0.0.0.0";
    autoStart = false;
    # 10 GB card, ~9.1 GiB free: ~2.9 weights + 3.1 expert cache (0.10 of the
    # 31.4G bank) + ~1.1 GDN pool (bf16 SSM halves the fp32 default) — engine
    # self-fits the KV pool into the rest, keeping ~0.9 GiB (memory_ratio)
    # for the FlashInfer workspace and CUDA graphs. --num-tokens overrides
    # skip the memory-fit solver and OOM. 4096-token prefill chunks
    # (--max-prefill-length) keep the transient GDN/MoE activation peak under
    # the ~0.6 GiB post-init headroom (8192 OOM'd mid-prefill); drop to 2048
    # if it recurs.
    extraArgs = [
      "--moe-cache-rate 0.10"
      "--max-prefill-length 4096"
    ];
    extraEnvironment.FREETOKEN_MAMBA_SSM_DTYPE = "bfloat16";
  };

  # FreeToken API for tailnet clients (e.g. `ft shell --server` on the ripper)
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ config.freetoken.port ];

  service-panel = {
    enable = true;
    units = [
      "moss-transcribe.service"
      "moss-transcribe-web.service"
      "tailscale-serve-moss-transcribe.service"
      "kokoro-fastapi.service"
      "freetoken.service"
    ];
  };

  defuddle = {
    enable = true;
    openFirewall = true;
  };

  wallabag-tts = {
    enable = true;
    openFirewall = true;
    environmentFile = "/home/jay/.secrets/wallabag-tts.env";
    podcastBaseUrl = "https://nixos.tail69fe1.ts.net:3001";
    pullInterval = 15;
    ttsVoice = "af_bella";
  };

  paperless = {
    enable = true;
    openFirewall = true;
    domain = "nixos.tail69fe1.ts.net";
    # Serve owns <ts-ip>:28981 externally; paperless must not wildcard-bind the
    # same port or it races tailscaled at boot and dies with EADDRINUSE (Aug 23).
    # Containers reach it via host.docker.internal:28982 below.
    port = 28982;
    passwordFile = "/home/jay/.secrets/paperless-admin-password";
  };

  # Use docker (already enabled below) as the backend for oci-containers
  # so we don't bring up a parallel podman stack.
  virtualisation.oci-containers.backend = "docker";

  paperless-ai = {
    enable = true;
    openFirewall = true;
    paperlessApiUrl = "http://host.docker.internal:28982/api";
    environmentFile = "/home/jay/.secrets/paperless-ai.env";
  };

  paperless-gpt = {
    enable = true;
    openFirewall = true;
    paperlessBaseUrl = "http://host.docker.internal:28982";
    enableLlmOcr = true;
    environmentFile = "/home/jay/.secrets/paperless-gpt.env";
  };

  romm = {
    enable = true;
    port = 8070;
    libraryPath = "/run/media/jay/Crucial X8";
    environmentFile = "/home/jay/.secrets/romm.env";
  };

  samba-share = {
    enable = true;
    shares."Crucial X8" = {
      path = "/run/media/jay/Crucial X8";
      comment = "Crucial X8 external drive";
    };
  };

  show-friends-preview = {
    enable = true;
    domain = "nixos.tail69fe1.ts.net";
    tokenFile = "/home/jay/.secrets/show-friends-preview.env";
  };

  # Fingerprint reader (Goodix)
  services.fprintd.enable = true;
  services.fprintd.tod.enable = true;
  services.fprintd.tod.driver = pkgs.libfprint-2-tod1-goodix;

  # Enable linger so systemd --user starts at boot (needed for user services over SSH)
  users.users.jay.linger = true;

  # Russell user account
  users.users.russell = {
    isNormalUser = true;
    description = "Russell";
    extraGroups = [ "networkmanager" "wheel" "docker" ];
    shell = pkgs.zsh;
  };

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
