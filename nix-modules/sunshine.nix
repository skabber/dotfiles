
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.sunshine;
in
{
  options.sunshine.enable = mkEnableOption "Sunshine";

  options.sunshine.autoStart = mkOption {
    type = types.bool;
    default = true;
    description = "Whether to automatically start Sunshine.";
  };

  options.sunshine.capSysAdmin = mkOption {
    type = types.bool;
    default = true;
    description = "Whether to grant CAP_SYS_ADMIN capability to Sunshine.";
  };

  options.sunshine.openFirewall = mkOption {
    type = types.bool;
    default = true;
    description = "Whether to open firewall ports for Sunshine.";
  };

  config = mkIf cfg.enable {
    services.sunshine = {
      enable = true;
      autoStart = cfg.autoStart;
      capSysAdmin = cfg.capSysAdmin;
      openFirewall = cfg.openFirewall;
    };
  };
}
