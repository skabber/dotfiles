# Orca IDE desktop AppImage wrapper.
#
# Fetched from the pinned GitHub release by URL + content hash, so eval stays
# pure. To upgrade, bump `version` and refresh `hash` with:
#   nix store prefetch-file --hash-type sha256 https://github.com/stablyai/orca/releases/download/v<version>/orca-linux.AppImage
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
  version = "1.4.179";
  src = fetchurl {
    url = "https://github.com/stablyai/orca/releases/download/v${version}/orca-linux.AppImage";
    hash = "sha256-B4CEhW22bSmya1dguIAo3pWv/NdxQxNZ7uNpJCl7EN8=";
  };

  bin = writeShellScriptBin "orca" ''
    exec ${lib.getExe appimage-run} ${src} --no-sandbox "$@"
  '';

  desktopItem = makeDesktopItem {
    name = "orca-ide";
    desktopName = "Orca";
    genericName = "IDE";
    comment = "Next-gen IDE for parallel agentic development";
    exec = "orca %U";
    icon = "orca-ide";
    terminal = false;
    categories = [ "Development" ];
    startupWMClass = "orca";
  };
in
stdenvNoCC.mkDerivation {
  pname = "orca";
  inherit version;

  nativeBuildInputs = [ copyDesktopItems ];
  desktopItems = [ desktopItem ];

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm555 ${bin}/bin/orca $out/bin/orca
    mkdir -p $out/share/icons
    cp -r ${./orca/icons/hicolor} $out/share/icons/hicolor
    runHook postInstall
  '';

  meta = with lib; {
    description = "Orca IDE desktop AppImage, wrapped for NixOS";
    mainProgram = "orca";
    platforms = platforms.linux;
  };
}
