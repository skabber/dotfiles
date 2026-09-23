# Google AX — declarative orchestrator for autonomous agent workloads
# https://github.com/google/ax
{
  lib,
  buildGo127Module,
  fetchFromGitHub,
}:

buildGo127Module rec {
  pname = "ax";
  version = "0.3.0";

  src = fetchFromGitHub {
    owner = "google";
    repo = "ax";
    tag = "v${version}";
    hash = "sha256-mGSQ4QsYLdeKDtVMBODCulqQQ0Ze0NjeADPhB6edaYU=";
  };

  vendorHash = "sha256-iC/X6Bg1M7Pn3dT1zWs2YxuPfgl9ZKNEYQsBisIQguY=";

  subPackages = [ "cmd/ax" ];

  ldflags = [
    "-s"
    "-w"
  ];

  meta = {
    description = "Declarative orchestrator to run autonomous agent workloads in sandboxes at scale";
    homepage = "https://github.com/google/ax";
    changelog = "https://github.com/google/ax/releases/tag/v${version}";
    license = lib.licenses.asl20;
    mainProgram = "ax";
  };
}
