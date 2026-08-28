
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

  options.ollama.igpuEnable = mkOption {
    type = types.bool;
    default = false;
    description = "Allow Ollama to use integrated GPUs (sets OLLAMA_IGPU_ENABLE=1). Required for the Framework 13's Radeon 890M.";
  };

  options.ollama.kvCacheType = mkOption {
    type = types.enum [ "f16" "q8_0" "q4_0" ];
    default = "f16";
    description = "KV cache quantization (OLLAMA_KV_CACHE_TYPE). q8_0 halves context memory; requires flash attention.";
  };

  options.ollama.keepAlive = mkOption {
    type = types.str;
    default = "5m";
    description = "How long models stay loaded after a request (OLLAMA_KEEP_ALIVE). Short values keep VRAM free for the MOSS transcription service; -1 keeps models resident forever.";
  };

  options.ollama.numParallel = mkOption {
    type = types.int;
    default = 1;
    description = "Concurrent requests Ollama processes (OLLAMA_NUM_PARALLEL). 1 serializes GPU work so one request's KV cache can't starve another.";
  };

  config = mkIf cfg.enable {

    services.ollama = {
        enable = true;
        package = pkgs.ollama-rocm;
        host = "0.0.0.0";
        port = 11434;
        environmentVariables = {
            OLLAMA_FLASH_ATTENTION = if cfg.flashAttention then "1" else "0";
            OLLAMA_KV_CACHE_TYPE = cfg.kvCacheType;
            OLLAMA_KEEP_ALIVE = cfg.keepAlive;
            OLLAMA_NUM_PARALLEL = toString cfg.numParallel;
        } // optionalAttrs cfg.igpuEnable {
            OLLAMA_IGPU_ENABLE = "1";
        };
    };

    # Order after the AMD compute node: ollama discovers GPUs once at startup and
    # would otherwise race amdgpu/kfd init at boot and silently fall back to CPU
    systemd.services.ollama = {
      after = [ "dev-kfd.device" ];
      wants = [ "dev-kfd.device" ];
    };

    # Allow Docker containers to reach Ollama
    networking.firewall.interfaces."docker0".allowedTCPPorts = [ 11434 ];
    # Allow other Tailscale peers (e.g. paperless-ai/paperless-gpt on nixos host) to reach Ollama
    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 11434 ];
    # Open-Webui (+ its Tailscale Serve proxy) temporarily disabled: it pulls in
    # ROCm PyTorch, whose miopen -> composable_kernel is gfx9-only and breaks the
    # gfx1150 pin. TODO: re-enable later (e.g. CPU-only torch for open-webui).
    /*
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
    */

  };
}
