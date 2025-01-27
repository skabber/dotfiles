
{ config, pkgs, lib, ... }:

with lib;

let

  cfg = config.ollama;

in

{
  options.ollama.enable = mkEnableOption "Ollama";

  options.ollama.package = mkOption {
    type = types.package;
    default = pkgs.ollama; # Replace with the actual package name if different
    description = "The Ollama package to install.";
  };

  config = mkIf cfg.enable {

    services.ollama = {
        enable = true;
        acceleration = "rocm";
        environmentVariables = {
            HCC_AMDGPU_TARGET = "gfx1030"; # used to be necessary, but doesn't seem to anymore
            # framework gfx1030
        };
        rocmOverrideGfx = "10.3.0";
    };

    systemd.services.ollama.environment = {
        OLLAMA_HOST =  lib.mkForce "0.0.0.0:11434";
    };
  };
}
