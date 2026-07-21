# Common Home Manager configuration shared across all machines
{
  config,
  pkgs,
  lib,
  ...
}:

{
  home.stateVersion = "23.11";

  # Common packages for all machines
  home.packages = with pkgs; [
    # Core tools
    ghostty.terminfo
    lsof
    # cemu
    htop
    git
    git-lfs
    gh
    tea
    hub
    tig
    ripgrep
    unzip
    zip
    jq
    tmux
    alsa-utils
    ffmpeg

    # Development
    nodejs_22
    direnv
    starship
    vim
    neovim
    fresh-editor

    # Language servers
    typescript-language-server
    vscode-langservers-extracted
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

    # Utilities (local packages)
    (pkgs.callPackage ../pkgs/proton-drive-cli.nix {})
    (pkgs.callPackage ../pkgs/hermes.nix { })

    # Agent stuff
    agent-browser
    herdr

    # Utilities
    # trayscale  # FIXME: broken with Go 1.26 in nixpkgs (gvisor build tag conflict)
    yazi
    fastfetch
    fzf
    zoxide
    eza
    bat

    # GNOME extensions
    gnomeExtensions.tailscale-qs
    gnomeExtensions.pano
  ];

  # Git configuration
  programs.git = {
    enable = true;
    signing.format = "openpgp";
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

  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    settings."*" = {
      IdentityAgent = "${config.home.homeDirectory}/.1password/agent.sock";
    };
  };

  home.sessionVariables = {
    SSH_AUTH_SOCK = "${config.home.homeDirectory}/.1password/agent.sock";
  };

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

  # GNOME — show Log Out in the system menu (hidden by default on single-user systems)
  dconf.settings = {
    "org/gnome/shell" = {
      always-show-log-out = true;
    };
  };
}
