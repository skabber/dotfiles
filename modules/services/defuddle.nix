# Defuddle — URL-to-Markdown conversion HTTP service
# Wraps the defuddle Node.js library as a simple HTTP server.

{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.defuddle;
  serverScript = ./defuddle-server.js;
in
{
  options.defuddle = {
    enable = mkEnableOption "Defuddle URL-to-Markdown service";

    port = mkOption {
      type = types.port;
      default = 3002;
      description = "Port for the Defuddle HTTP server.";
    };

    sourceDir = mkOption {
      type = types.str;
      default = "/home/jay/Projects/defuddle";
      description = "Path to the defuddle source directory.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to open the firewall port.";
    };
  };

  config = mkIf cfg.enable {
    # One-shot unit to install deps and build
    systemd.services.defuddle-setup = {
      description = "Defuddle npm install and build";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        WorkingDirectory = cfg.sourceDir;
        ExecStart = pkgs.writeShellScript "defuddle-setup" ''
          set -e
          cd ${cfg.sourceDir}
          ${pkgs.nodejs}/bin/npm install --prefer-offline
          ${pkgs.nodejs}/bin/npm run build
        '';
      };
      path = [ pkgs.nodejs pkgs.git pkgs.bash pkgs.coreutils ];
    };

    systemd.services.defuddle = {
      description = "Defuddle URL-to-Markdown Service";
      after = [ "network.target" "defuddle-setup.service" ];
      requires = [ "defuddle-setup.service" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        DEFUDDLE_DIR = cfg.sourceDir;
        DEFUDDLE_PORT = toString cfg.port;
        NODE_ENV = "production";
      };

      serviceConfig = {
        WorkingDirectory = cfg.sourceDir;
        ExecStart = "${pkgs.nodejs}/bin/node ${serverScript}";
        Restart = "on-failure";
        RestartSec = 5;
      };

      path = [ pkgs.nodejs ];
    };

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];
  };
}
