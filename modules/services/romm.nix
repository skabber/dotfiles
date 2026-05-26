
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.romm;
in
{
  options.romm = {
    enable = mkEnableOption "Romm game library manager";

    port = mkOption {
      type = types.port;
      default = 8070;
    };

    bindAddress = mkOption {
      type = types.str;
      default = "127.0.0.1";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
    };

    libraryPath = mkOption {
      type = types.str;
      description = "Host path to ROM library directory.";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/romm";
    };

    image = mkOption {
      type = types.str;
      default = "rommapp/romm:latest";
    };

    dbName = mkOption {
      type = types.str;
      default = "romm";
    };

    dbUser = mkOption {
      type = types.str;
      default = "romm";
    };

    environmentFile = mkOption {
      type = types.path;
      description = "Env file with DB_PASSWD, ROMM_AUTH_SECRET_KEY, and optional metadata API keys.";
    };
  };

  config = mkIf cfg.enable {
    services.mysql = {
      enable = true;
      package = pkgs.mariadb;
      ensureDatabases = [ cfg.dbName ];
      ensureUsers = [{
        name = cfg.dbUser;
      }];
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 root root -"
      "d ${cfg.dataDir}/assets 0750 root root -"
      "d ${cfg.dataDir}/config 0750 root root -"
      "d ${cfg.dataDir}/resources 0750 root root -"
      "d ${cfg.dataDir}/redis 0750 root root -"
    ];

    virtualisation.oci-containers.containers.romm = {
      image = cfg.image;
      autoStart = true;
      ports = [ "${cfg.bindAddress}:${toString cfg.port}:8080" ];
      volumes = [
        "${cfg.libraryPath}:/romm/library"
        "${cfg.dataDir}/assets:/romm/assets"
        "${cfg.dataDir}/config:/romm/config"
        "${cfg.dataDir}/resources:/romm/resources"
        "${cfg.dataDir}/redis:/redis-data"
      ];
      environment = {
        DB_HOST = "host.docker.internal";
        DB_NAME = cfg.dbName;
        DB_USER = cfg.dbUser;
      };
      environmentFiles = [ cfg.environmentFile ];
      extraOptions = [ "--add-host=host.docker.internal:host-gateway" ];
    };

    systemd.services.docker-romm = {
      after = [ "mysql.service" "docker.service" ];
      wants = [ "mysql.service" ];
      unitConfig.RequiresMountsFor = [ cfg.libraryPath ];
    };

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];
  };
}
