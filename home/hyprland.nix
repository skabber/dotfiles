# Declarative Hyprland desktop configs, shipped to ~/.config via Home Manager.
#
# Source files live in ../config/ (mirroring the XDG layout). After a rebuild
# these appear as symlinks into the nix store — edit them in the repo, not in
# ~/.config. Only imported by hosts that enable Hyprland (modules/desktop.nix).
#
# See docs/hyprland.md for usage.
{ ... }:

{
  xdg.configFile = {
    "hypr/hyprland.lua".source = ../config/hypr/hyprland.lua;
    "hypr/hyprlock.conf".source = ../config/hypr/hyprlock.conf;
    "waybar/config.jsonc".source = ../config/waybar/config.jsonc;
    "waybar/style.css".source = ../config/waybar/style.css;
    "rofi/config.rasi".source = ../config/rofi/config.rasi;
    "mako/config".source = ../config/mako/config;
  };
}
