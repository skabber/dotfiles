# vikunja: to-do / task management (native NixOS module) backed by sqlite.
# Binds loopback only; published tailnet-only via Tailscale Serve (TLS +
# tailnet identity). State lives in /var/lib/vikunja (DynamicUser +
# StateDirectory from the upstream module).
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.vikunja;
in
{
  options.vikunja = {
    enable = mkEnableOption "Vikunja task management service";

    domain = mkOption {
      type = types.str;
      description = "Public domain (Tailscale Serve hostname) the instance is reachable at.";
      example = "nixos.tail69fe1.ts.net";
    };

    port = mkOption {
      type = types.port;
      default = 3456;
      description = "Loopback port for the Vikunja listener; also the public Tailscale Serve HTTPS port.";
    };

    environmentFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Optional env file (mode 0600) with a fixed JWT secret so sessions
        survive restarts (a random one is generated per start otherwise):
          VIKUNJA_SERVICE_JWTSECRET=<random string>
        Generate with: openssl rand -base64 32
      '';
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
    };

    serve = mkOption {
      type = types.bool;
      default = true;
      description = "Expose at https://<host>.ts.net:<port> via Tailscale Serve.";
    };
  };

  config = mkIf cfg.enable {
    services.vikunja = {
      enable = true;
      environmentFiles = optional (cfg.environmentFile != null) cfg.environmentFile;
      frontendScheme = "https";
      frontendHostname = "${cfg.domain}" + optionalString (cfg.port != 443) ":${toString cfg.port}";
      address = "127.0.0.1";
      port = cfg.port;
      database.type = "sqlite";
    };

    # Tailscale Serve: HTTPS proxy for Vikunja. The API binds 127.0.0.1 so
    # this is the only listener (tailnet-only).
    systemd.services.tailscale-serve-vikunja = mkIf cfg.serve {
      description = "Tailscale Serve for Vikunja";
      after = [ "tailscaled.service" "vikunja.service" ];
      wants = [ "tailscaled.service" "vikunja.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.tailscale ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStartPre = "${pkgs.bash}/bin/bash -c 'for i in $(seq 1 30); do tailscale status >/dev/null 2>&1 && exit 0; sleep 1; done; exit 1'";
        ExecStart = "${pkgs.bash}/bin/bash -c 'for i in $(seq 1 5); do ${pkgs.tailscale}/bin/tailscale serve --bg --https=${toString cfg.port} http://127.0.0.1:${toString cfg.port} && exit 0; sleep 2; done; exit 1'";
        ExecStop = "${pkgs.tailscale}/bin/tailscale serve --https=${toString cfg.port} off";
      };
    };

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];
  };
}
