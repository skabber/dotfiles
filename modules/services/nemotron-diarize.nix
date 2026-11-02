# nemotron-diarize: who-spoke-when jobs API (NVIDIA Nemotron 3 Diarization,
# up to 8 speakers) with the same surface as the MOSS-Transcribe jobs API,
# plus optional speaker-attributed transcription (nemotron-3.5-asr-streaming-
# 0.6b, NVIDIA's documented masked-ASR pairing): POST /api/jobs upload -> poll
# -> GET segments (speaker turns, with text + SRT when transcription is on).
# Runs the NeMo Speech toolkit (github NVIDIA-NeMo/Speech, not PyPI — PyPI
# 3.0.0 lacks the RoPE encoder these models need) from a uv venv with CUDA
# torch, mirroring the moss vllm pattern. Models lazy-load on the first job
# (~0.7 GB diarize-only, ~1.9 GB combined — co-resident with the moss engine)
# and unload in-process when idle.
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.nemotron-diarize;

  # Repo tested with Python 3.12; pin so the venv stays stable across nixpkgs
  # python bumps (mirrors moss-transcribe.nix).
  venvPython = pkgs.python312.withPackages (ps: with ps; [ pip ]);

  # When serve is enabled, bind loopback only so tailscaled owns the tailnet
  # IP:port and terminates TLS; a 0.0.0.0 bind would shadow the serve proxy.
  bindHost = if cfg.serve then "127.0.0.1" else cfg.host;
