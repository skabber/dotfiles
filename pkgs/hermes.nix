# Hermes Agent desktop wrapper.
#
# Hermes (https://github.com/NousResearch/hermes-agent) is a Python+Electron
# agent whose desktop app has no prebuilt binary — install.sh clones the repo
# and builds apps/desktop via `npm run pack` into a mutable dir. We can't build
# it in the Nix store: the Electron chrome-sandbox helper needs setuid
# (chown root:root && chmod 4755), which the read-only store forbids. So, like
# zcode, this package ships only a launcher + desktop item; the user runs
# `hermes-install` once per host to populate ~/.hermes.
#
# The launcher passes --no-sandbox because the user-owned install dir can't
# hold a setuid chrome-sandbox either. Same trade-off as the zcode wrapper.
{
  lib,
  stdenvNoCC,
  writeShellScriptBin,
  curl,
  bash,
  makeDesktopItem,
  copyDesktopItems,
}:
let
  hermesHome = "$HOME/.hermes";
  desktopApp = "${hermesHome}/apps/desktop/release/linux-unpacked/Hermes";

  installer = writeShellScriptBin "hermes-install" ''
    set -euo pipefail
    echo "Installing Hermes Agent (desktop) into ${hermesHome} ..."
    echo "This clones the repo and builds the Electron app (~150MB, 1-3 min)."
    ${lib.getExe curl} -fsSL https://hermes-agent.nousresearch.com/install.sh \
      | ${lib.getExe bash} -s -- --include-desktop --non-interactive
    if [ ! -x "${desktopApp}" ]; then
      echo "Install finished but the desktop app was not found at:" >&2
      echo "  ${desktopApp}" >&2
      echo "Re-run with --include-desktop, or build manually:" >&2
      echo "  cd ${hermesHome}/apps/desktop && npm run pack" >&2
      exit 1
    fi
    echo "Done. Launch with: hermes"
  '';

  bin = writeShellScriptBin "hermes" ''
    set -euo pipefail
    if [ ! -x "${desktopApp}" ]; then
      echo "Hermes desktop app not found at:" >&2
      echo "  ${desktopApp}" >&2
      echo "Run hermes-install first to build it." >&2
      exit 1
    fi
    exec "${desktopApp}" --no-sandbox "$@"
  '';

  desktopItem = makeDesktopItem {
    name = "hermes";
    desktopName = "Hermes Agent";
    genericName = "AI Agent";
    comment = "Hermes Agent Desktop App";
    exec = "hermes %U";
    icon = "hermes";
    terminal = false;
    categories = [ "Development" ];
    startupWMClass = "Hermes";
  };
in
stdenvNoCC.mkDerivation {
  pname = "hermes";
  version = "0.18.0";

  nativeBuildInputs = [ copyDesktopItems ];
  desktopItems = [ desktopItem ];

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm555 ${bin}/bin/hermes $out/bin/hermes
    install -Dm555 ${installer}/bin/hermes-install $out/bin/hermes-install
    mkdir -p $out/share/icons
    cp -r ${./hermes/icons/hicolor} $out/share/icons/hicolor
    runHook postInstall
  '';

  meta = with lib; {
    description = "Hermes Agent desktop app, wrapped for NixOS";
    mainProgram = "hermes";
    platforms = platforms.linux;
  };
}
