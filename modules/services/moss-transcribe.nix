# MOSS-Transcribe-Diarize transcription service
# End-to-end speech transcription + speaker diarization via the HF/ROCm backend
# (mtd-subtitle-web): web UI on /, jobs API under /api/jobs

{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.moss-transcribe;

  mossPackage = pkgs.python3.pkgs.callPackage
    ({ buildPythonPackage, fetchFromGitHub, setuptools
     , transformers, safetensors, numpy, av, librosa, numba
     , soundfile, soxr, packaging, fastapi, uvicorn, python-multipart
     }: buildPythonPackage {
      pname = "moss-transcribe-diarize";
      version = "0.1.0";
      pyproject = true;

      src = fetchFromGitHub {
        owner = "OpenMOSS";
        repo = "MOSS-Transcribe-Diarize";
        rev = "e607537b1b870475e7898969d40b864de8b691b6";
        hash = "sha256-D4Xm1xwzOJ8VjD1+iMqilBQclUJbjJhD64jMvizyh2A=";
      };

      build-system = [ setuptools ];

      # torch is intentionally not a dependency here; it comes from the
      # rocmSupport override in pythonEnv so the GPU target set stays pinned.
      dependencies = [
        transformers
        safetensors
        numpy
        av
        librosa
        numba
        soundfile
        soxr
        packaging
        fastapi
        uvicorn
        python-multipart
      ];

      doCheck = false;
    })
    { };

  pythonEnv = pkgs.python3.withPackages (ps: with ps; [
    mossPackage
    (torch.override { rocmSupport = true; })
  ]);
in
{
  options.moss-transcribe = {
    enable = mkEnableOption "MOSS-Transcribe-Diarize transcription service";

    port = mkOption {
      type = types.port;
      default = 7860;
      description = "Port for the web UI and jobs API.";
    };

    host = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = "Bind address for the web UI and jobs API.";
    };

    modelPath = mkOption {
      type = types.str;
      default = "/home/jay/models/MOSS-Transcribe-Diarize";
      description = "Path to the downloaded MOSS-Transcribe-Diarize model directory.";
    };

    device = mkOption {
      type = types.str;
      default = "auto";
      description = "Inference device: auto (GPU if available), cuda, or cpu.";
    };

    dtype = mkOption {
      type = types.enum [ "bf16" "fp16" "fp32" ];
      default = "bf16";
      description = "Model dtype. If bf16 misbehaves on RDNA 2, try fp16 or fp32.";
    };

    maxNewTokens = mkOption {
      type = types.int;
      default = 2048;
      description = "Max generated tokens per job; raise (e.g. 65536) for long audio.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to open the firewall port.";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.moss-transcribe = {
      description = "MOSS-Transcribe-Diarize transcription service";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        HSA_OVERRIDE_GFX_VERSION = "10.3.0";
        HF_HUB_OFFLINE = "1";
      };

      serviceConfig = {
        StateDirectory = "moss-transcribe";
        WorkingDirectory = "/var/lib/moss-transcribe";
        ExecStart = concatStringsSep " " [
          "${pythonEnv}/bin/mtd-subtitle-web"
          "--model ${cfg.modelPath}"
          "--runs-dir /var/lib/moss-transcribe/runs"
          "--host ${cfg.host}"
          "--port ${toString cfg.port}"
          "--device ${cfg.device}"
          "--dtype ${cfg.dtype}"
          "--max-new-tokens ${toString cfg.maxNewTokens}"
        ];
        Restart = "on-failure";
        RestartSec = 10;
      };

      path = [ pkgs.ffmpeg ];
    };

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];
  };
}
