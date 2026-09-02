# nixpkgs daily reporter.
#
# Fetches the last 24h of commits to nixpkgs master, parses package updates /
# new / removals / security fixes, asks local Ollama for commentary on notable
# packages, and writes a styled HTML report + index to dataDir. Runs as user
# `jay` via a persistent daily timer. See nixnews-reporter.py for the flow.

{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.nixnews;
  reporter = ./nixnews-reporter.py;
in
{
  options.nixnews = {
    enable = mkEnableOption "nixpkgs-unstable daily HTML reporter";

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/nixnews";
      description = "Directory for daily HTML reports and index.html.";
    };

    ollamaUrl = mkOption {
      type = types.str;
      default = "http://127.0.0.1:11434";
      description = "Ollama API base URL for notable-package commentary.";
    };

    branch = mkOption {
      type = types.str;
      default = "master";
      description = "nixpkgs git ref to report on (master; nixos-unstable only advances in bursts).";
    };

    ollamaModel = mkOption {
      type = types.str;
      default = "hf.co/deepreinforce-ai/Ornith-1.0-9B-GGUF:Q4_K_M";
      description = "Ollama model tag used for commentary.";
    };

    startAt = mkOption {
      type = types.str;
      default = "*-*-* 03:00:00";
      description = "systemd OnCalendar expression for the daily run.";
    };

    serve = mkOption {
      type = types.bool;
      default = false;
      description = "Serve the reports over HTTPS via nginx + Tailscale Serve.";
    };

    domain = mkOption {
      type = types.str;
      default = "nixos-ripper.tail69fe1.ts.net";
      description = "Tailscale host name the reports are served under.";
    };

    nginxPort = mkOption {
      type = types.port;
      default = 8444;
      description = "Loopback port nginx listens on; also the Tailscale Serve HTTPS port.";
    };
  };

  config = mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 jay users -"
    ];

    systemd.services.nixnews-reporter = {
      description = "nixpkgs-unstable daily reporter";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = "jay";
        Group = "users";
        ExecStart = "${pkgs.python3}/bin/python3 ${reporter}";
      };
      environment = {
        NIXNEWS_DIR = cfg.dataDir;
        NIXNEWS_BRANCH = cfg.branch;
        OLLAMA_URL = cfg.ollamaUrl;
        OLLAMA_MODEL = cfg.ollamaModel;
      };
    };

    systemd.timers.nixnews-reporter = {
      description = "Timer for nixpkgs-unstable daily reporter";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.startAt;
        Persistent = true;
        Unit = "nixnews-reporter.service";
      };
    };

    # Optional HTTPS serving: nginx static vhost on loopback, fronted by
    # Tailscale Serve so reports are reachable across the tailnet. nginx needs
    # read access to dataDir (owned by jay:users per the tmpfiles rule above).
    services.nginx = mkIf cfg.serve {
      enable = true;
      virtualHosts."${cfg.domain}" = {
        listen = [{ addr = "127.0.0.1"; port = cfg.nginxPort; }];
        root = cfg.dataDir;
        locations."/" = {
          index = "index.html";
          tryFiles = "$uri $uri/ =404";
        };
      };
    };

    users.users.nginx.extraGroups = mkIf cfg.serve [ "users" ];

    systemd.services.tailscale-serve-nixnews = mkIf cfg.serve {
      description = "Tailscale Serve for nixnews reports";
      after = [ "tailscaled.service" "nginx.service" ];
      wants = [ "tailscaled.service" "nginx.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.tailscale ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStartPre = "${pkgs.bash}/bin/bash -c 'for i in $(seq 1 30); do tailscale status >/dev/null 2>&1 && exit 0; sleep 1; done; exit 1'";
        ExecStart = "${pkgs.bash}/bin/bash -c 'for i in $(seq 1 5); do ${pkgs.tailscale}/bin/tailscale serve --bg --https=${toString cfg.nginxPort} http://127.0.0.1:${toString cfg.nginxPort} && exit 0; sleep 2; done; exit 1'";
        ExecStop = "${pkgs.tailscale}/bin/tailscale serve --https=${toString cfg.nginxPort} off";
      };
    };
  };
}
