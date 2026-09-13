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
  # asDropin generates user-units/graphical-session.target.d/overrides.conf;
  # an environment.etc entry under "systemd/user" would collide with NixOS's
  # symlink to user-units and break the etc build.
  systemd.user.targets."graphical-session" = {
    overrideStrategy = "asDropin";
    unitConfig = {
      RefuseManualStart = false;
      StopWhenUnneeded = false;
    };
  };

  # Lock screen (also installs hyprlock + PAM policy)
  programs.hyprlock.enable = true;

  # hyprlock drives fprintd natively (auth.fingerprint in hyprlock.conf)
  security.pam.services.hyprlock.fprintAuth = false;

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
