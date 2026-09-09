# Aixle Flow — self-hosted agent orchestration platform (github.com/AixleHQ/flow)
#
# Rails 8 + Postgres + Redis + Temporal + Traefik via Docker Compose, driven by
# a systemd unit (Kokoro pattern). The app image is built from the cloned repo
# and tagged aixle/flow-web:latest; the agent runtime images
# (aixle/agent-base-core, aixle/claude-code, aixle/codex, ...) are built by a
# companion unit.
#
# Topology (single host, tailnet-only):
#   Tailscale Serve :4000 → Traefik 127.0.0.1:8081 → web :4000
#   - Traefik is structurally required: agent containers are created with
#     Traefik labels routing /t/<token>/{tty,fs,ide} to their ports, gated by
#     a ForwardAuth call to the app's /api/v1/internal/ws_auth. The web
#     service is the catch-all router so pages, API, ActionCable and terminal
#     WebSockets share one origin.
#   - The worker talks to the Docker daemon to spawn agent containers onto the
#     app_default network, where they reach web:4000 for MCP
#     (Settings.mcp.server_url → /action_mcp, served by the main app) and
#     cloud credentials.
#
# RAILS_ENV=staging is upstream's self-host mode: inherits production.rb,
# runs seeds on first boot (creates the admin user from ADMIN_PASSWORD /
# SUPER_ADMIN_EMAIL), and serves assets same-origin (request-relative
# asset_host) — no Vite dev server, no ASSET_HOST needed.
#
# The worker uses a custom entrypoint instead of upstream's bin/run-as-app:
# upstream chgrps the bind-mounted host Docker socket to the container's app
# group, which would rewrite the HOST socket's group and break docker for
# every other user/service on this machine. The custom script instead maps
# the socket's existing GID onto the app user — same privilege, no host
# mutation. (A docker-socket-proxy was considered and rejected: its ACL model
# denies DELETE, which container cleanup needs.)

