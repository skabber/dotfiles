
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.gitea;
in
{
  options.gitea.enable = mkEnableOption "Gitea";

  options.gitea.domain = mkOption {
    type = types.str;
    default = "localhost";
    description = "The domain name for Gitea.";
  };

  options.gitea.httpPort = mkOption {
    type = types.port;
    default = 3000;
    description = "The HTTP port for Gitea.";
  };

  options.gitea.openFirewall = mkOption {
    type = types.bool;
    default = false;
    description = "Whether to open firewall ports for Gitea.";
  };

  options.gitea.stateDir = mkOption {
    type = types.str;
    default = "/var/lib/gitea";
    description = "The state directory for Gitea.";
  };

  options.gitea.mailer = {
    enable = mkEnableOption "Gitea mailer";

    protocol = mkOption {
      type = types.enum [ "smtp" "smtps" "smtp+starttls" "smtp+unix" "sendmail" "dummy" ];
      default = "smtp+starttls";
      description = "The mailer protocol to use.";
    };

    smtpAddr = mkOption {
      type = types.str;
      default = "";
      description = "SMTP server address.";
    };

    smtpPort = mkOption {
      type = types.port;
      default = 587;
      description = "SMTP server port.";
    };

    from = mkOption {
      type = types.str;
      default = "";
      description = "Mail from address (e.g. 'Gitea <gitea@example.com>').";
    };

    user = mkOption {
      type = types.str;
      default = "";
      description = "SMTP username (usually the sender's email address).";
    };

    passwordFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to a file containing the SMTP password.";
    };
  };

  options.gitea.runner = {
    enable = mkEnableOption "Gitea Actions runner";

    name = mkOption {
      type = types.str;
      default = config.networking.hostName;
      description = "Name of the runner.";
    };

    url = mkOption {
      type = types.str;
      default = "http://${cfg.domain}:${toString cfg.httpPort}";
      description = "URL of the Gitea instance.";
    };

    token = mkOption {
      type = types.str;
      default = "";
      description = "Runner registration token (WARNING: stored in Nix store). Use tokenFile for better security.";
    };

    tokenFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to a file containing the runner registration token.";
    };

    labels = mkOption {
      type = types.listOf types.str;
      default = [ "native:host" ];
      description = "Labels for the runner. Use 'native:host' for host execution or docker labels.";
    };

    hostPackages = mkOption {
      type = types.listOf types.package;
      default = with pkgs; [
        bash
        coreutils
        curl
        gawk
        git
        gnused
        nodejs
        wget
      ];
      description = "Packages available to actions when using host execution.";
    };
  };

  config = mkIf cfg.enable {
    services.gitea = {
      enable = true;
      stateDir = cfg.stateDir;
      mailerPasswordFile = cfg.mailer.passwordFile;
      settings = {
        server = {
          DOMAIN = cfg.domain;
          HTTP_PORT = cfg.httpPort;
          ROOT_URL = "http://${cfg.domain}:${toString cfg.httpPort}/";
        };
        mailer = mkIf cfg.mailer.enable {
          ENABLED = true;
          PROTOCOL = cfg.mailer.protocol;
          SMTP_ADDR = cfg.mailer.smtpAddr;
          SMTP_PORT = cfg.mailer.smtpPort;
          FROM = cfg.mailer.from;
          USER = cfg.mailer.user;
        };
      };
    };

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.httpPort ];

    services.gitea-actions-runner.instances.${cfg.runner.name} = mkIf cfg.runner.enable {
      enable = true;
      name = cfg.runner.name;
      url = cfg.runner.url;
      tokenFile =
        if cfg.runner.tokenFile != null then cfg.runner.tokenFile
        else pkgs.writeText "gitea-runner-token" "TOKEN=${cfg.runner.token}";
      labels = cfg.runner.labels;
      hostPackages = cfg.runner.hostPackages;
      settings = {
        runner.file = ".runner";
        cache.dir = "cache";
        container = {
          options = "-m 32g --cpus 32";  # 32GB RAM, 32 CPUs
          valid_volumes = [ ];
        };
      };
    };
  };
}
