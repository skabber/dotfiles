{ stdenv, lib, fetchurl, makeWrapper, glibc, libsecret }:

stdenv.mkDerivation rec {
  pname = "proton-drive-cli";
  version = "0.4.6";

  src = fetchurl {
    url = "https://proton.me/download/drive/cli/${version}/linux-x64/proton-drive";
    hash = "sha256-iaVBMaCBHkLqGOxDBz1us0fYD1lO0CJgCbuUEY9M2oY=";
  };

  nativeBuildInputs = [ makeWrapper ];

  dontUnpack = true;
  dontBuild = true;
  # patchelf / autoPatchelfHook corrupt Bun standalone binaries by shifting
  # the section offsets that Bun uses to locate its embedded filesystem.
  dontStrip = true;
  dontPatchELF = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 $src $out/libexec/proton-drive-unwrapped

    # Invoke via the Nix glibc interpreter to avoid needing nix-ld.
    # LD_LIBRARY_PATH (not --library-path) is required so that runtime
    # dlopen() calls for libsecret also resolve correctly; --library-path
    # only affects initial ELF loading, not subsequent dlopen.
    makeWrapper ${glibc}/lib/ld-linux-x86-64.so.2 $out/bin/proton-drive \
      --set PROTON_DRIVE_UNSAFE_SECRETS "1" \
      --set LD_LIBRARY_PATH "${lib.makeLibraryPath [ glibc libsecret ]}" \
      --add-flags "$out/libexec/proton-drive-unwrapped"

    runHook postInstall
  '';

  meta = with lib; {
    description = "Official CLI for Proton Drive — end-to-end encrypted cloud storage";
    homepage = "https://proton.me/drive";
    license = licenses.unfreeRedistributable;
    platforms = [ "x86_64-linux" ];
    mainProgram = "proton-drive";
  };
}
