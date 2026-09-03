# gpu-gateway: single-GPU time-share scheduler between moss-transcribe
# (preferred tenant) and freetoken on hosts where both share one card.
#
# The gateway is the only thing that starts/stops the two engines; it holds
# freetoken requests and mutating moss requests in-process while the
# required engine is down, waits for VRAM release between engines, and
# drains in-flight work before switching. Two loopback front ports are
# published on the tailnet under the services' original public port numbers
# via Tailscale Serve, so tailnet clients need no changes. Runs as root
# (systemctl control), like service-panel.
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.gpu-gateway;

  py = pkgs.python3.withPackages (ps: with ps; [
    fastapi
    uvicorn
    httpx
  ]);

  serveUnit = name: pubPort: frontPort: {
    description = "Tailscale Serve for gpu-gateway ${name} (${toString pubPort})";
    after = [ "tailscaled.service" ];
    wants = [ "tailscaled.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.tailscale ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStartPre = "${pkgs.bash}/bin/bash -c 'for i in $(seq 1 30); do tailscale status >/dev/null 2>&1 && exit 0; sleep 1; done; exit 1'";
      # Retry: concurrent serve units racing one config write get an etag
      # mismatch; retry the whole serve until it sticks.
      ExecStart = "${pkgs.bash}/bin/bash -c 'for i in $(seq 1 5); do ${pkgs.tailscale}/bin/tailscale serve --bg --https=${toString pubPort} http://127.0.0.1:${toString frontPort} && exit 0; sleep 2; done; exit 1'";
      ExecStop = "${pkgs.tailscale}/bin/tailscale serve --https=${toString pubPort} off";
    };
  };
in
{
  options.gpu-gateway = {
    enable = mkEnableOption "gpu-gateway: time-share one GPU between moss-transcribe and freetoken";

    ftFrontPort = mkOption {
      type = types.port;
      default = 7870;
      description = "Loopback front port proxying the freetoken API.";
    };

    mossFrontPort = mkOption {
      type = types.port;
      default = 7871;
      description = "Loopback front port proxying the moss jobs API/web UI.";
    };

    ftUnit = mkOption {
      type = types.str;
      default = "freetoken.service";
      description = "systemd unit of the freetoken engine.";
    };

    mossUnit = mkOption {
      type = types.str;
      default = "moss-transcribe.service";
      description = "systemd unit of the moss vLLM engine (not the web unit).";
    };

    coalesceSec = mkOption {
      type = types.ints.positive;
      default = 8;
      description = "Wait after the first freetoken request before switching engines (batches arrivals).";
    };

    ftIdleSec = mkOption {
      type = types.ints.positive;
      default = 300;
      description = "Freetoken idle time before returning the GPU to moss.";
    };

    drainTimeoutSec = mkOption {
      type = types.ints.positive;
      default = 600;
      description = "Max wait for in-flight freetoken requests to finish once moss work is waiting; past this the engine is stopped anyway.";
    };

    ftStallSec = mkOption {
      type = types.ints.positive;
      default = 120;
      description = "Cut an in-flight freetoken stream that has produced no bytes for this long once moss work is waiting (hung streams otherwise pin the GPU through the whole drain window).";
    };

    ftStallHardSec = mkOption {
      type = types.ints.positive;
      default = 900;
      description = "Hard cap on silent freetoken streams even with no moss work waiting; past this the stream is cut so ghost counters cannot pin the GPU forever.";
    };

    maxHoldSec = mkOption {
      type = types.ints.positive;
      default = 900;
      description = "Per-request hold cap; held requests get 503 past this.";
    };

    healthTimeoutSec = mkOption {
      type = types.ints.positive;
      default = 900;
      description = "Max wait for an engine to come up healthy (model load, JIT).";
    };

    switchCooldownSec = mkOption {
      type = types.ints.positive;
      default = 60;
      description = "Minimum dwell in a state before another switch (thrash guard).";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = config.moss-transcribe.enable && config.freetoken.enable;
        message = "gpu-gateway requires both moss-transcribe and freetoken to be enabled";
      }
      {
        assertion = config.moss-transcribe.backend == "vllm";
        message = "gpu-gateway manages the vllm backend (separate engine + web units)";
      }
    ];

    systemd.services.gpu-gateway = {
      description = "GPU gateway: time-shares the GPU between moss-transcribe and freetoken";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      environment = {
        GW_UI_HTML = "${./gpu-gateway.html}";
        GW_FT_FRONT_PORT = toString cfg.ftFrontPort;
        GW_MOSS_FRONT_PORT = toString cfg.mossFrontPort;
        GW_FT_BACKEND = "http://127.0.0.1:${toString config.freetoken.port}";
        GW_MOSS_BACKEND = "http://127.0.0.1:${toString config.moss-transcribe.port}";
        GW_FT_HEALTH = "http://127.0.0.1:${toString config.freetoken.port}/v1/models";
        GW_MOSS_HEALTH = "http://127.0.0.1:${toString config.moss-transcribe.vllmPort}/v1/models";
        GW_FT_UNIT = cfg.ftUnit;
        GW_MOSS_UNIT = cfg.mossUnit;
        GW_COALESCE_SEC = toString cfg.coalesceSec;
        GW_FT_IDLE_SEC = toString cfg.ftIdleSec;
        GW_DRAIN_TIMEOUT_SEC = toString cfg.drainTimeoutSec;
        GW_FT_STALL_SEC = toString cfg.ftStallSec;
        GW_FT_STALL_HARD_SEC = toString cfg.ftStallHardSec;
        GW_MAX_HOLD_SEC = toString cfg.maxHoldSec;
        GW_HEALTH_TIMEOUT_SEC = toString cfg.healthTimeoutSec;
        GW_SWITCH_COOLDOWN_SEC = toString cfg.switchCooldownSec;
      };
      serviceConfig = {
        ExecStart = "${py}/bin/python ${./gpu-gateway.py}";
        StateDirectory = "gpu-gateway";
        Restart = "on-failure";
        RestartSec = "5s";
        TimeoutStopSec = "15s";
      };
    };

    systemd.services.tailscale-serve-gpu-gateway-freetoken =
      serveUnit "freetoken" config.freetoken.port cfg.ftFrontPort;
    systemd.services.tailscale-serve-gpu-gateway-moss =
      serveUnit "moss" config.moss-transcribe.port cfg.mossFrontPort;

    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
      config.freetoken.port
      config.moss-transcribe.port
    ];
  };
}
