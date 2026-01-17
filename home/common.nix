# Common Home Manager configuration shared across all machines
{ config, pkgs, lib, ... }:

{
  home.stateVersion = "23.11";

  # Common packages for all machines
  home.packages = with pkgs; [
    # Core tools
    htop
    git
    git-lfs
    gh
    hub
    tig
    ripgrep
    unzip
    zip
    jq
    tmux

    # Development
    nodejs_22
    direnv
    starship
    vim
    neovim

    # Language servers
    nodePackages.typescript-language-server
    nodePackages.vscode-json-languageserver
    yaml-language-server
    nil
    nixd
    marksman
    markdown-oxide
    dockerfile-language-server
    docker-compose-language-service

    # Desktop apps
    vscode
    google-chrome
    slack
    discord
    obsidian
    flatpak
    appimage-run

    # Utilities
    trayscale
    yazi
    neofetch

    # GNOME extensions
    gnomeExtensions.tailscale-qs
    gnomeExtensions.pano
  ];

  # Git configuration
  programs.git = {
    enable = true;
    settings = {
      user.name = "Jay Graves";
      user.email = "jay@skabber.com";
      commit.gpgSign = true;
    };
    includes = [
      { path = "~/.gitconfig"; }
    ];
  };

  # Dotfiles
  home.file.".gitconfig".source = ../gitconfig;
  home.file.".zshrc".source = ../zshconfig;

  # Direnv
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  # Starship prompt
  programs.starship = {
    enable = true;
    settings = {
      add_newline = false;
      package.disabled = true;
    };
  };
}
