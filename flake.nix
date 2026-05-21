{
  description = "Multi-machine NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    kokoro-fastapi-nix = {
      url = "github:mndfcked/kokoro-fastapi-nix";
    };
    wallbag-rust = {
      url = "git+https://nixos.tail69fe1.ts.net:3000/skabber/wallbag-rust.git";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      kokoro-fastapi-nix,
      wallbag-rust,
      ...
    }:
    let
      system = "x86_64-linux";
      googleCloudSdkModule = { pkgs, ... }: {
        environment.systemPackages = [ pkgs.google-cloud-sdk ];
      };
      nixLdModule = {
        programs.nix-ld.enable = true;
      };

      mkHost = { hostname, extraModules ? [ ], extraSpecialArgs ? { } }:
        nixpkgs.lib.nixosSystem {
          specialArgs = extraSpecialArgs;
          modules = [
            { nixpkgs.hostPlatform = system; }
            ./hosts/${hostname}/default.nix
            googleCloudSdkModule
            nixLdModule
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.jay = import ./home/${hostname}.nix;
            }
          ] ++ extraModules;
        };
    in
    {
      nixosConfigurations = {
        nixos-ripper = mkHost { hostname = "nixos-ripper"; };
        framework-13 = mkHost { hostname = "framework-13"; };
        framework-16 = mkHost { hostname = "framework-16"; };
        nixos = mkHost {
          hostname = "nixos";
          extraSpecialArgs = { inherit wallbag-rust; };
          extraModules = [
            kokoro-fastapi-nix.nixosModules.default
            {
              home-manager.backupFileExtension = "backup";
            }
          ];
        };
      };
    };
}
