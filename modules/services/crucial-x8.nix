# Crucial X8 external drive CIFS mount served by the nixos host.
#
# Mounts the share at /mnt/crucial-x8 with nofail + noauto +
# x-systemd.automount so it mounts on first access and doesn't block
# boot if the server is unreachable.
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.crucial-x8;
in
{
  options.crucial-x8 = {
    enable = mkEnableOption "Crucial X8 CIFS mount from nixos host";

    mountPoint = mkOption {
      type = types.str;
      default = "/mnt/crucial-x8";
      description = "Mount point for the Crucial X8 share.";
    };
  };

  config = mkIf cfg.enable {
    fileSystems."${cfg.mountPoint}" = {
      device = "//nixos/Crucial X8";
      fsType = "cifs";
      options = [
        "guest"
        "uid=1000"
        "gid=100"
        "nofail"
        "noauto"
        "x-systemd.automount"
        "x-systemd.idle-timeout=60"
      ];
    };

    environment.systemPackages = with pkgs; [ cifs-utils ];
  };
}
