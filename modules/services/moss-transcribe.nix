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
  # When serve is enabled, bind loopback only so tailscaled owns the tailnet
  # IP:port and terminates TLS; a 0.0.0.0 bind would shadow the serve proxy.
  bindHost = if cfg.serve then "127.0.0.1" else cfg.host;
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

    serve = mkOption {
      type = types.bool;
      default = false;
      description = "Expose over HTTPS via Tailscale Serve (https://<host>.tail69fe1.ts.net:<port>).";
    };

    idleUnloadMinutes = mkOption {
      type = types.ints.unsigned;
      default = 30;
      description = ''
        Restart the service after this many idle minutes so the resident
        model releases its ~2 GB of VRAM (the service lazy-loads on the
        first job and has no unload API; a restart costs ~7 s on the next
        job). 0 disables the idle unload.
      '';
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
          "--host ${bindHost}"
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

    systemd.services.tailscale-serve-moss-transcribe = mkIf cfg.serve {
      description = "Tailscale Serve for MOSS-Transcribe-Diarize";
      after = [ "tailscaled.service" "moss-transcribe.service" ];
      wants = [ "tailscaled.service" "moss-transcribe.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.tailscale ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStartPre = "${pkgs.bash}/bin/bash -c 'for i in $(seq 1 30); do tailscale status >/dev/null 2>&1 && exit 0; sleep 1; done; exit 1'";
        ExecStart = "${pkgs.tailscale}/bin/tailscale serve --bg --https=${toString cfg.port} http://127.0.0.1:${toString cfg.port}";
        ExecStop = "${pkgs.tailscale}/bin/tailscale serve --https=${toString cfg.port} off";
      };
    };

    # Idle unload: the service lazy-loads its model on the first job and then
    # holds ~2 GB of VRAM forever (no unload API). When nothing has touched
    # it for idleUnloadMinutes, restart the unit to hand the VRAM back to
    # Ollama summarization. A model load always emits the "MOSS attention"
    # probe lines to the journal, so their presence since the unit started
    # means the model is still resident.
    systemd.services.moss-idle-unload = mkIf (cfg.idleUnloadMinutes > 0) {
      description = "Release the resident MOSS model's VRAM after idle";
      serviceConfig.Type = "oneshot";
      path = [ pkgs.curl pkgs.jq pkgs.findutils pkgs.systemd ];
      script = ''
        base="http://127.0.0.1:${toString cfg.port}"
        # A queued/running/rendering job means the GPU is (about to be) busy.
        if curl -sf "$base/api/jobs" \
            | jq -e '[.jobs[] | select(.status == "queued" or .status == "running" or .status == "rendering")] | length > 0' \
            >/dev/null 2>&1; then
          exit 0
        fi
        # Recent job activity (run files still being written)? Keep it warm.
        if [ -n "$(find /var/lib/moss-transcribe/runs -type f -newermt '${toString cfg.idleUnloadMinutes} minutes ago' -print -quit 2>/dev/null)" ]; then
          exit 0
        fi
        # Model still loaded in the current process?
        started="$(systemctl show -p ActiveEnterTimestamp --value moss-transcribe.service)"
        if journalctl -u moss-transcribe --since "$started" --no-pager 2>/dev/null | grep -q "MOSS attention"; then
          echo "moss idle for ${toString cfg.idleUnloadMinutes}m with the model loaded — restarting to release VRAM"
          systemctl try-restart moss-transcribe.service
        fi
      '';
    };

    systemd.timers.moss-idle-unload = mkIf (cfg.idleUnloadMinutes > 0) {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*:0/10";
        Persistent = true;
      };
    };
  };
}
