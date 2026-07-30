# NixOS module: rclone S3 mount via systemd service
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.rclone-s3;
in
{
  options.rclone-s3 = {
    enable = mkEnableOption "rclone S3 mount";

    remoteName = mkOption {
      type = types.str;
      default = "mys3";
      description = "Rclone remote name matching RCLONE_CONFIG_<NAME>_* env vars.";
    };

    bucket = mkOption {
      type = types.str;
      description = "S3 bucket name to mount.";
    };

    mountPoint = mkOption {
      type = types.path;
      default = "/home/jay/S3-Bucket";
      description = "Local path where the bucket will be mounted.";
    };

    user = mkOption {
      type = types.str;
      default = "jay";
      description = "User to run the mount service as.";
    };

    environmentFile = mkOption {
      type = types.path;
      default = "/home/jay/.secrets/rclone-s3.env";
      description = "Path to file containing RCLONE_CONFIG_* credentials.";
    };

    vfsCacheMode = mkOption {
      type = types.enum [ "off" "minimal" "writes" "full" ];
      default = "full";
      description = "Rclone VFS cache mode.";
    };
  };

  config = mkIf cfg.enable {
    programs.fuse.userAllowOther = true;

    security.wrappers.fusermount3 = {
      source = "${pkgs.fuse3}/bin/fusermount3";
      owner = "root";
      group = "root";
      setuid = true;
    };

    environment.systemPackages = [ pkgs.rclone pkgs.fuse3 ];

    systemd.tmpfiles.rules = [
      "d ${cfg.mountPoint} 0755 ${cfg.user} users -"
    ];

    systemd.services.rclone-s3-mount = {
      description = "Mount S3 bucket via rclone";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Restart = "on-failure";
        RestartSec = "15s";
        Environment = "PATH=${config.security.wrapperDir}:/run/current-system/sw/bin";
        EnvironmentFile = cfg.environmentFile;
        ExecStart = ''
          ${pkgs.rclone}/bin/rclone mount \
            ${cfg.remoteName}:${cfg.bucket} \
            ${cfg.mountPoint} \
            --vfs-cache-mode ${cfg.vfsCacheMode} \
            --allow-other
        '';
        ExecStop = "/run/wrappers/bin/fusermount3 -u ${cfg.mountPoint}";
      };
    };
  };
}
