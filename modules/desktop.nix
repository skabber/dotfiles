# Desktop with AMD GPU (adds Hyprland session)
{ config, pkgs, lib, ambxst, ... }:

let
  # Launches Hyprland with HYPRLAND_CONFIG pointing at the Ambxst variant
  # (home/hyprland.nix): Ambxst's generated settings first, the regular
  # config layered on top as overrides
  hyprlandAmbxstSession = pkgs.writeShellScriptBin "hyprland-ambxst-session" ''
    export HYPRLAND_CONFIG="$HOME/.config/hypr/hyprland-ambxst.lua"
    exec ${pkgs.hyprland}/bin/start-hyprland
  '';

  ambxstSessionDesktop = (pkgs.writeTextDir "share/wayland-sessions/hyprland-ambxst.desktop" ''
    [Desktop Entry]
    Name=Hyprland (Ambxst)
    Comment=Hyprland with the Ambxst desktop shell
    Exec=${pkgs.uwsm}/bin/uwsm start -e -D Hyprland ${hyprlandAmbxstSession}/bin/hyprland-ambxst-session
    TryExec=${pkgs.uwsm}/bin/uwsm
    DesktopNames=Hyprland
    Type=Application
  '') // { providedSessions = [ "hyprland-ambxst" ]; };
in
{
  imports = [ ./desktop-base.nix ambxst.nixosModules.default ];

  services.xserver.videoDrivers = [ "amdgpu" ];

  programs.hyprland = {
    enable = true;
    withUWSM = true;
  };

  # SDDM preselects the alphabetically-first session when it has no
  # LastSession state (fresh install, or after clearing /var/lib/sddm), which
  # is cosmic.desktop — and cosmic-comp currently fails to take drm master
  # under SDDM, leaving a dead VT and a stuck graphical-session.target that
  # uwsm then refuses to log in over. Default to the uwsm-managed Hyprland
  # session instead.
  services.displayManager.defaultSession = "hyprland-uwsm";

  # Second SDDM entry: same compositor, but with the Ambxst shell's settings
  # preloaded (opt-in per login; the default session is unchanged). uwsm
  # manages this session identically to the default one.
  services.displayManager.sessionPackages = [ ambxstSessionDesktop ];

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

  # Polkit authentication agent for the Hyprland session. 1Password's embedded
  # agent does not register under Hyprland, and without an agent polkit requests
  # that require auth (e.g. Bitwarden biometric unlock, GParted) fail silently.
  # The unit is started from hyprland.lua's autostart (needs WAYLAND_DISPLAY in
  # the user manager, which the dbus-update-activation-environment call sets).
  systemd.packages = [ pkgs.hyprpolkitagent ];

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
