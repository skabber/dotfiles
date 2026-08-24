# MOSS-Transcribe-Diarize service
# OpenAI-compatible /v1/audio/transcriptions endpoint served via vLLM with CUDA

{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.moss-transcribe;

  # Repo is tested with Python 3.12 + Transformers 5.x; pin so the venv stays
  # stable across nixpkgs python bumps (mirrors whisperx.nix).
  pythonEnv = pkgs.python312.withPackages (ps: with ps; [ pip ]);
in
{
  options.moss-transcribe = {
    enable = mkEnableOption "MOSS-Transcribe-Diarize vLLM transcription service";

    port = mkOption {
      type = types.port;
      default = 8010;
      description = "Port for the OpenAI-compatible transcription API.";
    };

    host = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Address to bind. Loopback by default so Tailscale Serve owns the public listener (a 0.0.0.0 bind conflicts with the serve proxy on the tailscale IPs).";
    };

    modelPath = mkOption {
      type = types.str;
      default = "/home/jay/dotfiles/models/MOSS-Transcribe-Diarize";
      description = "Local path to the model snapshot (must include the custom code files).";
    };

    modelName = mkOption {
      type = types.str;
      default = "MOSS-Transcribe-Diarize";
      description = "Name the model is served under (used in API requests).";
    };

    gpuMemoryUtilization = mkOption {
      type = types.float;
      default = 0.6;
      description = "Fraction of GPU memory vLLM may use (GPU is shared with the desktop and whisperx).";
    };

    maxModelLen = mkOption {
      type = types.int;
      default = 32768;
      description = "Maximum sequence length. Audio is ~375 tokens per 30s, so 32768 covers ~40 minutes per request. Must fit in the KV cache budget.";
    };

    maxBatchedTokens = mkOption {
      type = types.int;
      default = 16384;
      description = "Scheduler token budget; also sizes the encoder cache, which caps audio length per request (~12.5 tokens/s of audio). 16384 ≈ 22 minutes.";
    };

    vllmIndexUrl = mkOption {
      type = types.str;
      default = "https://wheels.vllm.ai/68b4a1d582818e67adc903bf1b8fc5a5447da2fa/cu130";
      description = "Pinned vLLM nightly wheel index that includes the MOSS-Transcribe-Diarize model registration.";
    };

    extraArgs = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Extra arguments passed to `vllm serve`.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to open the firewall port.";
    };

    tailscaleServe = mkOption {
      type = types.bool;
      default = false;
      description = "Expose the service via Tailscale Serve at https://nixos.tail69fe1.ts.net:<port>.";
    };
  };

  config = mkIf cfg.enable {
    # One-shot unit to create venv and install the pinned vLLM nightly with CUDA torch
    systemd.services.moss-transcribe-setup = {
      description = "MOSS-Transcribe-Diarize venv setup";
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.uv pkgs.bash pkgs.coreutils ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        StateDirectory = "moss-transcribe";
        ExecStart = pkgs.writeShellScript "moss-transcribe-setup" ''
          set -e
          VENV="/var/lib/moss-transcribe/venv"
          PY="${pythonEnv}/bin/python"
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
            "vllm[audio]" \
            --torch-backend=auto \
            --extra-index-url ${cfg.vllmIndexUrl}
        '';
      };
    };

    systemd.services.moss-transcribe = {
      description = "MOSS-Transcribe-Diarize vLLM Server";
      after = [ "network.target" "moss-transcribe-setup.service" ];
      requires = [ "moss-transcribe-setup.service" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        # Model is loaded from a local snapshot; never touch the hub.
        HF_HUB_OFFLINE = "1";
        # stdenv libstdc++ for pip-installed torch, opengl-driver for libcuda.
        # TRITON_LIBCUDA_PATH stops triton from shelling out to /sbin/ldconfig.
        LD_LIBRARY_PATH = "${pkgs.stdenv.cc.cc.lib}/lib:/run/opengl-driver/lib";
        TRITON_LIBCUDA_PATH = "/run/opengl-driver/lib";
        # Triton JIT needs a C compiler on the unit's PATH (systemd units don't
        # inherit /run/current-system/sw/bin).
        CC = "${pkgs.stdenv.cc}/bin/cc";
        CXX = "${pkgs.stdenv.cc}/bin/c++";
        # FlashInfer's JIT sampler wants nvcc; greedy transcription doesn't need it.
        VLLM_USE_FLASHINFER_SAMPLER = "0";
        # Keep torch.compile/triton caches in the state dir instead of /root.
        VLLM_CACHE_ROOT = "/var/lib/moss-transcribe/cache";
        # Allow decoding files up to 22 min (default 600s guard would reject them).
        VLLM_MAX_AUDIO_DECODE_DURATION_S = toString (cfg.maxBatchedTokens * 60 / 750);
      };

      serviceConfig = {
        StateDirectory = "moss-transcribe";
        ExecStart = pkgs.writeShellScript "moss-transcribe-run" ''
          set -e
          source /var/lib/moss-transcribe/venv/bin/activate
          exec vllm serve ${cfg.modelPath} \
            --served-model-name ${cfg.modelName} \
            --host ${cfg.host} \
            --port ${toString cfg.port} \
            --trust-remote-code \
            --gpu-memory-utilization ${toString cfg.gpuMemoryUtilization} \
            --max-model-len ${toString cfg.maxModelLen} \
            --max-num-batched-tokens ${toString cfg.maxBatchedTokens} \
            ${concatStringsSep " " cfg.extraArgs}
        '';
        Restart = "on-failure";
        RestartSec = 10;
      };

      path = [ pkgs.stdenv.cc ];
    };

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];

    systemd.services.tailscale-serve-moss-transcribe = mkIf cfg.tailscaleServe {
      description = "Expose MOSS-Transcribe-Diarize via Tailscale Serve";
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
  };
}
