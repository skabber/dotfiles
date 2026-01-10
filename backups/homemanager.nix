{ config, pkgs, ... }:
let
  home-manager = builtins.fetchTarball "https://github.com/nix-community/home-manager/archive/master.tar.gz";
  # unstable = import <nixos-unstable> { config.allowUnfree = true; };
in
{
  imports = [
    (import "${home-manager}/nixos")
  ];
  
  home-manager.users.jay = {
    /* The home.stateVersion option does not have a default and must be set */
    home.stateVersion = "23.11";
    /* Here goes the rest of your home-manager config, e.g. home.packages = [ pkgs.foo ]; */
    home.packages = [
      pkgs.htop  
      pkgs.git
      pkgs.deno
      pkgs.rustup
      # pkgs.slack
      # pkgs.discord
      pkgs.vscode
      pkgs.direnv
      pkgs.starship
      pkgs.zip
      pkgs.mesa-demos
      pkgs.cider
      pkgs.google-chrome
      pkgs.vim
      pkgs.appimage-run
      pkgs.alacritty
      pkgs.rpi-imager
      pkgs.system76-keyboard-configurator
      pkgs.go
      pkgs.gopls
      pkgs.taplo
      pkgs.nodePackages.typescript-language-server
      pkgs.nodePackages_latest.vscode-json-languageserver
      pkgs.yaml-language-server
      pkgs.zig
      pkgs.zls
      pkgs.python311Packages.python-lsp-server
      pkgs.nil
      pkgs.marksman
      pkgs.dockerfile-language-server-nodejs
      pkgs.heroic
    ];
    # programs.steam.enable = true;
    programs.bash.enable = true;
    programs.bash.initExtra = ''
     source /home/jay/.bash_profile.local     
    '';
    programs.git = {
      enable = true;
      userName = "Jay Graves";
      userEmail = "jay@skabber.com";
      iniContent.commit.gpgSign = true;
      includes = [
        { path = "~/.gitconfig"; }
      ];
    };
    home.file.".gitconfig".source = /home/jay/dotfiles/gitconfig;
    home.file.".bash_profile.local".source = /home/jay/dotfiles/bashconfig;
# programs.git = {
#     enabled = true;
#     userName = "Jay Graves";
#     userEmail = "jay@skabber.com";
#   };
    };
}
