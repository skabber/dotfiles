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

    # Second compositor config for the SDDM "Hyprland (Ambxst)" entry
    # (modules/desktop.nix sets HYPRLAND_CONFIG here). Ambxst's generated
    # settings load first, then the regular config runs on top, so this
    # session defaults to identical binds/plugins/gestures. Until
    # `ambxst install hyprland` generates its file this is a no-op.
    "hypr/hyprland-ambxst.lua".text = ''
      local home = os.getenv("HOME")

      local ambxst = loadfile(home .. "/.local/share/ambxst/hyprland.lua")
      if ambxst then
          ambxst()
          -- consumed by the main config's autostart to skip the components
          -- Ambxst replaces (bar, notifications, wallpaper)
          ambxst_active = true
          -- Hyprland fires every bind matching a key (no dedupe), so drop
          -- Ambxst's copies of keys the main config owns before loading it.
          -- Keys Ambxst keeps: Super alone (launcher), Super+D, Super+Esc,
          -- Super+Shift+C/A, Super+Alt+B, Super+Alt+[0-9]; workspace binds
          -- mirror ours exactly and are left as harmless duplicates.
          local ambxstUnbind = {
              "SUPER + SPACE",
              "SUPER + TAB",
              "SUPER + A",
              "SUPER + C",
              "SUPER + F",
              "SUPER + L",
              "SUPER + N",
              "SUPER + S",
              "SUPER + T",
              "SUPER + V",
              "SUPER + COMMA",
              "SUPER + PERIOD",
              "SUPER + SHIFT + B",
              "SUPER + SHIFT + R",
              "SUPER + SHIFT + S",
          }
          for _, key in ipairs(ambxstUnbind) do
              hl.unbind(key)
          end
      end

      dofile(home .. "/.config/hypr/hyprland.lua")
    '';
  };

  # Ambxst's screenshot tool opens its folder via `xdg-open <dir>`; make that
    # (and any other folder-open on the Hyprland hosts) land in yazi in a
    # terminal. Super+E still launches nautilus directly; the GNOME host is
    # unaffected (this file is only imported by Hyprland hosts)
    xdg.desktopEntries.yazi = {
      name = "Yazi";
      exec = "ghostty -e yazi %f";
      mimeType = [ "inode/directory" ];
    };
    xdg.mimeApps = {
      enable = true;
      defaultApplications."inode/directory" = [ "yazi.desktop" ];
    };
}
