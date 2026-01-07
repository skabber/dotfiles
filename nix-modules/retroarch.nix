{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.retroarch;
in
{
  options.retroarch.enable = mkEnableOption "RetroArch with emulator cores";

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      (retroarch.withCores (cores: with cores; [
        # GBA
        mgba
        # PSX
        beetle-psx-hw
        # NDS
        desmume
        # Saturn
        beetle-saturn
        # NES
        fceumm
        nestopia
        # SNES
        snes9x
        bsnes
      ]))
    ];
  };
}
