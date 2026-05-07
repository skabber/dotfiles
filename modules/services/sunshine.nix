{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.sunshine;
in
{
  options.sunshine = {
    enable = mkEnableOption "Sunshine";

    package = mkOption {
      type = types.package;
      default = pkgs.sunshine;
      defaultText = literalExpression "pkgs.sunshine";
      description = "The Sunshine package to use.";
    };

    autoStart = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to automatically start Sunshine.";
    };

    capSysAdmin = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to grant CAP_SYS_ADMIN (required for DRM/KMS capture).";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to open firewall ports for Sunshine.";
    };

    settings = mkOption {
      type = types.attrs;
      default = { };
      example = literalExpression ''{ sunshine_name = "nixos-ripper"; port = 47989; }'';
      description = ''
        Declarative sunshine.conf settings. When set (any key other than the
        default port), web-UI configuration is locked out.
      '';
    };

    applications = mkOption {
      type = types.attrs;
      default = { };
      example = literalExpression ''
        {
          env = { PATH = "$(PATH):$(HOME)/.local/bin"; };
          apps = [ { name = "Desktop"; auto-detach = "true"; } ];
        }
      '';
      description = ''
        Declarative apps.json (env + apps list). When set, app configuration
        from the web UI is disabled.
      '';
    };
  };

  config = mkIf cfg.enable {
    services.sunshine = {
      enable = true;
      package = cfg.package;
      autoStart = cfg.autoStart;
      capSysAdmin = cfg.capSysAdmin;
      openFirewall = cfg.openFirewall;
      settings = cfg.settings;
      applications = cfg.applications;
    };
  };
}
