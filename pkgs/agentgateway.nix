# Agentgateway: AI agent connectivity proxy (LLM/MCP/A2A gateway).
# Upstream ships static musl binaries, so no patchelf or nix-ld is needed.
{ stdenv, lib, fetchurl }:

stdenv.mkDerivation rec {
  pname = "agentgateway";
  version = "1.5.0";

  gatewayBin = fetchurl {
    url = "https://github.com/agentgateway/agentgateway/releases/download/v${version}/agentgateway-linux-amd64";
    hash = "sha256-2spc2nboxasMGnWRL+zy1jZQlUA/gQ23ICnEnRSjfns=";
  };

  agctlBin = fetchurl {
    url = "https://github.com/agentgateway/agentgateway/releases/download/v${version}/agctl-linux-amd64";
    hash = "sha256-GftulImRx+tDxs7p13SGhaSjcuVapl2/3ElJKlui/nY=";
  };

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    install -Dm555 $gatewayBin $out/bin/agentgateway
    install -Dm555 $agctlBin $out/bin/agctl

    runHook postInstall
  '';

  meta = with lib; {
    description = "Open source AI agent connectivity gateway (LLM, MCP, A2A)";
    homepage = "https://agentgateway.dev";
    license = licenses.asl20;
    platforms = [ "x86_64-linux" ];
    mainProgram = "agentgateway";
  };
}
