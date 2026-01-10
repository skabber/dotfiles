
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.syncthing;
in
{
  options.syncthing.enable = mkEnableOption "Syncthing";

  options.syncthing.user = mkOption {
    type = types.str;
    default = "jay";
    description = "User account under which Syncthing runs.";
  };

  options.syncthing.dataDir = mkOption {
    type = types.path;
    default = "/home/jay";
    description = "Default folder for Syncthing files.";
  };

  options.syncthing.configDir = mkOption {
    type = types.path;
    default = "/home/jay/.config/syncthing";
    description = "Directory for Syncthing configuration files.";
  };

  options.syncthing.openFirewall = mkOption {
    type = types.bool;
    default = true;
    description = "Whether to open firewall ports for Syncthing.";
  };

  options.syncthing.guiAddress = mkOption {
    type = types.str;
    default = "127.0.0.1:8384";
    description = "Address and port for the Syncthing web GUI.";
  };

  config = mkIf cfg.enable {
    services.syncthing = {
      enable = true;
      user = cfg.user;
      dataDir = cfg.dataDir;
      configDir = cfg.configDir;
      openDefaultPorts = cfg.openFirewall;
      guiAddress = cfg.guiAddress;
    };
  };
}
