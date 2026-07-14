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

                # Default agent: local Ollama-served Ornith-1.0-35B. The id
                # "ornith-35b" maps to an Ollama alias (FROM the hf.co GGUF)
                # whose PARAMETER num_ctx matches contextWindow below.
                agent.model = "ollama/ornith-35b";

                # Declare the Ollama provider + Ornith model. Ornith supports up
                # to 262144 (256K) tokens; 131072 (128K) is a bumped default for
                # this host's RAM. contextWindow is clawdbot's client-side view —
                # the server-side KV cache is Ollama's num_ctx (set on the alias).
                configOverrides = {
                  models.providers.ollama = {
                    api = "openai-completions";
                    baseUrl = "http://127.0.0.1:11434/v1";
                    apiKey = "ollama";
                    models = [{
                      id = "ornith-35b";
                      name = "Ornith 1.0 35B (Q4_K_M)";
                      contextWindow = 131072;
                      maxTokens = 32768;
                      reasoning = true;
                      input = [ "text" ];
                    }];
                  };
                };

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
