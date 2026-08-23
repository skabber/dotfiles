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
    # vulkan_beta 595.44.09 fails to compile against kernel 7.2 (implicit
    # strncpy declaration is now a hard error); stable 595.91.07 is newer
    # anyway and substitutes from cache.
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  environment.sessionVariables = {
    WLR_NO_HARDWARE_CURSORS = "1";
  };
}
