# Cosmic Desktop with AMD GPU
{ config, pkgs, lib, ... }:

{
  services.desktopManager.cosmic.enable = true;
  services.desktopManager.gnome.enable = true;
  services.displayManager.cosmic-greeter.enable = true;

  services.xserver = {
    enable = true;
    xkb.layout = "us";
    xkb.variant = "";
    videoDrivers = [ "amdgpu" ];
    desktopManager.xfce.enable = true;
  };

  services.pulseaudio.enable = false;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    wireplumber.enable = true;
  };

  services.orca.enable = lib.mkForce false;

  environment.systemPackages = with pkgs; [
    xwayland
    wayland-protocols
    wayland-utils
    wl-clipboard
  ];
}
