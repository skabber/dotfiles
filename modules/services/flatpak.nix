{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.flatpak;
in
{
  options.flatpak = {
    enable = mkEnableOption "Flatpak with declarative remotes";

    remotes = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          url = mkOption {
            type = types.str;
            description = "URL to the .flatpakrepo file for the remote";
          };
        };
      });
      # orion-beta is baked into every host by default. Hosts can override
      # by setting flatpak.remotes = lib.mkForce { } to remove it.
      default = {
        orion-beta = {
          url = "https://flatpak.orionbrowser.com/orion-beta.flatpakrepo";
        };
      };
      description = "Flatpak remotes to register idempotently on activation";
    };
  };

  config = mkIf cfg.enable {
    services.flatpak.enable = true;
    xdg.portal.enable = mkDefault true;

    system.activationScripts.flatpakRemotes = {
      deps = [ "etc" "users" ];
      text = concatStringsSep "\n" (mapAttrsToList
        (name: remote: ''
          if ${pkgs.flatpak}/bin/flatpak remote-list 2>/dev/null | grep -q "^${name}\b"; then
            ${pkgs.flatpak}/bin/flatpak remote-modify ${name} --url=${escapeShellArg remote.url} || true
          else
            ${pkgs.flatpak}/bin/flatpak remote-add --if-not-exists ${name} ${escapeShellArg remote.url} || true
          fi
        '')
        cfg.remotes);
    };
  };
}
