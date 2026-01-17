# GNOME Desktop Environment configuration
{ config, pkgs, lib, ... }:

{
  # X11 and display
  services.xserver.enable = true;
  services.xserver.videoDrivers = [ "amdgpu" ];

  # GNOME Desktop
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

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
    wireplumber.enable = true;
  };

  # Wayland support
  environment.systemPackages = with pkgs; [
    xwayland
    wayland-protocols
    wayland-utils
    wl-clipboard
    wlroots
  ];
}
