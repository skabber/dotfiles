{
  description = "Multi-machine NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Pinned so LibreOffice stops rebuilding from source on every --upgrade:
    # it must come from a nixpkgs instance free of the openldap override in
    # modules/common.nix (LibreOffice depends on openldap, and overriding it
    # invalidates the binary cache for both). Bump when you actually want a
    # newer LibreOffice. This instance also pins dwarfs, which is broken on
    # unstable (bundled folly/fbthrift vs current fmt/GCC) — see
    # lib/mkHost.nix. Verify a green hydra window for dwarfs when bumping.
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
    pain = {
      url = "github:skabber/pain";
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
      pain,
      ...
    }:
    let
      system = "x86_64-linux";
      # import (not legacyPackages) so the unfree proton-drive-cli in `packages`
      # evaluates under `nix flake check`; system configs get allowUnfree from
      # modules/common.nix separately.
      pkgs = import nixpkgs { inherit system; config.allowUnfree = true; };

      inherit (import ./lib/mkHost.nix {
        inherit self nixpkgs nixpkgs-libreoffice home-manager system;
      }) mkHost;
    in
    {
      packages.${system} = {
        proton-drive-cli = pkgs.callPackage ./pkgs/proton-drive-cli.nix { };
        default = pkgs.callPackage ./pkgs/proton-drive-cli.nix { };
      };

      nixosConfigurations = {
        nixos-ripper = mkHost {
          hostname = "nixos-ripper";
          extraModules = [
            (_: { environment.systemPackages = [ pain.packages.${system}.default ]; })
          ];
        };
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
