# Threadripper 1 (nixos-ripper) - NixOS Configuration
{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/common.nix
    ../../modules/desktop.nix
    ../../modules/services/ollama.nix
    ../../modules/services/sunshine.nix
    ../../modules/services/retroarch.nix
    ../../modules/services/syncthing.nix
    ../../modules/services/vllm.nix
  ];

  # Hostname
  networking.hostName = "nixos-ripper";

  # Timezone - static for desktop
  time.timeZone = "America/Denver";

  # Kernel settings
  boot.kernel.sysctl = {
    "fs.inotify.max_user_watches" = 2048576;
  };

  # WiFi kernel modules (Intel AX200 + Qualcomm WCN785x)
  boot.kernelModules = [ "iwlwifi" "ath12k" ];

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

  # ROCm support
  nixpkgs.config.rocmSupport = true;

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
  ollama.enable = false;
  sunshine.enable = true;
  retroarch.enable = true;
  syncthing = {
    enable = true;
    dataDir = "/home/jay/.syncthing";
    guiAddress = "0.0.0.0:8384";
  };

  # Permitted insecure packages
  nixpkgs.config.permittedInsecurePackages = [
    "electron-25.9.0"
  ];

  # Fix outlines-core version mismatch (outlines 1.2.9 requires ==0.2.11, but 0.2.13 is available)
  nixpkgs.overlays = [
    (final: prev: {
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
      python3Packages = final.python3.pkgs;
    })
  ];

  # Threadripper-specific packages
  environment.systemPackages = with pkgs; [
    (btop.override { rocmSupport = true; })
    wirelesstools
    iw
    wlr-randr
    gnome-randr
    gst_all_1.gst-plugins-base
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
    rocmPackages.rocm-smi
    rocmPackages.rocminfo
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
