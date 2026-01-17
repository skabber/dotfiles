
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.vllm;
in
{
  options.vllm = {
    enable = mkEnableOption "vLLM inference server with ROCm support";

    package = mkOption {
      type = types.package;
      default = pkgs.python3Packages.vllm;
      description = "The vLLM package to use (rocmSupport configured via overlay).";
    };

    host = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = "Host address to bind the vLLM server.";
    };

    port = mkOption {
      type = types.port;
      default = 8000;
      description = "Port for the vLLM server.";
    };

    model = mkOption {
      type = types.str;
      default = "";
      description = "Model to serve (e.g., 'meta-llama/Llama-2-7b-hf').";
    };

    extraArgs = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Extra arguments to pass to the vLLM server.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to open the firewall port for vLLM.";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    systemd.services.vllm = mkIf (cfg.model != "") {
      description = "vLLM Inference Server";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        HSA_OVERRIDE_GFX_VERSION = "10.3.0";
        HCC_AMDGPU_TARGET = "gfx1030";
        HIP_VISIBLE_DEVICES = "0";
        ROCR_VISIBLE_DEVICES = "0";
        GPU_MAX_HW_QUEUES = "1";
        VLLM_TARGET_DEVICE = "rocm";
      };

      serviceConfig = {
        Type = "simple";
        ExecStart = ''
          ${cfg.package}/bin/vllm serve ${cfg.model} \
            --host ${cfg.host} \
            --port ${toString cfg.port} \
            ${concatStringsSep " " cfg.extraArgs}
        '';
        Restart = "on-failure";
        RestartSec = 5;
        DynamicUser = true;
        StateDirectory = "vllm";
        CacheDirectory = "vllm";
      };
    };

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];
  };
}
