# Agentgateway: AI agent connectivity proxy (LLM/MCP/A2A) with built-in UI
# served on the data-plane port. Config bootstraps to
# <dataDir>/.config/agentgateway/config.yaml and is hot-reloaded; the UI
# wizard rewrites it as you add models and MCP servers. Hybrid storage
# keeps config.yaml authoritative while keys and budgets live in sqlite,
# enabling dynamic virtual keys and USD/token budget enforcement.
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.agentgateway;

  bootstrap = pkgs.writeShellScript "agentgateway-bootstrap" ''
    set -euo pipefail
    config="''${HOME}/.config/agentgateway/config.yaml"
    if [ ! -f "$config" ]; then
      mkdir -p "$(dirname "$config")"
      printf '%s\n' \
        '# yaml-language-server: $schema=https://agentgateway.dev/schema/config' \
        'config:' \
        '  database:' \
        "    url: sqlite://${cfg.dataDir}/agentgateway.db" \
        '  storage:' \
        '    mode: hybrid' \
        'gateways:' \
        '  default:' \
        "    port: ${toString cfg.port}" \
        'ui:' \
        '  gateways: default' > "$config"
      chmod 600 "$config"
    fi
  '';
in
{
  options.agentgateway = {
    enable = mkEnableOption "Agentgateway agent connectivity proxy";

    package = mkOption {
      type = types.package;
      default = pkgs.callPackage ../../pkgs/agentgateway.nix { };
      description = "Agentgateway package (gateway binary + agctl CLI).";
    };

    port = mkOption {
      type = types.port;
      default = 4000;
      description = "Data-plane listener and UI port.";
    };

    user = mkOption {
      type = types.str;
      default = "agentgateway";
      description = "User to run the service as.";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/agentgateway";
      description = "State directory: config.yaml, sqlite request-log DB. Must be under /var/lib.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open the data-plane/UI port on all interfaces.";
    };
  };

  config = mkIf cfg.enable {
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.user;
      home = cfg.dataDir;
      description = "Agentgateway service user";
    };
    users.groups.${cfg.user} = { };

    systemd.services.agentgateway = {
      description = "Agentgateway agent connectivity proxy";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      environment.HOME = cfg.dataDir;

      serviceConfig = {
        Type = "exec";
        User = cfg.user;
        Group = cfg.user;
        StateDirectory = removePrefix "/var/lib/" cfg.dataDir;
        WorkingDirectory = cfg.dataDir;
        ExecStartPre = [ "${bootstrap}" ];
        ExecStart = "${cfg.package}/bin/agentgateway";
        Restart = "on-failure";
        RestartSec = "5s";
        # Graceful drain waits up to 5s for in-flight streams
        TimeoutStopSec = "30s";
      };
    };

    networking.firewall = mkIf cfg.openFirewall {
      allowedTCPPorts = [ cfg.port ];
    };

    environment.systemPackages = [ cfg.package ];
  };
}
