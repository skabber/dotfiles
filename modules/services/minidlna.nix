# MiniDLNA — UPnP/DLNA media server for VLC and other LAN clients

{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.minidlna;
in
{
  options.minidlna.enable = mkEnableOption "MiniDLNA media server";

  options.minidlna.mediaDir = mkOption {
    type = types.path;
    default = "/mnt/encrypted";
    description = "Video directory to serve over UPnP/DLNA.";
  };

  options.minidlna.openFirewall = mkOption {
    type = types.bool;
    default = true;
    description = "Whether to open firewall ports for MiniDLNA.";
  };

  config = mkIf cfg.enable {
    services.minidlna = {
      enable = true;
      openFirewall = cfg.openFirewall;
      settings = {
        media_dir = [ "V,${toString cfg.mediaDir}" ];
        inotify = "yes";
      };
    };

    users.users.minidlna.extraGroups = [ "users" ];
  };
}
