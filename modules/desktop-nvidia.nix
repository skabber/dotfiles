# GNOME Desktop Environment configuration for NVIDIA GPUs
{ config, pkgs, lib, ... }:

{
  # X11 and display
  services.xserver.enable = true;
  services.xserver.videoDrivers = [ "nvidia" ];

  # GNOME Desktop
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  # GNOME Keyring (SecretService provider)
  services.gnome.gnome-keyring.enable = true;

  # Keyboard layout
  services.xserver = {
    xkb.layout = "us";
    xkb.variant = "";
  };

  # Audio - PipeWire
  services.pulseaudio.enable = false;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
    wireplumber.enable = true;
  };

  # NVIDIA GPU configuration
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = false;
    powerManagement.finegrained = false;
    open = false;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.vulkan_beta;
  };

  # Wayland/cursor fix for NVIDIA
  environment.sessionVariables = {
    WLR_NO_HARDWARE_CURSORS = "1";
  };

  # Wayland support packages
  environment.systemPackages = with pkgs; [
    xwayland
    wayland-protocols
    wayland-utils
    wl-clipboard
    wlroots
    rofi
    wofi
  ];
}
