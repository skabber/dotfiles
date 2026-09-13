# llama-mtp: unsloth llama.cpp fork serving a GGUF model with MTP speculative
# decoding via an OpenAI-compatible API. Prebuilt Vulkan binaries from the
# unslothai/llama.cpp releases run inside steam-run's FHS env.
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.llama-mtp;

  version = "b10909-mix-bea84f7";

  dist = pkgs.runCommand "llama-mtp-${version}"
    {
      # flat tarball, no top-level directory
      source = pkgs.fetchurl {
        url = "https://github.com/unslothai/llama.cpp/releases/download/${version}/app-${version}-linux-x64-vulkan.tar.gz";
        hash = "sha256-2QqS2LzxzFECymSyWHoPc33uCNi66PfJo6kf1j27SxM=";
      };
    }
    ''
      mkdir -p $out/opt/llama-mtp
      tar -xzf $source -C $out/opt/llama-mtp
    '';
in
{
  options.llama-mtp = {
    enable = mkEnableOption "unsloth llama.cpp fork with MTP speculative decoding (Vulkan)";

    model = mkOption {
      type = types.str;
      example = "/home/jay/.lmstudio/models/unsloth/Qwen3.8-Flash-Next-GGUF/Qwen3.8-Flash-Next-UD-Q3_K_XL-00001-of-00003.gguf";
      description = "Path to the main GGUF (first shard for multi-file splits).";
    };

    draftModel = mkOption {
      type = types.str;
      description = "Path to the MTP draft head GGUF.";
    };

    host = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "API bind address.";
    };

    port = mkOption {
      type = types.port;
      default = 1234;
      description = "API port.";
    };

    contextLength = mkOption {
      type = types.ints.positive;
      default = 65536;
      description = "Context length per request slot.";
    };

    gpuLayers = mkOption {
      type = types.ints.unsigned;
      default = 23;
      description = "Layers offloaded to the GPU.";
    };

    threads = mkOption {
      type = types.ints.positive;
      default = 12;
      description = "CPU threads for generation.";
    };

    specDraftMax = mkOption {
      type = types.ints.positive;
      default = 2;
      description = "Maximum draft tokens per speculative step.";
    };

    user = mkOption {
      type = types.str;
      default = "jay";
      description = "User to run the service as; model files must be readable by this user.";
    };

    autoStart = mkOption {
      type = types.bool;
      default = true;
      description = "Start the service automatically at boot.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open the API port on all interfaces.";
    };

    extraArgs = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "--no-reasoning-preserve" ];
      description = "Extra llama-server flags.";
    };

    environment = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Extra environment variables for the server process.";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.llama-mtp = {
      description = "llama.cpp (unsloth fork) MTP speculative server";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = optionals cfg.autoStart [ "multi-user.target" ];
      environment = cfg.environment;
      serviceConfig = {
        Type = "exec";
        User = cfg.user;
        SupplementaryGroups = [ "video" "render" ];
        ExecStart = concatStringsSep " " ([
          "${pkgs.steam-run}/bin/steam-run"
          "${dist}/opt/llama-mtp/llama-server"
          "-m"
          cfg.model
          "-md"
          cfg.draftModel
          "--spec-type"
          "draft-mtp"
          "--spec-draft-n-max"
          (toString cfg.specDraftMax)
          "-c"
          (toString cfg.contextLength)
          "-np"
          "1"
          "-ngl"
          (toString cfg.gpuLayers)
          "-t"
          (toString cfg.threads)
          "-fa"
          "on"
          "--jinja"
          "--host"
          cfg.host
          "--port"
          (toString cfg.port)
        ] ++ cfg.extraArgs);
        Restart = "on-failure";
        RestartSec = "10s";
        # First start pages in ~90 GB of mmap'd weights
        TimeoutStartSec = "15min";
        TimeoutStopSec = "60s";
      };
    };

    networking.firewall = mkIf cfg.openFirewall {
      allowedTCPPorts = [ cfg.port ];
    };
  };
}
