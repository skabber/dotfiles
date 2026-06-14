# show-friends PR preview deploys.
#
# Builds and serves show-friends PRs on this host so a developer can test them
# over Tailscale (HTTPS) before merging. A long-running manager daemon (root,
# loopback-only HTTP) receives /start and /stop calls from Gitea Actions; for
# each PR it writes a per-PR env file and starts a templated systemd unit that
# (as user `jay`) checks out the PR, builds via `nix develop`, spins up a local
# libSQL server, runs the worker + pages dev servers, and registers a
# Tailscale Serve mapping. See show-friends-preview-manager.py for the flow.

{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.show-friends-preview;

  manager = ./show-friends-preview-manager.py;
  prepare = ./sf-preview-prepare.sh;
  serve   = ./sf-preview-serve.sh;
  stop    = ./sf-preview-stop.sh;

  # Wrapper that sources the per-PR env (to learn SRC_DIR) then enters the
  # per-PR flake's nix devshell to run the serve script.
  startWrapper = pkgs.writeShellScript "sf-preview-start" ''
    set -euo pipefail
    PR="$1"
    set -a; . "/srv/show-friends/previews/$PR/preview.env"; set +a
    exec nix develop "$SRC_DIR" -c bash ${serve} "$PR"
  '';

  # Tools the per-PR unit needs on PATH (the serve script also relies on the
  # non-pure nix develop inheriting these).
  unitPath = with pkgs; [
    nix git curl jq tailscale coreutils gnugrep findutils openssh bash
  ];
in
{
  options.show-friends-preview = {
    enable = mkEnableOption "show-friends PR preview deploys";

    port = mkOption {
      type = types.port;
      default = 9100;
      description = "Loopback port for the preview manager HTTP API.";
    };

    domain = mkOption {
      type = types.str;
      default = "nixos.tail69fe1.ts.net";
      description = "Tailscale host name previews are served under.";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/srv/show-friends";
      description = "Root directory for checkouts, per-PR DBs and env files.";
    };

    tokenFile = mkOption {
      type = types.path;
      description = ''
        Environment file (mode 0600, root-owned) with:
          PREVIEW_TOKEN=<shared secret for /start /stop>
          COMMENT_TOKEN=<Gitea API token allowed to comment on PRs>
          GITEA_REPO=skabber/show-friends
        Plus optional overrides: GITEA_URL, DOMAIN, MAX_PREVIEWS, HEALTH_TIMEOUT.
      '';
    };

    maxPreviews = mkOption {
      type = types.ints.positive;
      default = 5;
      description = "Maximum concurrent previews.";
    };
  };

  config = mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 jay root -"
      "d ${cfg.dataDir}/previews 0755 jay root -"
    ];

    # Root-owned manager: it needs to start/stop the per-PR system units and
    # chown checkout dirs to `jay`. Bound to loopback only; bearer-token auth.
    systemd.services.show-friends-preview-manager = {
      description = "show-friends PR preview manager";
      after = [ "network.target" "tailscaled.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.python3}/bin/python3 ${manager}";
        EnvironmentFile = cfg.tokenFile;
        Environment = [
          "PORT=${toString cfg.port}"
          "DOMAIN=${cfg.domain}"
          "MAX_PREVIEWS=${toString cfg.maxPreviews}"
          "DATA_ROOT=${cfg.dataDir}"
        ];
        Restart = "on-failure";
        RestartSec = 5;
      };
    };

    # Per-PR template. %i is the PR number. Builds + serves as user `jay` so the
    # nix/cargo caches are reused; the manager (root) starts it.
    systemd.services."show-friends-preview@" = {
      description = "show-friends preview for PR %i";
      after = [ "network.target" "tailscaled.service" ];
      serviceConfig = {
        Type = "simple";
        User = "jay";
        Group = "users";
        WorkingDirectory = "${cfg.dataDir}/previews/%i";
        ExecStartPre = "${pkgs.bash}/bin/bash ${prepare} %i";
        ExecStart = "${startWrapper} %i";
        ExecStopPost = "${pkgs.bash}/bin/bash ${stop} %i";
        # Give builds generous room; wrangler dev / sqld are long-lived.
        TimeoutStartSec = "20m";
        TimeoutStopSec = "30";
        KillMode = "control-group";
        Restart = "no";
      };
      environment = {
        NIX_CONFIG = "accept-flake-config = true";
        WRANGLER_SEND_METRICS = "false";
        CLOUDFLARE_TELEMETRY_DISABLED = "1";
        GIT_TERMINAL_PROMPT = "0";
      };
      path = unitPath;
    };
  };
}
