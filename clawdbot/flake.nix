{
  description = "Clawdbot configuration for nixos-ripper";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nix-clawdbot.url = "github:moltbot/nix-clawdbot";
  };

  outputs = { self, nixpkgs, home-manager, nix-clawdbot }:
    let
      system = "x86_64-linux";
      username = "jay";
      homeDir = "/home/jay";
      secretsDir = "${homeDir}/.secrets/clawdbot";
      pkgs = import nixpkgs { inherit system; overlays = [ nix-clawdbot.overlays.default ]; };
    in {
      homeConfigurations.${username} = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [
          nix-clawdbot.homeManagerModules.clawdbot
          {
            home.username = username;
            home.homeDirectory = homeDir;
            home.stateVersion = "23.11";
            programs.home-manager.enable = true;

            programs.clawdbot = {
              instances.default = {
                enable = true;

                providers.telegram = {
                  enable = true;
                  botTokenFile = "${secretsDir}/telegram-bot-token";
                  allowFrom = [ 8105954598 ];
                  groups = {
                    "*" = { requireMention = true; };
                  };
                };

                providers.anthropic = {
                  apiKeyFile = "${secretsDir}/anthropic-api-key";
                };

                plugins = [];
              };
            };
          }
        ];
      };
    };
}
