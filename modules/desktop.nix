# Desktop with AMD GPU (adds Hyprland session)
{ config, pkgs, lib, ... }:

{
  imports = [ ./desktop-base.nix ];

  services.xserver.videoDrivers = [ "amdgpu" ];

  programs.hyprland = {
    enable = true;
    withUWSM = true;
  };

  # Bare (non-uwsm) Hyprland sessions never activate graphical-session.target;
  # xdg-desktop-portal refuses to start without it (Requisite=), which silently
  # breaks window/screen sharing in browsers. Make the target manually startable
  # (hyprland.lua autostart starts it) and persistent with no requirers.
  environment.etc."systemd/user/graphical-session.target.d/allow-manual-start.conf".text = ''
    [Unit]
    RefuseManualStart=no
    StopWhenUnneeded=no
  '';

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
