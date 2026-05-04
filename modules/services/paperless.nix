
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.paperless;
in
{
  options.paperless = {
    enable = mkEnableOption "Paperless-ngx document management";

    port = mkOption {
      type = types.port;
      default = 28981;
      description = "Port for the Paperless-ngx web UI.";
    };

    address = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = "Listen address.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to open the firewall port.";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/paperless";
      description = "Directory for Paperless data and database (when SQLite).";
    };

    mediaDir = mkOption {
      type = types.str;
      default = "${cfg.dataDir}/media";
      description = "Directory for archived/original document files.";
    };

    consumptionDir = mkOption {
      type = types.str;
      default = "${cfg.dataDir}/consume";
      description = "Watched directory; files dropped here are auto-ingested.";
    };

    adminUser = mkOption {
      type = types.str;
      default = "jay";
      description = "Initial superuser username.";
    };

    passwordFile = mkOption {
      type = types.path;
      description = "Path to a file containing the admin password (single line, no trailing newline).";
      example = "/home/jay/.secrets/paperless-admin-password";
    };

    domain = mkOption {
      type = types.str;
      default = "nixos.tail69fe1.ts.net";
      description = "Hostname under which Paperless is reached (for ALLOWED_HOSTS / CSRF).";
    };

    ocrLanguage = mkOption {
      type = types.str;
      default = "eng";
      description = "Tesseract language code(s) for OCR (e.g. 'eng', 'eng+deu').";
    };
  };

  config = mkIf cfg.enable {
    nixpkgs.overlays = [
      (final: prev: {
        python3 = prev.python3.override {
          self = final.python3;
          packageOverrides = pyfinal: pyprev: {
            ocrmypdf = pyprev.ocrmypdf.overridePythonAttrs (_: {
              doCheck = false;
              doInstallCheck = false;
            });
          };
        };
      })
    ];

    services.paperless = {
      enable = true;
      inherit (cfg) address port dataDir mediaDir consumptionDir passwordFile;
      configureTika = false;
      settings = {
        PAPERLESS_URL = "https://${cfg.domain}:${toString cfg.port}";
        PAPERLESS_ALLOWED_HOSTS = "${cfg.domain},localhost,127.0.0.1";
        PAPERLESS_CORS_ALLOWED_HOSTS = "https://${cfg.domain}:${toString cfg.port}";
        PAPERLESS_TRUSTED_PROXIES = "127.0.0.1";
        PAPERLESS_OCR_LANGUAGE = cfg.ocrLanguage;
        PAPERLESS_TIME_ZONE = config.time.timeZone;
        PAPERLESS_ADMIN_USER = cfg.adminUser;
      };
    };

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];
  };
}
