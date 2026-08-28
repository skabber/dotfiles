
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
    };

    # MariaDB listens on 0.0.0.0:3306, but the default firewall drops the
    # container's traffic arriving on docker0. Open 3306 only on that
    # interface so the romm container can reach the host DB via
    # host.docker.internal (host-gateway).
    networking.firewall.interfaces.docker0.allowedTCPPorts = [ 3306 ];

    # ensureUsers can't set a password — DB_PASSWD is a secret read from the
    # env file — so provision the 'romm'@'%' user, password, and grants here,
    # idempotently, after MariaDB is up. The oneshot runs as root, so the
    # mariadb client authenticates to root over the unix socket.
    systemd.services.romm-db-init = {
      description = "Provision Romm MariaDB user and grants";
      after = [ "mysql.service" ];
      wants = [ "mysql.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        EnvironmentFile = cfg.environmentFile;
      };
      path = [ pkgs.mariadb ];
      script = ''
        mariadb <<SQL
        CREATE USER IF NOT EXISTS '${cfg.dbUser}'@'%' IDENTIFIED BY '$DB_PASSWD';
        ALTER USER '${cfg.dbUser}'@'%' IDENTIFIED BY '$DB_PASSWD';
        GRANT ALL PRIVILEGES ON ${cfg.dbName}.* TO '${cfg.dbUser}'@'%';
        FLUSH PRIVILEGES;
        SQL
      '';
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
      after = [ "mysql.service" "romm-db-init.service" "docker.service" ];
      wants = [ "mysql.service" ];
      requires = [ "romm-db-init.service" ];
      unitConfig.RequiresMountsFor = [ cfg.libraryPath ];
    };

    # Tailscale Serve: HTTPS proxy for RomM. RomM binds 127.0.0.1 so this is
    # the only public listener (tailnet-only).
    systemd.services.tailscale-serve-romm = {
      description = "Tailscale Serve for RomM";
      after = [ "tailscaled.service" "docker-romm.service" ];
      wants = [ "tailscaled.service" "docker-romm.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.tailscale ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStartPre = "${pkgs.bash}/bin/bash -c 'for i in $(seq 1 30); do tailscale status >/dev/null 2>&1 && exit 0; sleep 1; done; exit 1'";
        ExecStart = "${pkgs.tailscale}/bin/tailscale serve --bg --https=${toString cfg.port} http://127.0.0.1:${toString cfg.port}";
        ExecStop = "${pkgs.tailscale}/bin/tailscale serve --https=${toString cfg.port} off";
      };
    };

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];
  };
}
