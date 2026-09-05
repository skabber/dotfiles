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

  # Icon font for waybar/rofi configs (FiraCode Nerd Font)
  fonts.packages = [ pkgs.nerd-fonts.fira-code ];

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
    networkmanager_dmenu
    brightnessctl
    libnotify
    # Hyprland ecosystem: idle, system info, annotate, clipboard, recording
    hypridle
    hyprsysteminfo
    satty
    cliphist
    wl-screenrec
    gpu-screen-recorder
  ];
}
