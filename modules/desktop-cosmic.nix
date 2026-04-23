# Cosmic Desktop with AMD GPU
{ config, pkgs, lib, ... }:

{
  services.desktopManager.cosmic.enable = true;
  services.displayManager.cosmic-greeter.enable = true;

  services.xserver = {
    xkb.layout = "us";
    xkb.variant = "";
    videoDrivers = [ "amdgpu" ];
  };

  services.pulseaudio.enable = false;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    wireplumber.enable = true;
  };

  environment.systemPackages = with pkgs; [
    xwayland
    wayland-protocols
    wayland-utils
    wl-clipboard
  ];
}