{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.aixle-flow;

  # Compose override merged behind upstream's dev docker-compose.yml.
  # !override replaces list-valued keys wholesale (verified against
  # Docker Compose 5.4.0). The network name cannot be overridden here —
  # upstream pins it to app_default in their compose file — so
  # DOCKER_NETWORK=app_default below matches.
  composeFile = pkgs.writeText "aixle-flow-compose.yml" ''
    # Managed by NixOS (modules/services/aixle-flow.nix). Merge behind the
    # upstream docker-compose.yml for a single-origin production deployment.

    x-aixle: &aixle
      RAILS_ENV: staging
      RAILS_LOG_TO_STDOUT: "true"
      RAILS_MAX_THREADS: "10"
      PORT: "4000"
      DB_HOST: db
      DB_PORT: "5432"
      DB_USERNAME: postgres
      DB_NAME: aixle_staging
      REDIS_URL: redis://redis:6379/1
      DOMAIN: ${cfg.domain}:${toString cfg.port}
      PROTOCOL: https
      APP_VERSION: selfhosted
      DOCKER_NETWORK: app_default
      # /action_mcp is served by the main app (MCPController) — the dedicated
      # 4002 Puma from Procfile.dev is a dev isolation nicety, not needed.
      MCP_SERVER_URL: http://web:4000/action_mcp
      CLOUD_CREDENTIALS_URL: http://web:4000/cloud/aws/credentials
      CONTAINER_ASSET_HOST: web:4000
      TEMPORAL_HOST: temporal
      TEMPORAL_ENABLED: "true"
      TEMPORAL_UI_URL: https://${cfg.domain}:${toString cfg.temporalUiPort}
      TRAEFIK_WS_BASE: wss://${cfg.domain}:${toString cfg.port}
      TRAEFIK_HTTP_BASE: https://${cfg.domain}:${toString cfg.port}
      TRAEFIK_INTERNAL_URL: http://traefik
      TRAEFIK_CORS_ORIGINS: https://${cfg.domain}:${toString cfg.port}
      OTEL_EXPORTER_OTLP_ENDPOINT: http://otlp-ingest:4318
      OTEL_EXPORTER_OTLP_METRICS_ENDPOINT: http://otlp-ingest:4318/v1/metrics
      # Secrets: interpolated by docker compose from the systemd unit's
      # EnvironmentFile into the container environment. ''${VAR:?msg} in a
      # Nix indented string emits the literal ''${VAR:?msg} compose syntax,
      # which fails loudly when a variable is missing.
      RAILS_SECRET_KEY_BASE: ''${RAILS_SECRET_KEY_BASE:?aixle-flow env file incomplete}
      CREDENTIALS_SECRET_KEY: ''${CREDENTIALS_SECRET_KEY:?aixle-flow env file incomplete}
      CONFIG_ITEMS_SECRET_KEY: ''${CONFIG_ITEMS_SECRET_KEY:?aixle-flow env file incomplete}
      INTEGRATIONS_SECRET_KEY: ''${INTEGRATIONS_SECRET_KEY:?aixle-flow env file incomplete}
      OAUTH_SECRET_KEY: ''${OAUTH_SECRET_KEY:?aixle-flow env file incomplete}
      ADMIN_PASSWORD: ''${ADMIN_PASSWORD:?aixle-flow env file incomplete}
      SUPER_ADMIN_EMAIL: ''${SUPER_ADMIN_EMAIL:-admin@aixle.com}
      GOOGLE_CLIENT_ID: ''${GOOGLE_CLIENT_ID:-}
      GOOGLE_CLIENT_SECRET: ''${GOOGLE_CLIENT_SECRET:-}

    services:
      web:
        image: aixle/flow-web:latest
        build:
          context: .
          dockerfile: ./Dockerfile
        # bin/docker-entrypoint does the volume-chown dance and runs
        # db:prepare + catalog:featured:load on every start (idempotent).
        # No Docker socket is mounted for web, so its chgrp is a no-op.
        entrypoint: bin/docker-entrypoint
        command: ["bundle", "exec", "puma", "-C", "config/puma.rb"]
        volumes: !override
          - app_home:/home/app
          - storage:/app/storage
        # Gems live in the image (/usr/local/bundle) — no BUNDLE_PATH/GEM_HOME
        # overrides, so bundle check passes and no runtime bundle install.
        environment: !override
          <<: *aixle
        ports: !override
          - "127.0.0.1:4000:4000"
        labels: !override
          - "traefik.enable=true"
          - "traefik.http.routers.web.rule=PathPrefix(`/`)"
          - "traefik.http.routers.web.priority=1"
          - "traefik.http.services.web.loadbalancer.server.port=4000"
        restart: unless-stopped

      worker:
        image: aixle/flow-web:latest
        entrypoint: ["/bin/sh", "/usr/local/bin/flow-worker-entrypoint"]
        command: ["bin/temporal_worker"]
        volumes: !override
          - ${workerEntrypoint}:/usr/local/bin/flow-worker-entrypoint:ro
          - app_home:/home/app
          - storage:/app/storage
          - /var/run/docker.sock:/var/run/docker.sock
        environment: !override
          <<: *aixle
          RAILS_MAX_THREADS: "20"
        stop_grace_period: 120s
        restart: unless-stopped

      # Internal-only services: unpublish upstream's dev host ports.
      temporal:
        ports: !override []

      temporal-ui:
        ports: !override
          - "127.0.0.1:${toString cfg.temporalUiPort}:8080"
        restart: unless-stopped

      otlp-ingest:
        ports: !override []

      traefik:
        # Traefik is load-bearing (see module header). This deployment makes
        # the web service the catch-all router behind Tailscale Serve, so the
        # app is single-origin; the terminal-auth/terminal-cors middlewares
        # the agent-container routers reference must be (re)defined here
        # because labels are replaced wholesale.
        ports: !override
          - "127.0.0.1:${toString cfg.traefikPort}:80"
        command: !override
          - "--api.dashboard=false"
          - "--providers.docker=true"
          - "--providers.docker.exposedbydefault=false"
          - "--providers.docker.network=app_default"
          - "--entrypoints.web.address=:80"
          - "--log.level=INFO"
          - "--accesslog=true"
        labels: !override
          - "traefik.enable=true"
          - "traefik.http.middlewares.terminal-auth.forwardauth.address=http://web:4000/api/v1/internal/ws_auth"
          - "traefik.http.middlewares.terminal-auth.forwardauth.authResponseHeadersRegex=^X-"
          - "traefik.http.middlewares.terminal-cors.headers.accessControlAllowOriginList=https://${cfg.domain}:${toString cfg.port}"
          - "traefik.http.middlewares.terminal-cors.headers.accessControlAllowMethods=GET,POST,PUT,DELETE,OPTIONS"
          - "traefik.http.middlewares.terminal-cors.headers.accessControlAllowHeaders=Content-Type,Authorization,X-Requested-With,Cookie"
          - "traefik.http.middlewares.terminal-cors.headers.accessControlAllowCredentials=true"
        restart: unless-stopped

      # Dev-only infra tooling, not part of this deployment.
      remote:
        profiles: !override [disabled]
      toolbox:
        profiles: !override [disabled]

    volumes:
      storage: {}
  '';

  # Worker entrypoint: like upstream's bin/run-as-app, minus the host-mutating
  # chgrp on the Docker socket — instead the socket's existing GID is mapped
  # onto the container's app user (busybox sh, runs as root then su-exec app).
  workerEntrypoint = pkgs.writeText "flow-worker-entrypoint" ''
    #!/bin/sh
    set -e

    if [ "$(id -u)" = "0" ]; then
      mkdir -p /home/app
      chown -Rh app:app /home/app 2>/dev/null || true
      if [ -S /var/run/docker.sock ]; then
        gid=$(stat -c %g /var/run/docker.sock)
        gname=$(awk -F: -v g="$gid" '$3==g{print $1; exit}' /etc/group)
        if [ -z "$gname" ]; then
          addgroup -g "$gid" dockersock >/dev/null 2>&1 || true
          gname=dockersock
        fi
        addgroup app "$gname" 2>/dev/null || true
      fi
      exec su-exec app:app "$0" "$@"
    fi

    exec "$@"
  '';
in
{
  options.aixle-flow = {
    enable = mkEnableOption "Aixle Flow agent orchestration platform";

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/aixle-flow";
      description = "State directory holding the repo clone and compose project.";
    };

    repoUrl = mkOption {
      type = types.str;
      default = "https://github.com/AixleHQ/flow.git";
    };

    repoBranch = mkOption {
      type = types.str;
      default = "develop";
      description = "Upstream default branch. Currently the only maintained branch.";
    };

    domain = mkOption {
      type = types.str;
      default = "nixos.tail69fe1.ts.net";
      description = "Public host under which the app is served (Tailscale Serve).";
    };

    port = mkOption {
      type = types.port;
      default = 4000;
      description = "Public HTTPS port (Tailscale Serve) and web container port.";
    };

    traefikPort = mkOption {
      type = types.port;
      default = 8081;
      description = "Loopback port Traefik listens on (Tailscale Serve fronts this).";
    };

    temporalUiPort = mkOption {
      type = types.port;
      default = 8082;
      description = "Loopback port for the Temporal UI (Tailscale Serve fronts this).";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
    };

    user = mkOption {
      type = types.str;
      default = "aixle-flow";
      description = "User the service runs as. Needs docker group for the socket.";
    };

    environmentFile = mkOption {
      type = types.path;
      default = "/home/jay/.secrets/aixle-flow.env";
      description = ''
        Secrets file (read by systemd as root). Required keys:
        RAILS_SECRET_KEY_BASE (openssl rand -hex 64), CREDENTIALS_SECRET_KEY,
        CONFIG_ITEMS_SECRET_KEY, INTEGRATIONS_SECRET_KEY, OAUTH_SECRET_KEY
        (each openssl rand -hex 32), ADMIN_PASSWORD. Optional:
        SUPER_ADMIN_EMAIL (defaults to admin@aixle.com), GOOGLE_CLIENT_ID/SECRET.
      '';
    };
  };

  config = mkIf cfg.enable {
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.user;
      home = cfg.dataDir;
      createHome = true;
      # docker: the unit shells out to docker for compose/builds, and the
      # worker container needs the host socket (see workerEntrypoint).
      extraGroups = [ "docker" ];
    };
    users.groups.${cfg.user} = { };

    systemd.services.aixle-flow = {
      description = "Aixle Flow agent orchestration platform (compose stack)";
      after = [ "docker.service" "network-online.target" ];
      wants = [ "network-online.target" ];
      requires = [ "docker.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = cfg.user;
        Group = cfg.user;
        WorkingDirectory = cfg.dataDir;
        EnvironmentFile = [ cfg.environmentFile ];
        Restart = "on-failure";
        RestartSec = "15";
        TimeoutStartSec = "3600";
        TimeoutStopSec = "600";
        ExecStartPre = [
          # Clone or fast-forward the tracked branch. Reset --hard: upstream
          # moves fast and we deploy their code, not local edits.
          "${pkgs.bash}/bin/bash -c 'if [ ! -d flow/.git ]; then ${pkgs.git}/bin/git clone --branch ${cfg.repoBranch} ${cfg.repoUrl} flow; else cd flow && ${pkgs.git}/bin/git fetch origin ${cfg.repoBranch} && ${pkgs.git}/bin/git reset --hard origin/${cfg.repoBranch}; fi'"
          # Build/rebuild the web image (layer cache makes no-op boots fast).
          "${pkgs.bash}/bin/bash -c 'cd flow && ${pkgs.docker}/bin/docker compose -f docker-compose.yml -f ${composeFile} build web'"
        ];
        ExecStart = "${pkgs.bash}/bin/bash -c 'cd flow && ${pkgs.docker}/bin/docker compose -f docker-compose.yml -f ${composeFile} up --detach'";
        # Best-effort: named volume is root-owned on first mount; the app
        # user inside the container needs /app/storage. Don't fail the unit.
        ExecStartPost = "${pkgs.bash}/bin/bash -c 'cd flow && for i in $(seq 1 30); do ${pkgs.docker}/bin/docker compose -f docker-compose.yml -f ${composeFile} exec -u root -T web chown -R app:app storage && exit 0; sleep 2; done; exit 0'";
        # Compose stop honors worker's stop_grace_period (Temporal drain).
        ExecStop = "${pkgs.bash}/bin/bash -c 'cd flow && ${pkgs.docker}/bin/docker compose -f docker-compose.yml -f ${composeFile} stop || true'";
      };
    };

    systemd.services.aixle-flow-agents = {
      description = "Aixle Flow agent runtime image builds";
      after = [ "aixle-flow.service" "docker.service" ];
      wants = [ "aixle-flow.service" ];
      requires = [ "docker.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = cfg.user;
        Group = cfg.user;
        WorkingDirectory = "${cfg.dataDir}";
        TimeoutStartSec = "3600";
        # Base image first (agent images FROM it), then the five runtimes.
        # Contexts mirror upstream's Makefile: base/Dockerfile COPYs its
        # siblings (probe-browser.js etc.) so it builds from base/, the
        # runtime Dockerfiles reference files across docker/ from its root.
        ExecStart = "${pkgs.bash}/bin/bash -c 'cd flow/docker && ${pkgs.docker}/bin/docker build -t aixle/agent-base-core:latest -f base/Dockerfile base && ${pkgs.docker}/bin/docker build -t aixle/claude-code:latest -f claude-code/Dockerfile . && ${pkgs.docker}/bin/docker build -t aixle/codex:latest -f codex/Dockerfile . && ${pkgs.docker}/bin/docker build -t aixle/cursor-cli:latest -f cursor-cli/Dockerfile . && ${pkgs.docker}/bin/docker build -t aixle/gemini-cli:latest -f gemini-cli/Dockerfile . && ${pkgs.docker}/bin/docker build -t aixle/grok:latest -f grok/Dockerfile .'";
      };
    };

    # Tailscale Serve: the only public listener. Fronts Traefik so the web app
    # and every agent-container terminal route share one origin/port.
    systemd.services.tailscale-serve-aixle-flow = {
      description = "Tailscale Serve for Aixle Flow";
      after = [ "tailscaled.service" "aixle-flow.service" ];
      wants = [ "tailscaled.service" "aixle-flow.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.tailscale ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStartPre = "${pkgs.bash}/bin/bash -c 'for i in $(seq 1 30); do tailscale status >/dev/null 2>&1 && exit 0; sleep 1; done; exit 1'";
        ExecStart = "${pkgs.bash}/bin/bash -c 'for i in $(seq 1 5); do ${pkgs.tailscale}/bin/tailscale serve --bg --https=${toString cfg.port} http://127.0.0.1:${toString cfg.traefikPort} && exit 0; sleep 2; done; exit 1'";
        ExecStop = "${pkgs.tailscale}/bin/tailscale serve --https=${toString cfg.port} off";
      };
    };

    systemd.services.tailscale-serve-aixle-flow-temporal-ui = {
      description = "Tailscale Serve for Aixle Flow Temporal UI";
      after = [ "tailscaled.service" "aixle-flow.service" ];
      wants = [ "tailscaled.service" "aixle-flow.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.tailscale ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStartPre = "${pkgs.bash}/bin/bash -c 'for i in $(seq 1 30); do tailscale status >/dev/null 2>&1 && exit 0; sleep 1; done; exit 1'";
        ExecStart = "${pkgs.bash}/bin/bash -c 'for i in $(seq 1 5); do ${pkgs.tailscale}/bin/tailscale serve --bg --https=${toString cfg.temporalUiPort} http://127.0.0.1:${toString cfg.temporalUiPort} && exit 0; sleep 2; done; exit 1'";
        ExecStop = "${pkgs.tailscale}/bin/tailscale serve --https=${toString cfg.temporalUiPort} off";
      };
    };

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [
      cfg.port
      cfg.traefikPort
      cfg.temporalUiPort
    ];
  };
}
