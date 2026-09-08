# pi-chat: web UI that drives the pi coding agent against the dotfiles repo.
# Chat streams live pi events (thinking, tool calls, text), alongside a file
# browser and a git diff viewer so agent edits are inspectable. The server
# runs unprivileged as the repo owner (pi needs their ~/.pi auth and edits
# their files); loopback-only HTTP published tailnet-only via Tailscale Serve
# (TLS + tailnet identity), with an optional bearer token for defense in
# depth. Chat runs are one pi process per session id, capped overall.
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.pi-chat;
in
{
  options.pi-chat = {
    enable = mkEnableOption "pi-chat: web UI for the pi agent over the dotfiles repo";

    port = mkOption {
      type = types.port;
      default = 7981;
      description = "Loopback port for the panel.";
    };

    repo = mkOption {
      type = types.path;
      default = /home/jay/dotfiles;
      description = "Repository the agent works in and the browser shows.";
    };

    user = mkOption {
      type = types.str;
      default = "jay";
      description = "Unprivileged user that owns the repo and pi config.";
    };

    piBin = mkOption {
      type = types.str;
      default = "/home/jay/.local/bin/pi";
      description = "Path to the pi CLI (imperatively installed).";
    };

    tokenFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Optional environment file (mode 0600) with
          PI_CHAT_TOKEN=<shared secret>
        When set, every request requires an Authorization: Bearer header.
      '';
    };

    serve = mkOption {
      type = types.bool;
      default = true;
      description = "Expose at https://<host>.ts.net:<port> via Tailscale Serve.";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.pi-chat = {
      description = "pi-chat web UI (pi agent + file browser)";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      environment = {
        PI_CHAT_PORT = toString cfg.port;
        PI_CHAT_HOST = "127.0.0.1";
        PI_CHAT_HTML = toString ./pi-chat.html;
        PI_CHAT_REPO = toString cfg.repo;
        PI_CHAT_PI = cfg.piBin;
        HOME = "/home/${cfg.user}";
      };
      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = "users";
        WorkingDirectory = toString cfg.repo;
        ExecStart = "${pkgs.python3}/bin/python3 ${./pi-chat.py}";
        NoNewPrivileges = true;
        PrivateTmp = true;
        Restart = "on-failure";
        RestartSec = 5;
      } // optionalAttrs (cfg.tokenFile != null) {
        EnvironmentFile = cfg.tokenFile;
      };
      # systemd-cat for request logging; nodejs (pi's #!/usr/bin/env node
      # shebang), git (the browser/diff backend), and bash for pi's tools.
      path = [ pkgs.systemd pkgs.nodejs pkgs.git pkgs.bash ];
    };

    systemd.services.tailscale-serve-pi-chat = mkIf cfg.serve {
      description = "Tailscale Serve for pi-chat";
      after = [ "tailscaled.service" ];
      wants = [ "tailscaled.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.tailscale ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStartPre = "${pkgs.bash}/bin/bash -c 'for i in $(seq 1 30); do tailscale status >/dev/null 2>&1 && exit 0; sleep 1; done; exit 1'";
        # Retry: concurrent serve units racing one config write get an etag
        # mismatch ("Another client is changing the serve config").
        ExecStart = "${pkgs.bash}/bin/bash -c 'for i in $(seq 1 5); do ${pkgs.tailscale}/bin/tailscale serve --bg --https=${toString cfg.port} http://127.0.0.1:${toString cfg.port} && exit 0; sleep 2; done; exit 1'";
        ExecStop = "${pkgs.tailscale}/bin/tailscale serve --https=${toString cfg.port} off";
      };
    };
  };
}
