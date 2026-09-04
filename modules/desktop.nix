# Desktop with AMD GPU (adds Hyprland session)
{ config, pkgs, lib, ... }:

{
  imports = [ ./desktop-base.nix ];

  services.xserver.videoDrivers = [ "amdgpu" ];

  programs.hyprland = {
    enable = true;
    withUWSM = true;
  };

  # Lock screen (also installs hyprlock + PAM policy)
  programs.hyprlock.enable = true;

  environment.systemPackages = with pkgs; [
    pulseaudio
    pipewire
    # Hyprland session: bar, launcher, notifications, screenshots
    waybar
    rofi
    mako
    hyprpaper
    grim
    slurp
    networkmanagerapplet
    brightnessctl
    libnotify
  ];
}
