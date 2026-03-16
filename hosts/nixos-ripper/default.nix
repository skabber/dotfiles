# Threadripper 1 (nixos-ripper) - NixOS Configuration
{ config, pkgs, lib, ... }:

{
  # imports = [
  #   ./hardware-configuration.nix
  #   ../../modules/common.nix
  #   ../../modules/desktop.nix
  #   ../../modules/rocm-dev.nix
  #   ../../modules/services/ollama.nix
  #   ../../modules/services/sunshine.nix
  #   ../../modules/services/retroarch.nix
  #   ../../modules/services/syncthing.nix
  #   ../../modules/services/vllm.nix
  # ];
  imports = [
    ./hardware-configuration.nix
    ../../modules/common.nix
    ../../modules/desktop.nix
    ../../modules/rocm-dev.nix
    # ../../modules/services/ollama.nix
    # ../../modules/services/sunshine.nix
    # ../../modules/services/retroarch.nix
    # ../../modules/services/syncthing.nix
    # ../../modules/services/vllm.nix
  ];

  # Hostname
  networking.hostName = "nixos-ripper";

  # ROCm development environment (RDNA 2)
  rocm-dev = {
    enable = true;
    architecture = "gfx1030";
  };

  # Zram swap (helps with memory-heavy builds like ROCm)
  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };

  # Kernel settings
  boot.kernel.sysctl = {
    "fs.inotify.max_user_watches" = 2048576;
  };

  # WiFi kernel modules (Intel AX200 + Qualcomm WCN785x)
  # snd-aloop: ALSA loopback for system audio capture
  boot.kernelModules = [ "iwlwifi" "ath12k" "snd-aloop" ];

  # Hardware firmware
  hardware.enableRedistributableFirmware = true;
  hardware.firmware = with pkgs; [ linux-firmware ];

  # Razer peripherals
  hardware.openrazer.enable = true;
  users.users.jay.extraGroups = lib.mkAfter [ "openrazer" "roon-server" "input" ];

  # Mount points
  systemd.tmpfiles.rules = [
    "d /mnt/external 0777 root root - -"
  ];

  # LACT (AMD GPU control)
  systemd.packages = with pkgs; [ lact ];
  systemd.services.lactd.wantedBy = [ "multi-user.target" ];

  # Prevent GDM from suspending before user login
  services.displayManager.gdm.autoSuspend = false;

  # GNOME Keyring PAM
  security.pam.services.gdm.enableGnomeKeyring = true;

  # U2F and Yubikey auth
  services.pcscd.enable = true;
  services.udev.packages = [ pkgs.yubikey-personalization pkgs.via ];

  security.pam.services = {
    login.u2fAuth = true;
    sudo.u2fAuth = true;
  };

  security.pam.yubico = {
    enable = true;
    debug = true;
    mode = "challenge-response";
    id = [ "31141322" ];
  };

  # udev rules
  services.udev.extraRules = ''
    # Nintendo Pro Controller
    SUBSYSTEM=="input", ATTRS{idVendor}=="057e", ATTRS{idProduct}=="2009", MODE="0660", GROUP="input"
    # Framework Laptop 16 - LED Matrix
    SUBSYSTEMS=="usb", ATTRS{idVendor}=="32ac", ATTRS{idProduct}=="0020", MODE="0660", TAG+="uaccess"
  '';

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

  # GPG agent
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  # Disk/mount services
  services.udisks2.enable = true;
  services.devmon.enable = true;
  services.gvfs.enable = true;

  # Roon Server
  services.roon-server = {
    enable = true;
    openFirewall = true;
  };

  # Service toggles
  # ollama.enable = true;
  # ollama.flashAttention = false;
  # sunshine.enable = true;
  # retroarch.enable = true;
  # syncthing = {
  #   enable = true;
  #   dataDir = "/home/jay/.syncthing";
  #   guiAddress = "0.0.0.0:8384";
  # };

  # Permitted insecure packages
  nixpkgs.config.permittedInsecurePackages = [
    "electron-25.9.0"
  ];

  # vLLM with ROCm + outlines-core version fix, scoped to avoid breaking other python3 packages (e.g. calibre)
  nixpkgs.overlays = [
    (final: prev: {
      whisper-cpp = prev.whisper-cpp.overrideAttrs (old: {
        doBuild = false;
      });
      vllm-rocm = let
        python3 = prev.python3.override {
          packageOverrides = pyFinal: pyPrev: {
            outlines = pyPrev.outlines.overridePythonAttrs (old: {
              postPatch = (old.postPatch or "") + ''
                substituteInPlace pyproject.toml \
                  --replace-fail 'outlines_core==0.2.11' 'outlines_core>=0.2.11,<0.3.0'
              '';
            });
            vllm = (pyPrev.vllm.override { rocmSupport = true; }).overridePythonAttrs (old: {
              env = (old.env or {}) // { VLLM_TARGET_DEVICE = "rocm"; };
              postPatch = (old.postPatch or "") + ''
                sed -i 's/raise RuntimeError("Unknown runtime environment")/return "0.13.0"/' setup.py; sed -i 's/ValueError("Unsupported platform, please use CUDA, ROCm, or CPU.")/["rocm"]/' setup.py || true
              '';
            });
          };
        };
      in python3.pkgs.vllm;
    })
  ];

  # # Use the scoped vllm-rocm package
  # vllm.package = pkgs.vllm-rocm;

  # Threadripper-specific packages
  environment.systemPackages = with pkgs; [
    (btop.override { rocmSupport = true; })
    wirelesstools
    iw
    wlr-randr
    gnome-randr
    openrazer-daemon
    polychromatic
    onedrive
    minikube
    kubectl
    cryptsetup
    tmux
    spice-gtk
    lact
    docker-credential-gcr
    pciutils
    joycond-cemuhook
    protonvpn-gui
    ffmpeg
    squashfsTools
    fuse
    linuxConsoleTools
    snyk
  ];

  system.stateVersion = "23.11";
}
