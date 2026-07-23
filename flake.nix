{
  description = "Multi-machine NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Pinned so LibreOffice stops rebuilding from source on every --upgrade:
    # it must come from a nixpkgs instance free of the openldap override in
    # modules/common.nix (LibreOffice depends on openldap, and overriding it
    # invalidates the binary cache for both). Bump when you actually want a
    # newer LibreOffice.
    nixpkgs-libreoffice.url = "github:NixOS/nixpkgs/b5aa0fbd538984f6e3d201be0005b4463d8b09f8";
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
    gtk-flash = {
      url = "git+https://nixos.tail69fe1.ts.net:3000/skabber/gtk-flash.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-libreoffice,
      home-manager,
      kokoro-fastapi-nix,
      wallbag-rust,
      gtk-flash,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      libreofficeOverlay = _final: _prev: {
        libreoffice = nixpkgs-libreoffice.legacyPackages.${system}.libreoffice;
      };

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
            { nixpkgs.overlays = [ libreofficeOverlay ]; }
            ./hosts/${hostname}/default.nix
            googleCloudSdkModule
            nixLdModule
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "backup";
              home-manager.users.jay = import ./home/${hostname}.nix;
            }
          ] ++ extraModules;
        };
    in
    {
      packages.${system} = {
        proton-drive-cli = pkgs.callPackage ./pkgs/proton-drive-cli.nix { };
        default = pkgs.callPackage ./pkgs/proton-drive-cli.nix { };
      };

      nixosConfigurations = {
        nixos-ripper = mkHost { hostname = "nixos-ripper"; };
        framework-13 = mkHost {
          hostname = "framework-13";
          extraModules = [
            gtk-flash.nixosModules.default
          ];
        };
        framework-16 = mkHost { hostname = "framework-16"; };
        nixos = mkHost {
          hostname = "nixos";
          extraSpecialArgs = { inherit wallbag-rust; };
          extraModules = [
            kokoro-fastapi-nix.nixosModules.default
          ];
        };
      };
    };
}
