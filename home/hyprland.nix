# Declarative Hyprland desktop configs, shipped to ~/.config via Home Manager.
#
# Source files live in ../config/ (mirroring the XDG layout). After a rebuild
# these appear as symlinks into the nix store — edit them in the repo, not in
# ~/.config. Only imported by hosts that enable Hyprland (modules/desktop.nix).
#
# See docs/hyprland.md for usage.
{ pkgs, ... }:

let
  wallpaper = "${pkgs.nixos-artwork.wallpapers.nineish-catppuccin-mocha}/share/wallpapers/nineish-catppuccin-mocha/contents/images/nix-wallpaper-nineish-catppuccin-mocha.png";

  # nixpkgs pins hypr-dynamic-cursors at 2026-07-21, which predates hyprland
  # 0.56.2's renderSoftwareCursorsFor(..., screencopy, forceRender) signature;
  # the plugin then refuses to load ("unexpected function signature") and its
  # config keys stay unknown. Backport of upstream fix 9778329 until the pin
  # catches up: https://github.com/VirtCode/hypr-dynamic-cursors/pull/160
  hypr-dynamic-cursors = pkgs.hyprlandPlugins.hypr-dynamic-cursors.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./patches/hypr-dynamic-cursors-v0.56.2.patch ];
  });

  # nixpkgs pins hyprtasking at a rev tracking hyprland main (post-0.56.2 ABI);
  # the v0.56.2 pair is the plugin's own hyprpm.toml commit_pin
  hyprtasking = pkgs.hyprlandPlugins.hyprtasking.overrideAttrs (old: {
    version = "0-unstable-2026-05-04";
    src = pkgs.fetchFromGitHub {
      owner = "raybbian";
      repo = "hyprtasking";
      rev = "4d3c39511c3f38966abf1ec4393f5a7220ffb1a3";
      hash = "sha256-3C5YdLaUx4LgmPyVyfYqHB24ZDsrfI87veA3eDQIofM=";
    };
  });
in
{
  xdg.configFile = {
    "hypr/hyprland.lua".source = ../config/hypr/hyprland.lua;
    "hypr/hyprlock.conf".source = ../config/hypr/hyprlock.conf;
    "hypr/hypridle.conf".source = ../config/hypr/hypridle.conf;
    "waybar/config.jsonc".source = ../config/waybar/config.jsonc;
    "waybar/style.css".source = ../config/waybar/style.css;
    "waybar/scripts/tailscale-status.sh" = {
      source = ../config/waybar/scripts/tailscale-status.sh;
      executable = true;
    };
    "waybar/scripts/audio-picker.sh" = {
      source = ../config/waybar/scripts/audio-picker.sh;
      executable = true;
    };
    "waybar/scripts/bluetooth-picker.sh" = {
      source = ../config/waybar/scripts/bluetooth-picker.sh;
      executable = true;
    };
    "waybar/scripts/screens.sh" = {
      source = ../config/waybar/scripts/screens.sh;
      executable = true;
    };
    "rofi/config.rasi".source = ../config/rofi/config.rasi;
    "networkmanager-dmenu/config.ini".source = ../config/networkmanager-dmenu/config.ini;
    "mako/config".source = ../config/mako/config;
    "hypr/hyprpaper.conf".text = ''
      splash = false
      wallpaper {
          monitor = *
          path = ${wallpaper}
      }
    '';

    # Loaded via require("./plugins") from hyprland.lua; store paths are
    # interpolated here so plugin updates propagate on rebuild
    "hypr/plugins.lua".text = ''
      hl.plugin.load("${hypr-dynamic-cursors}/lib/libhypr-dynamic-cursors.so")
      hl.plugin.load("${hyprtasking}/lib/libhyprtasking.so")
    '';
  };
}
