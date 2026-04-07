
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.ollama;
  # localNxpkgs = /home/jay/nixpkgs {
  #   config = {};
  #   overlays = {};
  # };
in
{
# nixpkgs = {
#   pkgs = localNxpkgs;
# };
  options.ollama.enable = mkEnableOption "Ollama";

  options.ollama.package = mkOption {
    type = types.package;
    default = pkgs.ollama; # Replace with the actual package name if different
    description = "The Ollama package to install.";
  };

  options.ollama.flashAttention = mkOption {
    type = types.bool;
    default = true;
    description = "Whether to enable flash attention for Ollama.";
  };

  config = mkIf cfg.enable {

    services.ollama = {
        enable = true;
        package = pkgs.ollama-rocm;
        environmentVariables = {
            HCC_AMDGPU_TARGET = "gfx1030";
            HSA_OVERRIDE_GFX_VERSION = "10.3.0";
            HIP_VISIBLE_DEVICES = "0";
            ROCR_VISIBLE_DEVICES = "0";
            GPU_MAX_HW_QUEUES = "1";
            OLLAMA_FLASH_ATTENTION = if cfg.flashAttention then "1" else "0";
        };
        rocmOverrideGfx = "10.3.0";
    };

    # services.open-webui.enable = true;

    systemd.services.ollama.environment = {
        OLLAMA_HOST =  lib.mkForce "0.0.0.0:11434";
    };
    # Open-Webui setup
  services.open-webui = {
    enable = true;
    openFirewall = true;
    host = "127.0.0.1";
    port = 8181;
    environment = {
      ANONYMIZED_TELEMETRY = "False";
      DO_NOT_TRACK = "True";
      SCARF_NO_ANALYTICS = "True";
      HOME = "/var/lib/open-webui";
    };
  };

  # Tailscale Serve: HTTPS proxy for Open WebUI
  systemd.services.tailscale-serve-open-webui = {
    description = "Tailscale Serve for Open WebUI";
    after = [ "tailscaled.service" "open-webui.service" ];
    wants = [ "tailscaled.service" "open-webui.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.tailscale ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStartPre = "${pkgs.bash}/bin/bash -c 'for i in $(seq 1 30); do tailscale status >/dev/null 2>&1 && exit 0; sleep 1; done; exit 1'";
      ExecStart = "${pkgs.tailscale}/bin/tailscale serve --bg --https=8443 http://127.0.0.1:8181";
      ExecStop = "${pkgs.tailscale}/bin/tailscale serve --https=8443 off";
    };
  };

  };
}
