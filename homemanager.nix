{ config, pkgs, ... }:
let
  # home-manager = builtins.fetchTarball "https://github.com/nix-community/home-manager/archive/release-23.11.tar.gz";
  home-manager = builtins.fetchTarball "https://github.com/nix-community/home-manager/archive/master.tar.gz";
  # stable = import <stable> { config.allowUnfree = true; };
in
{
  imports = [
    (import "${home-manager}/nixos")
  ];
  nixpkgs.config.permittedInsecurePackages = [
    "electron-25.9.0"
  ];
  home-manager.users.jay = {
    /* The home.stateVersion option does not have a default and must be set */
    home.stateVersion = "23.11";
    /* Here goes the rest of your home-manager config, e.g. home.packages = [ pkgs.foo ]; */
    home.packages = [
      pkgs.htop
      pkgs.git
      pkgs.tig
      pkgs.deno
      pkgs.rustup
      pkgs.opentofu
      pkgs.vscode
      pkgs.openvscode-server
      pkgs.jetbrains.rust-rover
      pkgs.direnv
      pkgs.starship
      pkgs.zip
      pkgs.cider
      pkgs.google-chrome
      pkgs.vim
      pkgs.appimage-run
      pkgs.alacritty
      pkgs.remmina
      pkgs.rpi-imager
      pkgs.go
      pkgs.zig
      pkgs.zig-shell-completions
      pkgs.system76-keyboard-configurator
      pkgs.gopls
      pkgs.taplo
      pkgs.nodePackages.typescript-language-server
      pkgs.nodePackages_latest.vscode-json-languageserver
      pkgs.yaml-language-server
      pkgs.zip
      pkgs.zls
      pkgs.python311Packages.python-lsp-server
      pkgs.nil
      pkgs.marksman
      pkgs.dockerfile-language-server-nodejs
      pkgs.slack
      pkgs.discord
      pkgs.flatpak
      pkgs.appimage-run
      pkgs.trayscale
      pkgs.obsidian
      pkgs.fermyon-spin
      pkgs.gjs
      pkgs.vte
      pkgs.heroic
      pkgs.gnomeExtensions.tailscale-qs
      pkgs.zoom-us
      pkgs.teams-for-linux
      pkgs.gnumake
      pkgs.android-studio
      pkgs.ryujinx
      pkgs.neofetch
      pkgs.awscli2
      pkgs.cargo-espflash
      pkgs.espup
      pkgs.zed-editor
      pkgs.nushell
      pkgs.bottles
      pkgs.dualsensectl
      # Cosmic DE Stuff
      pkgs.cosmic-term
      pkgs.cosmic-edit
      pkgs.cosmic-bg
      pkgs.cosmic-osd
      pkgs.cosmic-comp
      pkgs.cosmic-randr
      pkgs.cosmic-panel
      pkgs.cosmic-icons
      pkgs.cosmic-greeter
      pkgs.cosmic-files
      pkgs.cosmic-applets
      pkgs.cosmic-settings
      pkgs.cosmic-launcher
      pkgs.cosmic-screenshot
      pkgs.cosmic-applibrary
      pkgs.cosmic-design-demo
      pkgs.cosmic-notifications
      pkgs.cosmic-settings-daemon
      pkgs.cosmic-workspaces-epoch
    ];
    # programs.1password.enable = true;
    # programs.1password-gui = {
      # enable = true;
      # Certain features, including CLI integration and system authentication support,
      # require enabling PolKit integration on some desktop environments (e.g. Plasma).
      # polkitPolicyOwners = [ "jay" ];
    # };
    # programs.bash.enable = true;
    # programs.bash.initExtra = ''
     # source /home/jay/.bash_profile.local     
    # '';
    # programs.zsh.enable = true;
    programs.zsh.initExtra = ''
      source /home/jay/dotfiles/zshconfig
    '';
    # programs.git = {
    #   enable = true;
    #   userName = "Jay Graves";
    #   userEmail = "jay@skabber.com";
    #   iniContent.commit.gpgSign = true;
    #   includes = [
    #     { path = "~/.gitconfig"; }
    #   ];
    # };
    # home.file.".gitconfig".source = /home/jay/dotfiles/gitconfig;
    # home.file.".bash_profile.local".source = /home/jay/dotfiles/bashconfig;
    # home.file.".zsh_profile.local".source = /home/jay/dotfiles/zshconfig;
  };
}
