# Shared desktop base: SDDM greeter (astronaut theme), GNOME + COSMIC sessions, PipeWire, Wayland
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

  # chili is Qt Quick Controls 1 (Qt5-only); nixpkgs' sddm is Qt6 now, so use
  # astronaut — the closest actively-maintained equivalent. Its QML deps must
  # go in extraPackages so the greeter wrapper can resolve them.
  services.displayManager.sddm = {
    enable = true;
    theme = "sddm-astronaut-theme";
    extraPackages = with pkgs.kdePackages; [
      qtmultimedia
      qtvirtualkeyboard
    ];
  };

  # Either password or fingerprint at the greeter, without pam_fprintd's
  # ~30s finger-wait blocking password logins: NixOS orders pam_fprintd before
  # pam_unix, so override sddm's auth stack to check the password first and
  # only fall back to a swipe on empty/wrong password. Mirrors the generated
  # `login` auth rules (unix-early prompts and sets the authtok; keyring must
  # capture it before the sufficient rule short-circuits the stack). Swipe by
  # logging in with an empty password; a typo pays one fprintd timeout before
  # the retry. TTY logins stay password-only.
  security.pam.services.login.fprintAuth = false;
  security.pam.services.sddm.text = lib.mkForce ''
    auth      optional    ${pkgs.pam}/lib/security/pam_unix.so likeauth nullok
    auth      optional    ${pkgs.gnome-keyring}/lib/security/pam_gnome_keyring.so
    auth      sufficient  ${pkgs.pam}/lib/security/pam_unix.so likeauth nullok try_first_pass
    auth      sufficient  ${pkgs.fprintd}/lib/security/pam_fprintd.so
    auth      required    ${pkgs.pam}/lib/security/pam_deny.so
    account   include     login
    password  substack    login
    session   include     login
  '';

  services.desktopManager.gnome.enable = true;
  services.desktopManager.cosmic.enable = true;

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
    sddm-astronaut
    xwayland
    wayland-protocols
    wayland-utils
    wl-clipboard
    wlroots
    glycin-thumbnailer
    libheif
  ];
}
