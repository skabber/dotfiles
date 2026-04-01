# WhisperX Transcription Service
# HTTP + WebSocket transcription powered by WhisperX with CUDA support

{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.whisperx;

  pythonEnv = pkgs.python3.withPackages (ps: with ps; [ pip virtualenv ]);

  cudaLibPath = lib.makeLibraryPath [
    pkgs.cudaPackages.cudatoolkit
    pkgs.cudaPackages.cudnn
    pkgs.stdenv.cc.cc.lib
  ];
in
{
  options.whisperx = {
    enable = mkEnableOption "WhisperX transcription service";

    port = mkOption {
      type = types.port;
      default = 8000;
      description = "Port for the WhisperX HTTP/WebSocket server.";
    };

    model = mkOption {
      type = types.str;
      default = "large-v3";
      description = "Whisper model name.";
    };

    batchSize = mkOption {
      type = types.int;
      default = 4;
      description = "Transcription batch size.";
    };

    hfTokenFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to a file containing the HuggingFace token for diarization.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to open the firewall port.";
    };

    sourceDir = mkOption {
      type = types.str;
      default = "/home/jay/Projects/whisperx-service";
      description = "Path to the whisperx-service source directory.";
    };
  };

  config = mkIf cfg.enable {
    # One-shot unit to create venv and install deps
    systemd.services.whisperx-setup = {
      description = "WhisperX venv setup";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        StateDirectory = "whisperx";
        Environment = [
          "LD_LIBRARY_PATH=${cudaLibPath}:/run/opengl-driver/lib"
          "CUDA_PATH=${pkgs.cudaPackages.cudatoolkit}"
        ];
        ExecStart = pkgs.writeShellScript "whisperx-setup" ''
          set -e
          VENV="/var/lib/whisperx/venv"
          if [ ! -d "$VENV" ]; then
            ${pythonEnv}/bin/python -m venv "$VENV"
          fi
          source "$VENV/bin/activate"
          pip install --quiet -r ${cfg.sourceDir}/requirements.txt
        '';
      };
      path = [ pkgs.git pkgs.ffmpeg pkgs.sox pkgs.bash pkgs.coreutils ];
    };

    systemd.services.whisperx = {
      description = "WhisperX Transcription Service";
      after = [ "network.target" "whisperx-setup.service" ];
      requires = [ "whisperx-setup.service" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        WHISPERX_MODEL = cfg.model;
        WHISPERX_BATCH_SIZE = toString cfg.batchSize;
        LD_LIBRARY_PATH = "${cudaLibPath}:/run/opengl-driver/lib";
        CUDA_PATH = "${pkgs.cudaPackages.cudatoolkit}";
      };

      serviceConfig = {
        StateDirectory = "whisperx";
        WorkingDirectory = toString cfg.sourceDir;
        ExecStart = "${pkgs.writeShellScript "whisperx-run" ''
          source /var/lib/whisperx/venv/bin/activate
          ${optionalString (cfg.hfTokenFile != null) ''
            export HF_TOKEN=$(cat ${cfg.hfTokenFile})
          ''}
          exec uvicorn main:app --host 0.0.0.0 --port ${toString cfg.port}
        ''}";
        Restart = "on-failure";
        RestartSec = 10;
      };

      path = [ pkgs.git pkgs.ffmpeg pkgs.sox pkgs.bash pkgs.coreutils ];
    };

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];
  };
}
