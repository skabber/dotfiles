{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.samba-share;

  shareToSettings = _name: share: {
    path = share.path;
    comment = share.comment;
    "read only" = if share.readOnly then "yes" else "no";
    browseable = "yes";
    "guest ok" = "yes";
    "force user" = share.forceUser;
  };
in
{
  options.samba-share = {
    enable = mkEnableOption "Samba network file sharing";

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open firewall ports 139 and 445 for Samba.";
    };

    allowedHosts = mkOption {
      type = types.listOf types.str;
      default = [ "100.64.0.0/10" "127.0.0.1" ];
      description = "Hosts/subnets allowed to connect (defaults to Tailscale CGNAT range + localhost).";
    };

    shares = mkOption {
      description = "Samba shares to export.";
      default = {};
      type = types.attrsOf (types.submodule {
        options = {
          path = mkOption {
            type = types.str;
            description = "Path to the directory to share.";
          };
          comment = mkOption {
            type = types.str;
            default = "";
            description = "Human-readable description of the share.";
          };
          readOnly = mkOption {
            type = types.bool;
            default = false;
            description = "Whether the share is read-only.";
          };
          forceUser = mkOption {
            type = types.str;
            default = "jay";
            description = "Run all file operations as this user (needed for exFAT drives mounted with uid=1000).";
          };
        };
      });
    };
  };

  config = mkIf cfg.enable {
    services.samba = {
      enable = true;
      openFirewall = cfg.openFirewall;
      settings = {
        global = {
          workgroup = "WORKGROUP";
          "server string" = config.networking.hostName;
          security = "user";
          "map to guest" = "bad user";
          "guest account" = "nobody";
          "hosts allow" = concatStringsSep " " cfg.allowedHosts;
          "hosts deny" = "ALL";
          # Disable printing to silence spooler warnings
          "load printers" = "no";
          "printing" = "bsd";
          "printcap name" = "/dev/null";
          "disable spoolss" = "yes";
        };
      } // mapAttrs shareToSettings cfg.shares;
    };

    # WS-Discovery so macOS/Windows clients can find the server on the network
    services.samba-wsdd = {
      enable = true;
      openFirewall = cfg.openFirewall;
    };
  };
}
