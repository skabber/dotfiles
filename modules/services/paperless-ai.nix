
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.paperless-ai;
in
{
  options.paperless-ai = {
    enable = mkEnableOption "Paperless-AI (auto-tagging, classification, RAG)";

    port = mkOption {
      type = types.port;
      default = 3003;
      description = "Host port mapped to the container's :3000 web UI.";
    };

    bindAddress = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = ''
        Host address the container's port is published on. Defaults to
        127.0.0.1 so Tailscale Serve owns the public listener and Docker
        doesn't race tailscaled for 0.0.0.0.
      '';
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to open the firewall port.";
    };

    image = mkOption {
      type = types.str;
      default = "clusterzx/paperless-ai:latest";
      description = "Docker image (RAG bundled in production image).";
    };

    paperlessApiUrl = mkOption {
      type = types.str;
      default = "http://host.docker.internal:28981/api";
      description = "URL of the paperless-ngx API as seen from inside the container.";
    };

    paperlessUsername = mkOption {
      type = types.str;
      default = "jay";
      description = "Paperless-ngx username that owns the API token.";
    };

    ollamaUrl = mkOption {
      type = types.str;
      default = "http://nixos-ripper.tail69fe1.ts.net:11434";
      description = "Ollama base URL.";
    };

    ollamaModel = mkOption {
      type = types.str;
      default = "llama3.2";
      description = "Ollama model used for classification/tagging/RAG.";
    };

    enableRag = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to enable the bundled RAG service (semantic search).";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/paperless-ai";
      description = "Host directory mounted at /app/data inside the container.";
    };

    environmentFile = mkOption {
      type = types.path;
      description = ''
        Path to a file containing PAPERLESS_API_TOKEN (and optionally other
        secrets). Format: KEY=value, one per line. Example contents:

          PAPERLESS_API_TOKEN=abc123…
      '';
      example = "/home/jay/.secrets/paperless-ai.env";
    };
  };

  config = mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 root root -"
    ];

    virtualisation.oci-containers.containers.paperless-ai = {
      image = cfg.image;
      autoStart = true;
      ports = [ "${cfg.bindAddress}:${toString cfg.port}:3000" ];
      volumes = [ "${cfg.dataDir}:/app/data" ];
      environment = {
        PUID = "1000";
        PGID = "1000";
        PAPERLESS_AI_INITIAL_SETUP = "yes";
        PAPERLESS_API_URL = cfg.paperlessApiUrl;
        PAPERLESS_USERNAME = cfg.paperlessUsername;
        AI_PROVIDER = "ollama";
        OLLAMA_API_URL = cfg.ollamaUrl;
        OLLAMA_MODEL = cfg.ollamaModel;
        RAG_SERVICE_URL = "http://localhost:8000";
        RAG_SERVICE_ENABLED = if cfg.enableRag then "true" else "false";
      };
      environmentFiles = [ cfg.environmentFile ];
      extraOptions = [ "--add-host=host.docker.internal:host-gateway" ];
    };

    # Wait for paperless-ngx web service before starting
    systemd.services.docker-paperless-ai = {
      after = [ "paperless-web.service" "docker.service" ];
      wants = [ "paperless-web.service" ];
    };

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];
  };
}
