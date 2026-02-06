{
  description = "Multi-machine NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-openclaw = {
      url = "git+https://nixos.tail69fe1.ts.net:3000/skabber/nix-openclaw.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, nix-openclaw, ... }: {
    nixosConfigurations = {
      nixos-ripper = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./hosts/nixos-ripper/default.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.jay = import ./home/nixos-ripper.nix;
          }
        ];
      };

      nixos = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./hosts/nixos/default.nix
          home-manager.nixosModules.home-manager
          {
            nixpkgs.overlays = [ nix-openclaw.overlays.default ];
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.jay = { ... }: {
              imports = [
                ./home/nixos.nix
                nix-openclaw.homeManagerModules.openclaw
              ];
            };
          }
        ];
      };

      framework-13 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./hosts/framework-13/default.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.jay = import ./home/framework-13.nix;
          }
        ];
      };

      framework-16 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./hosts/framework-16/default.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.jay = import ./home/framework-16.nix;
          }
        ];
      };
    };
  };
}
