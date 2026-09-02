# FreeToken: edge-native MoE LLM serving engine (NVIDIA/CUDA) with
# OpenAI- and Anthropic-compatible APIs. Runs from a uv-managed venv in
# dataDir; CUDA kernels JIT-compile on first start via nvcc (CUDA 13).
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.freetoken;

  # cuda-merged: full CUDA 13 toolkit; its nvcc wrapper already binds a host
  # gcc, so no extra compiler is needed on the service PATH
  cudatoolkit = pkgs.cudaPackages_13.cudatoolkit;

  venvDir = "${cfg.dataDir}/venv";

  bootstrap = pkgs.writeShellScript "freetoken-bootstrap" ''
    set -euo pipefail
    if [ ! -x "${venvDir}/bin/ft" ] || [ "$(< ${venvDir}/.spec)" != "${cfg.package}" ]; then
      echo "freetoken: installing ${cfg.package} into ${venvDir}"
      rm -rf "${venvDir}"
      ${pkgs.uv}/bin/uv venv --python ${pkgs.python312}/bin/python3 "${venvDir}"
      ${pkgs.uv}/bin/uv pip install --python "${venvDir}/bin/python" "${cfg.package}"
      printf '%s' "${cfg.package}" > "${venvDir}/.spec"
    fi
  '';
in
{
  options.freetoken = {
    enable = mkEnableOption "FreeToken MoE inference server (CUDA)";

    autoStart = mkOption {
      type = types.bool;
      default = true;
      description = "Start the service automatically at boot.";
    };

    model = mkOption {
      type = types.str;
      example = "Qwen/Qwen3.6-35B-A3B-FP8";
      description = "Model to serve: local checkpoint path or Hugging Face repo id (downloaded into dataDir on first start).";
    };

    package = mkOption {
      type = types.str;
      default = "freetoken[accel]";
      description = "PyPI requirement specifier installed into the service venv. Changing it triggers a reinstall.";
    };

    host = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "API bind address.";
    };

    port = mkOption {
      type = types.port;
      default = 1919;
      description = "API port.";
    };

    extraArgs = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "--moe-backend hybrid" ];
      description = "Extra ft serve flags.";
    };

    extraEnvironment = mkOption {
      type = types.attrsOf types.str;
      default = { };
      example = { FREETOKEN_MAMBA_SSM_DTYPE = "bfloat16"; };
      description = "Extra environment variables for the ft serve process.";
    };

    user = mkOption {
      type = types.str;
      default = "freetoken";
      description = "User to run the service as.";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/freetoken";
      description = "State directory: venv, HF model cache, JIT caches. Must be under /var/lib.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open the API port on all interfaces.";
    };
  };

  config = mkIf cfg.enable {
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.user;
      home = cfg.dataDir;
      description = "FreeToken service user";
    };
    users.groups.${cfg.user} = { };

    systemd.services.freetoken = {
      description = "FreeToken MoE inference server";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = optionals cfg.autoStart [ "multi-user.target" ];

      # bash provides `sh`; ninja runs every command through sh -c
      # nvidia-x11 bin provides nvidia-smi for JIT arch detection (tvm_ffi)
      path = [ cudatoolkit pkgs.ninja pkgs.stdenv.cc pkgs.bash config.boot.kernelPackages.nvidia_x11.bin ];
      environment = {
        CUDA_HOME = "${cudatoolkit}";
        HF_HOME = "${cfg.dataDir}/hf";
        UV_CACHE_DIR = "/var/cache/freetoken";
        UV_PYTHON_DOWNLOADS = "never";
        UV_LINK_MODE = "copy";
        LD_LIBRARY_PATH = "${pkgs.stdenv.cc.cc.lib}/lib:/run/opengl-driver/lib";
        # triton's libcuda discovery shells out to /sbin/ldconfig, which
        # doesn't exist on NixOS; this knob short-circuits it to the driver dir
        TRITON_LIBCUDA_PATH = "/run/opengl-driver/lib";
        # triton's runtime JIT needs a host C compiler to build its driver stub;
        # flashinfer's JIT defaults CXX to bare `c++`, which no NixOS unit has
        CC = "${pkgs.stdenv.cc}/bin/cc";
        CXX = "${pkgs.stdenv.cc}/bin/c++";
        # flashinfer's JIT links against upstream CUDA's lib64 layout, which
        # NixOS's cuda-merged doesn't have (libs live in lib/, driver stub in
        # lib/stubs); gcc's LIBRARY_PATH injects the right -L dirs
        LIBRARY_PATH = "${cudatoolkit}/lib:${cudatoolkit}/lib/stubs";
        # tvm_ffi's JIT never passes -I$CUDA_HOME/include for .cu compiles
        # (upstream nvcc finds its own headers implicitly); CPATH injects it
        CPATH = "${cudatoolkit}/include";
      } // cfg.extraEnvironment;

      serviceConfig = {
        Type = "exec";
        User = cfg.user;
        Group = cfg.user;
        SupplementaryGroups = [ "video" "render" ];
        StateDirectory = removePrefix "/var/lib/" cfg.dataDir;
        CacheDirectory = "freetoken";
        WorkingDirectory = cfg.dataDir;
        ExecStartPre = [ "${bootstrap}" ];
        ExecStart = concatStringsSep " " ([
          "${venvDir}/bin/ft"
          "serve"
          "--model"
          cfg.model
          "--host"
          cfg.host
          "--port"
          (toString cfg.port)
        ] ++ cfg.extraArgs);
        Restart = "on-failure";
        RestartSec = "10s";
        # First start downloads ~10 GB of wheels, then the model checkpoint
        TimeoutStartSec = "2h";
        TimeoutStopSec = "60s";
      };
    };

    networking.firewall = mkIf cfg.openFirewall {
      allowedTCPPorts = [ cfg.port ];
    };

    # Interactive use on the host: uv for manual venv work, nvcc for JIT rebuilds
    environment.systemPackages = [ pkgs.uv cudatoolkit ];
  };
}
