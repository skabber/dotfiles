
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.paperless-gpt;
in
{
  options.paperless-gpt = {
    enable = mkEnableOption "paperless-gpt (LLM-powered titles, tags, OCR)";

    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Host port mapped to the container's :8080 web UI.";
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
      default = "icereed/paperless-gpt:latest";
      description = "Docker image.";
    };

    paperlessBaseUrl = mkOption {
      type = types.str;
      default = "http://host.docker.internal:28981";
      description = "Base URL of the paperless-ngx instance as seen from inside the container.";
    };

    llmProvider = mkOption {
      type = types.str;
      default = "ollama";
      description = "LLM provider for title/tag generation.";
    };

    llmModel = mkOption {
      type = types.str;
      default = "qwen3:8b";
      description = "Text LLM model used for title/tag generation.";
    };

    ollamaHost = mkOption {
      type = types.str;
      default = "http://nixos-ripper.tail69fe1.ts.net:11434";
      description = "Ollama base URL (used for both text and vision LLMs when provider is ollama).";
    };

    enableLlmOcr = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to use a vision LLM for OCR (in addition to paperless-ngx's tesseract).";
    };

    visionLlmProvider = mkOption {
      type = types.str;
      default = "ollama";
      description = "Vision LLM provider (only used when enableLlmOcr = true).";
    };

    visionLlmModel = mkOption {
      type = types.str;
      default = "minicpm-v";
      description = "Vision LLM model used for OCR.";
    };

    promptsDir = mkOption {
      type = types.str;
      default = "/var/lib/paperless-gpt/prompts";
      description = "Host directory mounted at /app/prompts for prompt customization.";
    };

    environmentFile = mkOption {
      type = types.path;
      description = ''
        Path to a file containing PAPERLESS_API_TOKEN. Format: KEY=value.
        Example contents:

          PAPERLESS_API_TOKEN=abc123…
      '';
      example = "/home/jay/.secrets/paperless-gpt.env";
    };
  };

  config = mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d ${cfg.promptsDir} 0750 root root -"
    ];

    virtualisation.oci-containers.containers.paperless-gpt = {
      image = cfg.image;
      autoStart = true;
      ports = [ "${cfg.bindAddress}:${toString cfg.port}:8080" ];
      volumes = [ "${cfg.promptsDir}:/app/prompts" ];
      environment = {
        PAPERLESS_BASE_URL = cfg.paperlessBaseUrl;
        LLM_PROVIDER = cfg.llmProvider;
        LLM_MODEL = cfg.llmModel;
        OLLAMA_HOST = cfg.ollamaHost;
      } // optionalAttrs cfg.enableLlmOcr {
        OCR_PROVIDER = "llm";
        VISION_LLM_PROVIDER = cfg.visionLlmProvider;
        VISION_LLM_MODEL = cfg.visionLlmModel;
      };
      environmentFiles = [ cfg.environmentFile ];
      extraOptions = [ "--add-host=host.docker.internal:host-gateway" ];
    };

    systemd.services.docker-paperless-gpt = {
      after = [ "paperless-web.service" "docker.service" ];
      wants = [ "paperless-web.service" ];
    };

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];
  };
}
