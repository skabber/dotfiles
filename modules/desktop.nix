# GNOME Desktop with AMD GPU
{ config, pkgs, lib, ... }:

{
  imports = [ ./desktop-base.nix ];

  services.xserver.videoDrivers = [ "amdgpu" ];

  environment.systemPackages = with pkgs; [
    pulseaudio
    pipewire
  ];
}
