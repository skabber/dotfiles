
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.wallabag;
  php = pkgs.php82.withExtensions ({ enabled, all }: enabled ++ [ all.pdo_pgsql all.pdo_sqlite all.intl all.gd all.imagick ]);
  dataDir = "/var/lib/wallabag";

  dbDriver = if cfg.database.type == "sqlite" then "pdo_sqlite" else "pdo_pgsql";
  dbPath = if cfg.database.type == "sqlite" then "${dataDir}/data/db/wallabag.sqlite" else "null";
  dbHost = if cfg.database.type == "postgresql" then "/run/postgresql" else "127.0.0.1";
  dbName = if cfg.database.type == "postgresql" then cfg.database.name else "wallabag";
  dbUser = if cfg.database.type == "postgresql" then "wallabag" else "wallabag";

  # Generate parameters.yml at build time
  parametersYml = pkgs.writeText "parameters.yml" ''
    parameters:
        database_driver: ${dbDriver}
        database_host: ${dbHost}
        database_port: null
        database_name: ${dbName}
        database_user: ${dbUser}
        database_password: null
        database_path: ${dbPath}
        database_table_prefix: wallabag_
        database_socket: null
        database_charset: utf8
        domain_name: 'http://${cfg.hostname}'
        server_name: 'Wallabag'
        mailer_dsn: 'smtp://127.0.0.1'
        locale: en
        secret: '${cfg.secret}'
        twofactor_sender: no-reply@wallabag.org
        fosuser_registration: false
        fosuser_confirmation: false
        fos_oauth_server_access_token_lifetime: 3600
        fos_oauth_server_refresh_token_lifetime: 1209600
        from_email: no-reply@wallabag.org
        rss_limit: 50
        rabbitmq_host: localhost
        rabbitmq_port: 5672
        rabbitmq_user: guest
        rabbitmq_password: guest
        rabbitmq_prefetch_count: 10
        redis_scheme: tcp
        redis_host: localhost
        redis_port: 6380
        redis_path: null
        redis_password: null
        sentry_dsn: null
  '';

  # Create merged app directory with custom parameters.yml and writable var symlink
  appDir = pkgs.runCommand "wallabag-app" {} ''
    mkdir -p $out/app

    # Symlink top-level files/dirs except app, var, and web
    for item in ${pkgs.wallabag}/*; do
      name=$(basename "$item")
      if [ "$name" != "app" ] && [ "$name" != "var" ] && [ "$name" != "web" ]; then
        ln -s "$item" "$out/$name"
      fi
    done

    # Copy web directory (so PHP doesn't resolve back to nix store)
    cp -r ${pkgs.wallabag}/web $out/web
    chmod -R u+w $out/web
    rm -rf $out/web/uploads
    ln -s ${dataDir}/uploads $out/web/uploads

    # Symlink app subdirs except config and AppKernel.php
    for item in ${pkgs.wallabag}/app/*; do
      name=$(basename "$item")
      if [ "$name" != "config" ] && [ "$name" != "AppKernel.php" ]; then
        ln -s "$item" "$out/app/$name"
      fi
    done

    # Copy AppKernel.php so __DIR__ resolves correctly
    cp ${pkgs.wallabag}/app/AppKernel.php $out/app/AppKernel.php

    # Copy config dir and replace parameters.yml
    cp -r ${pkgs.wallabag}/app/config $out/app/config
    chmod -R u+w $out/app/config
    rm -f $out/app/config/parameters.yml
    cp ${parametersYml} $out/app/config/parameters.yml

    # Symlink var to writable location
    ln -s ${dataDir}/var $out/var
  '';
in
{
  options.wallabag.enable = mkEnableOption "Wallabag";

  options.wallabag.hostname = mkOption {
    type = types.str;
    default = "wallabag.localhost";
    description = "Hostname for the Wallabag instance.";
  };

  options.wallabag.secret = mkOption {
    type = types.str;
    description = "Secret key for Symfony (generate with: head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9')";
    example = "ChangeMe123RandomSecretKey";
  };

  options.wallabag.enableNginx = mkOption {
    type = types.bool;
    default = true;
    description = "Whether to configure nginx as a reverse proxy.";
  };

  options.wallabag.enableSSL = mkOption {
    type = types.bool;
    default = false;
    description = "Whether to enable SSL with ACME.";
  };

  options.wallabag.database = {
    type = mkOption {
      type = types.enum [ "postgresql" "sqlite" ];
      default = "postgresql";
      description = "Database backend to use.";
    };

    name = mkOption {
      type = types.str;
      default = "wallabag";
      description = "Database name.";
    };
  };

  config = mkIf cfg.enable {
    users.users.wallabag = {
      isSystemUser = true;
      group = "wallabag";
      home = dataDir;
      createHome = true;
    };
    users.groups.wallabag = {};

    # PostgreSQL setup
    services.postgresql = mkIf (cfg.database.type == "postgresql") {
      enable = true;
      ensureDatabases = [ cfg.database.name ];
      ensureUsers = [{
        name = "wallabag";
        ensureDBOwnership = true;
      }];
    };

    # Redis for caching
    services.redis.servers.wallabag = {
      enable = true;
      user = "wallabag";
      port = 6380;
    };

    # PHP-FPM pool
    services.phpfpm.pools.wallabag = {
      user = "wallabag";
      group = "wallabag";
      phpPackage = php;
      settings = {
        "listen.owner" = config.services.nginx.user;
        "listen.group" = config.services.nginx.group;
        "pm" = "dynamic";
        "pm.max_children" = 16;
        "pm.start_servers" = 2;
        "pm.min_spare_servers" = 1;
        "pm.max_spare_servers" = 4;
      };
      phpEnv = {
        WALLABAG_DATA = "${appDir}";
      };
    };

    # Nginx virtualhost
    services.nginx = mkIf cfg.enableNginx {
      enable = true;
      virtualHosts.${cfg.hostname} = {
        forceSSL = cfg.enableSSL;
        enableACME = cfg.enableSSL;
        root = "${appDir}/web";
        locations."/" = {
          tryFiles = "$uri /app.php$is_args$args";
        };
        locations."~ ^/app\\.php(/|$)" = {
          priority = 500;
          extraConfig = ''
            fastcgi_pass unix:${config.services.phpfpm.pools.wallabag.socket};
            fastcgi_split_path_info ^(.+\.php)(/.*)$;
            include ${pkgs.nginx}/conf/fastcgi.conf;
            fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
            fastcgi_param DOCUMENT_ROOT $document_root;
            internal;
          '';
        };
        locations."~ \\.php$" = {
          priority = 600;
          extraConfig = "return 404;";
        };
      };
    };

    # Data directory setup
    systemd.tmpfiles.rules = [
      "d ${dataDir} 0750 wallabag wallabag -"
      "d ${dataDir}/data 0750 wallabag wallabag -"
      "d ${dataDir}/data/db 0750 wallabag wallabag -"
      "d ${dataDir}/var 0750 wallabag wallabag -"
      "d ${dataDir}/var/cache 0750 wallabag wallabag -"
      "d ${dataDir}/var/cache/prod 0750 wallabag wallabag -"
      "d ${dataDir}/var/logs 0750 wallabag wallabag -"
      "d ${dataDir}/var/sessions 0750 wallabag wallabag -"
      "d ${dataDir}/uploads 0750 wallabag wallabag -"
      "d ${dataDir}/uploads/import 0750 wallabag wallabag -"
    ];

    # Open firewall
    networking.firewall.allowedTCPPorts = mkIf cfg.enableNginx ([ 80 ] ++ (optional cfg.enableSSL 443));

    environment.systemPackages = [
      (pkgs.writeShellScriptBin "wallabag-console" ''
        export WALLABAG_DATA="${appDir}"
        export APP_ENV=prod
        exec ${php}/bin/php ${appDir}/bin/console --env=prod "$@"
      '')
    ];
  };
}
