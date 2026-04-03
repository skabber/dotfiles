# GNOME Desktop with NVIDIA GPU
{ config, pkgs, lib, ... }:

{
  imports = [ ./desktop-base.nix ];

  services.xserver.videoDrivers = [ "nvidia" ];

  services.gnome.gnome-keyring.enable = true;

  services.pipewire.jack.enable = true;

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = false;
    powerManagement.finegrained = false;
    open = false;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.vulkan_beta;
  };

  environment.sessionVariables = {
    WLR_NO_HARDWARE_CURSORS = "1";
  };
}
