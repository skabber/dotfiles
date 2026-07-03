# ZCode desktop AppImage wrapper.
#
# Runs the prebuilt AppImage through appimage-run (FHS env + Electron --no-sandbox
# so it works on NixOS) and registers the `zcode://` URI scheme handler so the
# in-app OAuth login redirect finds its way back to the app.
#
# The AppImage is pulled from the ZCode CDN via fetchurl — pure-eval safe and
# binary-cached, so no local file needs to exist on the build host. When you
# upgrade, bump `version` and the URL below, then recompute the hash:
#   nix-prefetch-url --type sha256 <url> | tail -1 | xargs -I{} nix hash to-sri --type sha256 {}
{
  lib,
  stdenvNoCC,
  writeShellScriptBin,
  appimage-run,
  makeDesktopItem,
  copyDesktopItems,
  fetchurl,
}:
let
  version = "3.2.4";
  src = fetchurl {
    url = "https://cdn-zcode.z.ai/zcode/electron/releases/3.2.4/ZCode-3.2.4-linux-x64.AppImage";
    hash = "sha256-J91o4SgCYOsJ4jUjyA7eVgkRXAQasXljrvLisqe+NeQ=";
  };

  bin = writeShellScriptBin "zcode" ''
    set -euo pipefail
    self="$(cd "$(dirname "''${BASH_SOURCE[0]}")" && pwd)/$(basename "''${BASH_SOURCE[0]}")"

    # ZCode (Electron) calls setAsDefaultProtocolClient('zcode', process.execPath)
    # at startup, rewriting ~/.local/share/applications/zcode.desktop with an Exec
    # that points at the raw AppImage. The raw AppImage can't run on NixOS (no
    # libfuse in nix-ld + missing glibc/loader libs), so the zcode:// OAuth
    # callback would fail to relaunch the app. Rewrite it back to this wrapper
    # shortly after launch — auth happens after startup, so the handler is
    # correct by then.
    (
      for _ in $(seq 1 60); do
        f="$HOME/.local/share/applications/zcode.desktop"
        if [[ -f "$f" ]] && grep -q '^Exec=' "$f"; then
          sleep 2
          tmp="''${f}.fix.$''$"
          awk -v e="Exec=''${self} %U" '/^Exec=/{print e; next} {print}' "$f" > "$tmp" && mv "$tmp" "$f"
          break
        fi
        sleep 0.5
      done
    ) &

    exec ${lib.getExe appimage-run} ${src} --no-sandbox "$@"
  '';

  desktopItem = makeDesktopItem {
    name = "zcode";
    desktopName = "ZCode";
    genericName = "Code Editor";
    comment = "ZCode Desktop App";
    exec = "zcode %U";
    icon = "zcode";
    terminal = false;
    categories = [ "Development" ];
    startupWMClass = "ZCode";
    mimeTypes = [ "x-scheme-handler/zcode" ];
  };
in
stdenvNoCC.mkDerivation {
  pname = "zcode";
  inherit version;

  nativeBuildInputs = [ copyDesktopItems ];
  desktopItems = [ desktopItem ];

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm555 ${bin}/bin/zcode $out/bin/zcode
    mkdir -p $out/share/icons
    cp -r ${./zcode/icons/hicolor} $out/share/icons/hicolor
    runHook postInstall
  '';

  meta = with lib; {
    description = "ZCode desktop AppImage, wrapped for NixOS";
    mainProgram = "zcode";
    platforms = platforms.linux;
  };
}
