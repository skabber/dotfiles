# restic-backup: nightly encrypted backups to Backblaze B2 (S3-compatible,
# restic native b2 backend). File-level copies of service data plus
# consistent database dumps staged before each run, so no backup captures a
# mid-write database. The service runs as root to read /var/lib state.
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.restic-backup;
  staging = "/var/backup/restic-staging";

  # Consistent snapshots of every DB-backed service into the staging dir.
  # Each dump is guarded so a disabled service or stopped MariaDB skips its
  # dump instead of failing the whole backup.
  dbDumps = pkgs.writeShellScript "restic-backup-dumps" ''
    set -euo pipefail
    rm -rf ${staging}
    install -d -m 700 ${staging}
    dump() {
      if [ -f "$1" ]; then
        ${pkgs.sqlite}/bin/sqlite3 "$1" ".backup '$2'"
      fi
    }
    dump /var/lib/bitwarden_rs/db.sqlite3 ${staging}/vaultwarden.sqlite3
    dump /var/lib/wallabag/data/db/wallabag.sqlite ${staging}/wallabag.sqlite
    dump /var/lib/gitea/data/gitea.db ${staging}/gitea.sqlite3
    dump /var/lib/paperless/paperless.sqlite ${staging}/paperless.sqlite3
    if ${pkgs.mariadb}/bin/mariadb-admin ping >/dev/null 2>&1; then
      ${pkgs.mariadb}/bin/mariadb-dump --single-transaction romm > ${staging}/romm.sql
    fi
  '';
in
{
  options.restic-backup = {
    enable = mkEnableOption "Restic backups to Backblaze B2";

    repository = mkOption {
      type = types.str;
      default = "b2:skabber-nixos-backups:nixos/";
      description = "Restic repository URI: b2:<bucket>:<path>. One path per host.";
    };

    passwordFile = mkOption {
      type = types.path;
      default = "/home/jay/.secrets/restic-password";
      description = "File containing the restic repository encryption password. Losing it loses the backups.";
    };

    environmentFile = mkOption {
      type = types.path;
      default = "/home/jay/.secrets/restic-b2.env";
      description = "Env file (0600) with B2_ACCOUNT_ID and B2_ACCOUNT_KEY (Backblaze application key).";
    };

    paths = mkOption {
      type = types.listOf types.path;
      default = [
        staging
        "/var/lib/bitwarden_rs"
        "/var/lib/gitea"
        "/var/lib/paperless"
        "/var/lib/wallabag"
        "/var/lib/romm"
        "/var/lib/roon-server"
        "/home/jay/.secrets"
        "/home/jay/.syncthing"
      ];
      description = "Paths to back up.";
    };

    timerConfig = mkOption {
      type = types.attrs;
      default = {
        OnCalendar = "daily";
        RandomizedDelaySec = "1h";
        Persistent = true;
      };
      description = "systemd timer config for the nightly run.";
    };
  };

  config = mkIf cfg.enable {
    services.restic.backups.nixos = {
      inherit (cfg) repository passwordFile environmentFile paths timerConfig;
      initialize = true;
      backupPrepareCommand = "${dbDumps}";
      backupCleanupCommand = "rm -rf ${staging}";
      exclude = [
        "**/.cache"
        "**/__pycache__"
      ];
      pruneOpts = [
        "--keep-daily" "7"
        "--keep-weekly" "4"
        "--keep-monthly" "6"
      ];
    };
  };
}
