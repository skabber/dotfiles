# MOSS-Transcribe-Diarize service
# Speaker-diarized transcription behind one consistent API: the mtd-subtitle-web
# jobs API + web UI (/api/jobs, segments, SRT/ASS export, MP4 burn-in).
#  - "vllm" (CUDA/NVIDIA): vLLM engine on loopback does the inference; the web
#    app proxies to it via the OpenAI-compatible /v1/audio/transcriptions endpoint
#  - "hf" (ROCm/AMD): the web app runs inference in-process via transformers

{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.moss-transcribe;
  isVllm = cfg.backend == "vllm";

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
      # rocmSupport override in hfPython so the GPU target set stays pinned.
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

  # Repo is tested with Python 3.12 + Transformers 5.x; pin so the venv stays
  # stable across nixpkgs python bumps (mirrors whisperx.nix).
  vllmPython = pkgs.python312.withPackages (ps: with ps; [ pip ]);

  hfPython = pkgs.python3.withPackages (ps: with ps; [
    mossPackage
    (ps.torch.override { rocmSupport = true; })
  ]);

  # vllm backend: the web app only proxies to the engine, but its imports pull
  # in torch/transformers, so it needs a CPU-torch env (the engine venv holds
  # the CUDA stack).
  webPython = pkgs.python3.withPackages (ps: with ps; [
    mossPackage
    torch
  ]);

  # When serve is enabled, bind loopback only so tailscaled owns the tailnet
  # IP:port and terminates TLS; a 0.0.0.0 bind would shadow the serve proxy.
  bindHost = if cfg.serve then "127.0.0.1" else cfg.host;
in
{
  options.moss-transcribe = {
    backend = mkOption {
      type = types.enum [ "vllm" "hf" ];
      default = "hf";
      description = ''
        Serving backend: "vllm" runs vllm serve with CUDA for an
        OpenAI-compatible transcription API; "hf" runs mtd-subtitle-web with
        transformers + ROCm for the jobs API and web UI.
      '';
    };

    enable = mkEnableOption "MOSS-Transcribe-Diarize transcription service";

    port = mkOption {
      type = types.port;
      default = 7860;
      description = "Public port for the jobs API and web UI (same surface on both backends).";
    };

    vllmPort = mkOption {
      type = types.port;
      default = 8010;
      description = "Loopback-only port for the vLLM inference engine (vllm backend); the web app proxies to it.";
    };

    host = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = ''
        Address to bind. When serve is enabled the service always binds
        loopback so Tailscale Serve owns the public listener (a 0.0.0.0 bind
        conflicts with the serve proxy on the tailscale IPs).
      '';
    };

    modelPath = mkOption {
      type = types.str;
      default = if isVllm then "/home/jay/dotfiles/models/MOSS-Transcribe-Diarize" else "/home/jay/models/MOSS-Transcribe-Diarize";
      description = "Local path to the model snapshot (must include the custom code files).";
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

    modelName = mkOption {
      type = types.str;
      default = "MOSS-Transcribe-Diarize";
      description = "Name the model is served under (vllm backend, used in API requests).";
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
      description = "Extra arguments passed to `vllm serve` (vllm backend).";
    };

    device = mkOption {
      type = types.str;
      default = "auto";
      description = "Inference device: auto (GPU if available), cuda, or cpu (hf backend).";
    };

    dtype = mkOption {
      type = types.enum [ "bf16" "fp16" "fp32" ];
      default = "bf16";
      description = "Model dtype. If bf16 misbehaves on RDNA 2, try fp16 or fp32 (hf backend).";
    };

    gfxVersion = mkOption {
      type = types.nullOr types.str;
      default = "10.3.0";
      description = "HSA_OVERRIDE_GFX_VERSION for AMD GPU compatibility. Set to null when rocm-dev pins native kernels for this host's arch.";
    };

    maxNewTokens = mkOption {
      type = types.int;
      default = 2048;
      description = "Max generated tokens per job; raise (e.g. 65536) for long audio (hf backend).";
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
    # vllm backend: one-shot unit to create venv and install the pinned
    # vLLM nightly with CUDA torch
    systemd.services.moss-transcribe-setup = mkIf isVllm {
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
          PY="${vllmPython}/bin/python"
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
      description = "MOSS-Transcribe-Diarize ${if isVllm then "vLLM engine" else "transcription service"}";
      after = [ "network.target" ] ++ optionals isVllm [ "moss-transcribe-setup.service" ];
      requires = optionals isVllm [ "moss-transcribe-setup.service" ];
      wantedBy = [ "multi-user.target" ];

      environment =
        (optionalAttrs (!isVllm && cfg.gfxVersion != null) {
          HSA_OVERRIDE_GFX_VERSION = cfg.gfxVersion;
        }) // {
          # Model is loaded from a local snapshot; never touch the hub.
          HF_HUB_OFFLINE = "1";
        } // optionalAttrs isVllm {
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
        WorkingDirectory = mkIf (!isVllm) "/var/lib/moss-transcribe";
        ExecStart =
          if isVllm then
            pkgs.writeShellScript "moss-transcribe-run" ''
              set -e
              source /var/lib/moss-transcribe/venv/bin/activate
              exec vllm serve ${cfg.modelPath} \
                --served-model-name ${cfg.modelName} \
                --host 127.0.0.1 \
                --port ${toString cfg.vllmPort} \
                --trust-remote-code \
                --gpu-memory-utilization ${toString cfg.gpuMemoryUtilization} \
                --max-model-len ${toString cfg.maxModelLen} \
                --max-num-batched-tokens ${toString cfg.maxBatchedTokens} \
                ${concatStringsSep " " cfg.extraArgs}
            ''
          else
            concatStringsSep " " [
              "${hfPython}/bin/mtd-subtitle-web"
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

      path = if isVllm then [ pkgs.stdenv.cc ] else [ pkgs.ffmpeg ];
    };

    # vllm backend: same jobs API + web UI as the hf backend, proxying
    # inference to the loopback vLLM engine.
    systemd.services.moss-transcribe-web = mkIf isVllm {
      description = "MOSS-Transcribe-Diarize jobs API (vllm backend)";
      after = [ "network.target" "moss-transcribe.service" ];
      wants = [ "moss-transcribe.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        StateDirectory = "moss-transcribe";
        WorkingDirectory = "/var/lib/moss-transcribe";
        ExecStart = concatStringsSep " " [
          "${webPython}/bin/mtd-subtitle-web"
          "--backend vllm"
          "--vllm-base-url http://127.0.0.1:${toString cfg.vllmPort}/v1"
          "--vllm-model ${cfg.modelName}"
          "--model ${cfg.modelName}"
          "--runs-dir /var/lib/moss-transcribe/runs"
          "--host ${bindHost}"
          "--port ${toString cfg.port}"
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
    systemd.services.moss-idle-unload = mkIf (!isVllm && cfg.idleUnloadMinutes > 0) {
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

    systemd.timers.moss-idle-unload = mkIf (!isVllm && cfg.idleUnloadMinutes > 0) {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*:0/10";
        Persistent = true;
      };
    };
  };
}
