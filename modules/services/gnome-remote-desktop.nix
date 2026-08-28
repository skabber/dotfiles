# GNOME Remote Desktop — native RDP over Wayland
# Remote Login (headless GDM session via system daemon) + Desktop Sharing
# (attach to existing session via user daemon + handover).
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.gnome-remote-desktop;
in
{
  options.gnome-remote-desktop = {
    enable = mkEnableOption "GNOME Remote Desktop with native RDP";

    port = mkOption {
      type = types.port;
      default = 3389;
      description = "TCP port the RDP server binds to.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to open the RDP port in the firewall.";
    };

    credentialsFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      example = "/home/jay/.secrets/grd-rdp.env";
      description = ''
        Environment file with RDP_USERNAME and RDP_PASSWORD provisioning the
        system daemon (Remote Login) via grdctl. Restart
        gnome-remote-desktop-configure.service after changing it.
        When null, configure manually with (as root):
        runuser -u gnome-remote-desktop -- grdctl rdp set-credentials <user> <password>
        Note: avoid `grdctl rdp enable` — it shells out to pkexec +
        `systemctl enable`, which cannot work on NixOS. Instead ensure
        enabled=true in [RDP] in /etc/gnome-remote-desktop/grd.conf and that
        gnome-remote-desktop.service is enabled declaratively.
      '';
    };
  };

  config = mkIf cfg.enable {
    services.gnome.gnome-remote-desktop.enable = true;

    # NixOS presets ignore packaged [Install] sections, so wire both daemons
    # explicitly: system daemon for Remote Login, user daemon for Desktop
    # Sharing (handover from the system daemon).
    systemd.services.gnome-remote-desktop.wantedBy = [ "graphical.target" ];
    systemd.user.services.gnome-remote-desktop.wantedBy = [ "gnome-session.target" ];

    networking.firewall = mkIf cfg.openFirewall {
      allowedTCPPorts = [ cfg.port ];
    };

    # grdctl writes system settings to /etc/gnome-remote-desktop/grd.conf (owned
    # by the gnome-remote-desktop user) and the daemon watches that file, so no
    # restart is needed for config changes.
    # `grdctl rdp enable` is NOT used: it re-execs through pkexec to run
    # `systemctl enable`, which cannot work on NixOS (/etc/systemd/system is a
    # read-only store path). Unit enablement is declarative via wantedBy above,
    # so we only need the rdp-enabled=true keyfile entry that enable would write.
    systemd.services.gnome-remote-desktop-configure = mkIf (cfg.credentialsFile != null) {
      description = "Provision GNOME Remote Desktop system daemon (Remote Login)";
      wantedBy = [ "multi-user.target" ];
      before = [ "gnome-remote-desktop.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        EnvironmentFile = cfg.credentialsFile;
      };
      path = [
        pkgs.gnome-remote-desktop
        pkgs.util-linux
        pkgs.openssl
        pkgs.gnused
        pkgs.gnugrep
      ];
      script = ''
        conf=/etc/gnome-remote-desktop/grd.conf
        tls_dir=/var/lib/gnome-remote-desktop/rdp-tls

        # The system daemon does not auto-generate TLS credentials (only the
        # user daemon does, via the keyring). Generate a self-signed pair for
        # RDP once; RDP clients accept it after the usual certificate prompt.
        if [ ! -s "$tls_dir/tls.key" ] || [ ! -s "$tls_dir/tls.crt" ]; then
          mkdir -p "$tls_dir"
          chmod 700 "$tls_dir"
          chown gnome-remote-desktop:gnome-remote-desktop "$tls_dir"
          runuser -u gnome-remote-desktop -- openssl req \
            -new -newkey rsa:4096 -days 7200 -nodes -x509 \
            -subj "/CN=${config.networking.hostName}" \
            -keyout "$tls_dir/tls.key" -out "$tls_dir/tls.crt"
        fi

        runuser -u gnome-remote-desktop -- grdctl rdp set-port ${toString cfg.port}
        runuser -u gnome-remote-desktop -- grdctl rdp set-tls-cert "$tls_dir/tls.crt"
        runuser -u gnome-remote-desktop -- grdctl rdp set-tls-key "$tls_dir/tls.key"
        runuser -u gnome-remote-desktop -- grdctl rdp disable-view-only
        runuser -u gnome-remote-desktop -- grdctl rdp set-credentials "$RDP_USERNAME" "$RDP_PASSWORD"

        # enabled=true under [RDP] — what `grdctl rdp enable` would persist,
        # minus the impossible systemctl enable. System conf keys are bare
        # (enabled/port), not rdp-* names — see rdp_file_settings in
        # grd-settings-system.c: struct fields are { file_key, settings_name }.
        # Also drop a stale rdp-enabled= key if an older revision wrote one.
        grep -q '^\[RDP\]' "$conf" || printf '\n[RDP]\n' >> "$conf"
        sed -i '/^rdp-enabled=/d;/^enabled=/d' "$conf"
        sed -i '/^\[RDP\]/a enabled=true' "$conf"

        # --no-block: a synchronous restart deadlocks when this oneshot runs
        # inside a switch-to-configuration transaction (switch waits for this
        # unit, restart job waits for the switch).
        ${pkgs.systemd}/bin/systemctl --no-block try-restart gnome-remote-desktop.service || true
      '';
    };
  };
}
