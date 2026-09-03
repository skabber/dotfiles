# Shared GNOME Desktop / PipeWire / Wayland base configuration
{ config, pkgs, lib, ... }:

{
  programs.gdk-pixbuf.modulePackages = [
    pkgs.librsvg
    pkgs.webp-pixbuf-loader
    pkgs.libheif.lib
  ];

  # programs.gdk-pixbuf.modulePackages generates a merged loaders.cache and
  # exposes it via environment.sessionVariables, but wrapGAppsHook bakes
  # GDK_PIXBUF_MODULE_FILE into each app's binary wrapper at build time —
  # using whichever cache the gdk-pixbuf setup-hook finds longest (librsvg's
  # internal cache wins, which lacks webp/heif). Override sushi so its build
  # sees the full merged cache and bakes the correct path into the wrapper.
  nixpkgs.overlays = [
    (final: prev: {
      gdkPixbufLoadersCache = prev.gnome._gdkPixbufCacheBuilder_DO_NOT_USE {
        extraLoaders = [ prev.librsvg prev.webp-pixbuf-loader prev.libheif.lib ];
      };

      sushi = prev.sushi.overrideAttrs (_: {
        GDK_PIXBUF_MODULE_FILE = final.gdkPixbufLoadersCache;
      });
    })
  ];

  # GNOME Shell creates its Power Mode quick-settings toggle once at session
  # start with no retry. ppd 0.30 is dbus-activated only and ordered after
  # multi-user/display-manager, so on slow boots the activation times out and
  # the toggle never appears. Start it eagerly at boot instead.
  systemd.services.power-profiles-daemon = {
    after = lib.mkForce [ "dbus.socket" ];
    wantedBy = [ "multi-user.target" ];
  };

  services.xserver.enable = true;

  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  services.xserver = {
    xkb.layout = "us";
    xkb.variant = "";
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
    wlroots
    glycin-thumbnailer
    libheif
  ];
}
