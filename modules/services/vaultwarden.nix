# vaultwarden: Bitwarden-compatible server (native NixOS module) with the
# /admin panel enabled via ADMIN_TOKEN from a secret env file. Binds
# loopback only; published tailnet-only via Tailscale Serve (TLS + tailnet
# identity), which the web vault requires as a secure context.
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.vaultwarden;
in
{
  options.vaultwarden = {
    enable = mkEnableOption "Vaultwarden password manager server";

    domain = mkOption {
      type = types.str;
      description = "Public domain (Tailscale Serve hostname) the instance is reachable at.";
      example = "nixos.tail69fe1.ts.net";
    };

    port = mkOption {
      type = types.port;
      default = 8222;
      description = "Loopback port for the Rocket listener; also the public Tailscale Serve HTTPS port.";
    };

    adminTokenFile = mkOption {
      type = types.path;
      description = ''
        Env file (mode 0600) containing the admin panel token:
          ADMIN_TOKEN=<argon2 PHC string>
        Generate with:
          nix shell nixpkgs#vaultwarden -c vaultwarden hash
      '';
    };

    backupDir = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Enable nightly sqlite backups into this directory.";
      example = "/var/backup/vaultwarden";
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
    services.vaultwarden = {
      inherit (cfg) backupDir;
      enable = true;
      dbBackend = "sqlite";
      environmentFile = cfg.adminTokenFile;
      config = {
        DOMAIN = "https://${cfg.domain}" + optionalString (cfg.port != 443) ":${toString cfg.port}";
        ROCKET_ADDRESS = "127.0.0.1";
        ROCKET_PORT = cfg.port;
      };
    };

    # Tailscale Serve: HTTPS proxy for Vaultwarden. Rocket binds 127.0.0.1 so
    # this is the only listener (tailnet-only).
    systemd.services.tailscale-serve-vaultwarden = mkIf cfg.serve {
      description = "Tailscale Serve for Vaultwarden";
      after = [ "tailscaled.service" "vaultwarden.service" ];
      wants = [ "tailscaled.service" "vaultwarden.service" ];
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
