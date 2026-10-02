# OpenHands Agent Canvas (https://github.com/OpenHands/OpenHands): all-in-one
# Docker image bundling the agent server, automation backend, and frontend
# behind a single ingress port. The agent runs sandboxed inside the container
# and can only reach state under dataDir and projects under projectsDir.
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.openhands;
in
{
  options.openhands = {
    enable = mkEnableOption "OpenHands Agent Canvas";

    port = mkOption {
      type = types.port;
      default = 8000;
      description = "Ingress proxy port (unified UI + API entry point).";
    };

    bindAddress = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Bind address. Keep loopback when serve is enabled so tailscaled owns the tailnet IP:port.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
    };

    serve = mkOption {
      type = types.bool;
      default = false;
      description = "Publish via Tailscale Serve (HTTPS on the tailnet).";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/openhands";
      description = "Persistent state (settings, secrets, conversations, automation DB), mounted at /home/openhands/.openhands.";
    };

    projectsDir = mkOption {
      type = types.str;
      default = "/var/lib/openhands/projects";
      description = "Project folders the agent can read/write, mounted at /projects. Container user is openhands (UID 10001).";
    };

    image = mkOption {
      type = types.str;
      default = "ghcr.io/openhands/agent-canvas:1.24.0";
      description = "Agent Canvas image tag.";
    };

    environmentFile = mkOption {
      type = with types; nullOr path;
      default = null;
      description = "Optional env file with extra container variables (e.g. OH_* agent server settings).";
    };

    extraEnvironment = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Extra environment variables passed to the container.";
    };
  };

  config = mkIf cfg.enable {
    # Container user openhands is UID/GID 10001 in the published image
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 10001 10001 -"
      "d ${cfg.projectsDir} 0755 10001 10001 -"
    ];

    virtualisation.oci-containers.containers.openhands = {
      image = cfg.image;
      autoStart = true;
      ports = [ "${cfg.bindAddress}:${toString cfg.port}:8000" ];
      volumes = [
        "${cfg.dataDir}:/home/openhands/.openhands"
        "${cfg.projectsDir}:/projects"
      ];
      environment = {
        # Auto-inject the session API key into the served HTML. Only safe
        # because the published port is loopback; Tailscale Serve (TLS +
        # tailnet ACLs) is the sole external path. The key is also readable
        # for API use via: docker exec openhands cat /home/openhands/.openhands/api-key.txt
        AGENT_CANVAS_ALLOW_LAN_SESSION_KEY = "true";
      } // cfg.extraEnvironment;
      environmentFiles = mkIf (cfg.environmentFile != null) [ cfg.environmentFile ];
    };

    systemd.services.docker-openhands =
      let
        mounts = [ cfg.dataDir ] ++ unique [ cfg.projectsDir ];
      in
      {
        unitConfig.RequiresMountsFor = mounts;
      };

    # Tailscale Serve: HTTPS proxy for the canvas. WebSocket-friendly, so
    # live agent event streams survive the proxy.
    systemd.services.tailscale-serve-openhands = mkIf cfg.serve {
      description = "Tailscale Serve for OpenHands Agent Canvas";
      after = [ "tailscaled.service" "docker-openhands.service" ];
      wants = [ "tailscaled.service" "docker-openhands.service" ];
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