in
{
  options.nemotron-diarize = {
    enable = mkEnableOption "Nemotron 3 Diarization jobs API (who spoke when)";

    autoStart = mkOption {
      type = types.bool;
      default = true;
      description = "Start the service automatically at boot (cheap idle process; the model lazy-loads on the first job).";
    };

    port = mkOption {
      type = types.port;
      default = 7862;
      description = "Public port for the jobs API and web UI.";
    };

    host = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = ''
        Address to bind. When serve is enabled the service always binds
        loopback so Tailscale Serve owns the public listener.
      '';
    };

    modelPath = mkOption {
      type = types.str;
      default = "/home/jay/dotfiles/models/Nemotron-3-Diarization/Nemotron-3-Diarization.nemo";
      description = "Local path to the .nemo checkpoint.";
    };

    enableTranscription = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Speaker-attributed transcription with nemotron-3.5-asr-streaming-0.6b
        (masked-ASR pairing from the diarization model card): segments carry
        text, SRT export available, jobs accept transcribe=0 to opt out.
        Adds ~2.4 GB of checkpoint on disk and ~1.2 GB VRAM when loaded.
      '';
    };

    asrModelPath = mkOption {
      type = types.str;
      default = "/home/jay/dotfiles/models/nemotron-3.5-asr-streaming-0.6b/nemotron-3.5-asr-streaming-0.6b.nemo";
      description = "Local path to the ASR .nemo checkpoint (used when enableTranscription is on).";
    };

    nemoSpec = mkOption {
      type = types.str;
      default = "nemo-toolkit[asr] @ git+https://github.com/NVIDIA-NeMo/Speech.git@16b0ff2584c6";
      description = "Pinned nemo-toolkit install spec. Must be the NVIDIA-NeMo/Speech repo (or a release with RoPE encoder support): PyPI 3.0.0 cannot load this model.";
    };

    device = mkOption {
      type = types.enum [ "cuda" "cpu" ];
      default = "cuda";
      description = "Inference device (cpu is the emergency fallback, ~60x slower than the eager CUDA path).";
    };

    idleUnloadMinutes = mkOption {
      type = types.ints.unsigned;
      default = 30;
      description = "Unload the resident model after this many idle minutes to hand VRAM back (0 disables).";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to open the firewall port.";
    };

    serve = mkOption {
      type = types.bool;
      default = false;
      description = "Expose over HTTPS via Tailscale Serve (https://<host>.tail69fe1.ts.net:<port>). Turn off when gpu-gateway fronts this service.";
    };
  };

  config = mkIf cfg.enable {
    # One-shot unit to create the venv and install the pinned NeMo Speech
    # toolkit with CUDA torch (nemo-toolkit is not in nixpkgs).
    systemd.services.nemotron-diarize-setup = {
      description = "Nemotron diarization venv setup";
      wantedBy = optionals cfg.autoStart [ "multi-user.target" ];
      path = [ pkgs.uv pkgs.git pkgs.bash pkgs.coreutils ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        StateDirectory = "nemotron-diarize";
        ExecStart = pkgs.writeShellScript "nemotron-diarize-setup" ''
          set -e
          VENV="/var/lib/nemotron-diarize/venv"
          PY="${venvPython}/bin/python"
          want="$("$PY" -c 'import sys; print("%d.%d" % sys.version_info[:2])')"
          have=""
          if [ -x "$VENV/bin/python" ]; then
            have="$("$VENV/bin/python" -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null || true)"
          fi
          # Recreate when missing, stale (symlink into a GC'd nix store path),
          # or built against a different python minor than the pinned one.
          if [ "$have" != "$want" ]; then
            rm -rf "$VENV"
            "$PY" -m venv "$VENV"
          fi
          ${pkgs.uv}/bin/uv pip install --python "$VENV/bin/python" \
            "${cfg.nemoSpec}" \
            fastapi uvicorn python-multipart \
            --torch-backend=auto
        '';
      };
    };

    systemd.services.nemotron-diarize = {
      description = "Nemotron 3 Diarization jobs API";
      after = [ "network.target" "nemotron-diarize-setup.service" ];
      requires = [ "nemotron-diarize-setup.service" ];
      wantedBy = optionals cfg.autoStart [ "multi-user.target" ];

      environment = {
        HF_HUB_OFFLINE = "1";
        # stdenv libstdc++ for pip-installed torch, opengl-driver for libcuda.
        LD_LIBRARY_PATH = "${pkgs.stdenv.cc.cc.lib}/lib:/run/opengl-driver/lib";
        # The Speech repo compiles flex_attention; the compiled kernel fails
        # against torch 2.14 + cu132 (block-mask subgraph error). Eager
        # measures RTFx ~60 diarize-only / ~5.5 combined on the RTX 3080.
        TORCHDYNAMO_DISABLE = "1";
        # Stops triton from shelling out to /sbin/ldconfig (NixOS).
        TRITON_LIBCUDA_PATH = "/run/opengl-driver/lib";
        # Both models load next to the resident moss vLLM engine; expandable
        # segments avoid fragmentation OOMs at that headroom.
        PYTORCH_CUDA_ALLOC_CONF = "expandable_segments:True";
      };

      serviceConfig = {
        StateDirectory = "nemotron-diarize";
        WorkingDirectory = "/var/lib/nemotron-diarize";
        ExecStart = concatStringsSep " " ([
          "/var/lib/nemotron-diarize/venv/bin/python" "${./nemotron-diarize-web.py}"
          "--model ${cfg.modelPath}"
          "--runs-dir /var/lib/nemotron-diarize/runs"
          "--host ${bindHost}"
          "--port ${toString cfg.port}"
          "--device ${cfg.device}"
          "--idle-unload-minutes ${toString cfg.idleUnloadMinutes}"
        ] ++ optionals cfg.enableTranscription [
          "--asr-model ${cfg.asrModelPath}"
        ]);
        Restart = "on-failure";
        RestartSec = 10;
      };
      # Cap retries: a crash-looping GPU service cycling CUDA contexts has
      # hard-locked the driver before (2026-09-30 postmortem).
      unitConfig = {
        StartLimitIntervalSec = 600;
        StartLimitBurst = 5;
      };

      path = [ pkgs.ffmpeg ];
    };

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];

    systemd.services.tailscale-serve-nemotron-diarize = mkIf cfg.serve {
      description = "Tailscale Serve for Nemotron diarization";
      after = [ "tailscaled.service" "nemotron-diarize.service" ];
      wants = [ "tailscaled.service" "nemotron-diarize.service" ];
      wantedBy = optionals cfg.autoStart [ "multi-user.target" ];
      path = [ pkgs.tailscale ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStartPre = "${pkgs.bash}/bin/bash -c 'for i in $(seq 1 30); do tailscale status >/dev/null 2>&1 && exit 0; sleep 1; done; exit 1'";
        # Retry: concurrent serve units racing one config write get an etag
        # mismatch ("Another client is changing the serve config").
        ExecStart = "${pkgs.bash}/bin/bash -c 'for i in $(seq 1 5); do ${pkgs.tailscale}/bin/tailscale serve --bg --https=${toString cfg.port} http://127.0.0.1:${toString cfg.port} && exit 0; sleep 2; done; exit 1'";
        ExecStop = "${pkgs.tailscale}/bin/tailscale serve --https=${toString cfg.port} off";
      };
    };
  };
}
