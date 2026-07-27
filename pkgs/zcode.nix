# ZCode desktop AppImage wrapper.
#
# Runs the prebuilt AppImage through appimage-run (FHS env + Electron --no-sandbox
# so it works on NixOS) and registers the `zcode://` URI scheme handler so the
# in-app OAuth login redirect finds its way back to the app.
#
# The AppImage is fetched from the ZCode CDN by URL + content hash, so eval stays
# pure (no local file in ~/Downloads or the flake). To upgrade, bump `version`
# and refresh `hash` with:
#   nix store prefetch-file --hash-type sha256 <url>
{
  lib,
  stdenvNoCC,
  fetchurl,
  writeShellScriptBin,
  appimage-run,
  makeDesktopItem,
  copyDesktopItems,
}:
let
  version = "3.5.3";
  src = fetchurl {
    url = "https://cdn-zcode.z.ai/zcode/electron/releases/${version}/linux-x64/ZCode-${version}-linux-x64.AppImage";
    hash = "sha256-n+2EQbne1iXfFgUN2zxitSdAhYp9BOEhfgZuYZ8iMt0=";
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
