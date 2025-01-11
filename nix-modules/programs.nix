# my-module.nix
{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    meld
  ];
}