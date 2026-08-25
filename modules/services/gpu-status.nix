# gpu-status: tiny read-only amdgpu VRAM endpoint for the crumpet GPU steward.
#
# crumpet-core's `gpu` module asks http://<ollama-host>:7861/vram for
# host-level VRAM when the app runs on another machine (the framework
# laptops over Tailscale); locally it reads sysfs itself and never needs
# this. Firewall is tailscale-only, matching the Ollama service's policy.

{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.gpu-status;

  server = pkgs.writers.writePython3 "gpu-status" { } ''
    import glob
    import json
    import os
    import http.server


    def read_int(path):
        try:
            with open(path) as f:
                return int(f.read().strip())
        except OSError:
            return None


    def vram():
        cards = []
        for total_path in glob.glob(
            "/sys/class/drm/card*/device/mem_info_vram_total"
        ):
            total = read_int(total_path)
            if total:
                cards.append((os.path.dirname(total_path), total))
        if not cards:
            return None
        # Report the largest GPU (the one Ollama/MOSS actually use).
        best_dir, total = max(cards, key=lambda c: c[1])
        used = read_int(os.path.join(best_dir, "mem_info_vram_used"))
        if used is None:
            return None
        return {
            "vram_used": used,
            "vram_total": total,
            "gtt_used": read_int(os.path.join(best_dir, "mem_info_gtt_used")),
        }


    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path != "/vram":
                self.send_error(404)
                return
            data = vram()
            if data is None:
                self.send_error(503, "no amdgpu sysfs")
                return
            body = json.dumps(data).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass


    http.server.ThreadingHTTPServer(("0.0.0.0", ${toString cfg.port}), Handler).serve_forever()
  '';
in
{
  options.gpu-status = {
    enable = mkEnableOption "gpu-status: read-only amdgpu VRAM endpoint (GET /vram) for remote crumpet clients";

    port = mkOption {
      type = types.port;
      default = 7861;
      description = "Port serving GET /vram. Must match crumpet-core's gpu::GPU_STATUS_PORT.";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.gpu-status = {
      description = "Read-only amdgpu VRAM endpoint (GET /vram)";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${server}";
        DynamicUser = true;
        Restart = "on-failure";
        RestartSec = 5;
      };
    };

    # Tailnet peers only (crumpet on the laptops); loopback needs no rule.
    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ cfg.port ];
  };
}
