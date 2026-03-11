
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.comfyui;
in
{
  options.comfyui.enable = mkEnableOption "ComfyUI";

  options.comfyui.port = mkOption {
    type = types.port;
    default = 8188;
    description = "Port for the ComfyUI web interface.";
  };

  options.comfyui.dataDir = mkOption {
    type = types.str;
    default = "/var/lib/comfyui";
    description = "Directory for ComfyUI persistent data (models, outputs, custom nodes).";
  };

  options.comfyui.image = mkOption {
    type = types.str;
    default = "yanwk/comfyui-boot:rocm";
    description = "Docker image for ComfyUI.";
  };

  config = mkIf cfg.enable {
    # Create persistent directories
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root -"
      "d ${cfg.dataDir}/models 0755 root root -"
      "d ${cfg.dataDir}/output 0755 root root -"
      "d ${cfg.dataDir}/input 0755 root root -"
      "d ${cfg.dataDir}/custom_nodes 0755 root root -"
    ];

    virtualisation.oci-containers.containers.comfyui = {
      image = cfg.image;
      ports = [ "${toString cfg.port}:8188" ];
      volumes = [
        "${cfg.dataDir}/models:/root/ComfyUI/models"
        "${cfg.dataDir}/output:/root/ComfyUI/output"
        "${cfg.dataDir}/input:/root/ComfyUI/input"
        "${cfg.dataDir}/custom_nodes:/root/ComfyUI/custom_nodes"
      ];
      environment = {
        HSA_OVERRIDE_GFX_VERSION = "11.5.0";
      };
      extraOptions = [
        "--device=/dev/kfd"
        "--device=/dev/dri"
        "--group-add=video"
        "--group-add=render"
        "--security-opt=seccomp=unconfined"
      ];
    };

    # Tailscale Serve: HTTPS proxy for ComfyUI
    systemd.services.tailscale-serve-comfyui = {
      description = "Tailscale Serve for ComfyUI";
      after = [ "tailscaled.service" ];
      wants = [ "tailscaled.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.tailscale}/bin/tailscale serve --bg --https=${toString cfg.port} http://127.0.0.1:${toString cfg.port}";
        ExecStop = "${pkgs.tailscale}/bin/tailscale serve --https=${toString cfg.port} off";
      };
    };
  };
}
