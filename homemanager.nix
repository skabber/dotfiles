{ config, pkgs, ... }:
let
  home-manager = builtins.fetchTarball "https://github.com/nix-community/home-manager/archive/release-23.11.tar.gz";
  unstable = import <nixos-unstable> { config.allowUnfree = true; };
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
      unstable.deno
      pkgs.rustup
      pkgs.cmake
      pkgs.slack
      pkgs.discord
      unstable.vscode
      pkgs.direnv
      pkgs.starship
      pkgs.mesa-demos
      pkgs.steam
      pkgs.cider
      pkgs.google-chrome
      pkgs.vim
    ];
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
