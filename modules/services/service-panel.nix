# service-panel: minimal web UI to start/stop an allowlisted set of NixOS
# systemd units (the GPU-heavy services etc. that are no longer auto-started).
# Root-owned loopback HTTP; published tailnet-only via Tailscale Serve (TLS +
# tailnet identity), with an optional bearer token for defense in depth.
# Units are an exact-match allowlist — the panel can never touch anything
# outside config.service-panel.units.
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.service-panel;
in
{
  options.service-panel = {
    enable = mkEnableOption "service-panel: web UI to start/stop selected systemd units";

    port = mkOption {
      type = types.port;
      default = 7980;
      description = "Loopback port for the panel.";
    };

    units = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "moss-transcribe-web.service" "kokoro-fastapi.service" ];
      description = "Exact unit names the panel may show and control.";
    };

    tokenFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Optional environment file (mode 0600, root-owned) with
          PANEL_TOKEN=<shared secret>
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
    systemd.services.service-panel = {
      description = "service-panel web UI";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      environment = {
        PANEL_PORT = toString cfg.port;
        PANEL_HOST = "127.0.0.1";
        PANEL_UNITS = concatStringsSep " " cfg.units;
        PANEL_HTML = toString ./service-panel.html;
      };
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.python3}/bin/python3 ${./service-panel.py}";
        NoNewPrivileges = true;
        PrivateTmp = true;
        Restart = "on-failure";
        RestartSec = 5;
      } // optionalAttrs (cfg.tokenFile != null) {
        EnvironmentFile = cfg.tokenFile;
      };
      # systemctl/journalctl/systemd-cat resolution inside the unit
      path = [ pkgs.systemd ];
    };

    systemd.services.tailscale-serve-service-panel = mkIf cfg.serve {
      description = "Tailscale Serve for service-panel";
      after = [ "tailscaled.service" ];
      wants = [ "tailscaled.service" ];
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
  };
}
