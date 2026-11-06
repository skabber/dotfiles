# Eglantine (Eden Switch emulator frontend, Qt6 AppImage) — FHS runner
# Bundles its own Qt6/ffmpeg; needs host libgpg-error, GL, Vulkan.
# Usage: eglantine [AppImage] [args...] — defaults to newest eglantine*.AppImage in ~/Downloads
{
  lib,
  buildFHSEnv,
  appimageTools,
  writeShellScript,
}:
let
  runScript = writeShellScript "eglantine-run" ''
    unset QT_QPA_PLATFORMTHEME QT_PLUGIN_PATH QT_IM_MODULE
    img="''${1:-}"
    if [ -z "$img" ]; then
      img="$(ls -t "$HOME"/Downloads/eglantine*.AppImage 2>/dev/null | head -1 || true)"
    fi
    if [ -z "$img" ]; then
      echo "eglantine: pass an AppImage path or drop one in ~/Downloads" >&2
      exit 1
    fi
    if [ $# -gt 0 ] && [ "''${1:-}" != "" ]; then shift; fi
    exec appimage-exec.sh "$img" "$@"
  '';
in
buildFHSEnv {
  pname = "eglantine";
  version = "0";

  targetPkgs = pkgs: with pkgs; [
    appimageTools.appimage-exec
    libgpg-error
    libusb1
    libglvnd
    mesa
    libdrm
    wayland
    libxi
    xorg.libX11
    xorg.libxcb
    xorg.libXext
    xorg.libXfixes
    xorg.libXrender
    xkeyboard-config
    fontconfig
    freetype
    fribidi
    harfbuzz
    zlib
    dejavu_fonts
    vulkan-loader
  ];

  inherit runScript;

  meta = {
    description = "FHS runner for the Eglantine (Eden emulator) AppImage";
    license = lib.licenses.gpl3Plus;
    mainProgram = "eglantine";
    platforms = lib.platforms.linux;
  };
}
