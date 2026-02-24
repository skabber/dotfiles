{
  description = "Multi-machine NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # nix-openclaw = {
    #   url = "git+http://127.0.0.1:3000/skabber/nix-openclaw.git";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
  };

  outputs = { self, nixpkgs, home-manager, ... }: let
    system = "x86_64-linux";
  in {
    devShells.${system}.whisperx = let
      pkgs = import nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
          cudaSupport = true;
        };
      };
    in pkgs.mkShell {
      packages = with pkgs; [
        (python3.withPackages (ps: with ps; [
          pip
          virtualenv
        ]))
        cudaPackages.cudatoolkit
        cudaPackages.cudnn
        ffmpeg
        sox
        git
      ];

      shellHook = ''
        export LD_LIBRARY_PATH=${pkgs.lib.makeLibraryPath [
          pkgs.cudaPackages.cudatoolkit
          pkgs.cudaPackages.cudnn
          pkgs.stdenv.cc.cc.lib
        ]}:/run/opengl-driver/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
        export CUDA_PATH=${pkgs.cudaPackages.cudatoolkit}

        if [ ! -d .venv ]; then
          echo "Creating Python venv..."
          python -m venv .venv
        fi
        source .venv/bin/activate
        echo "WhisperX dev shell ready. Run: pip install whisperx"
      '';
    };

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
            # nixpkgs.overlays = [ nix-openclaw.overlays.default ];
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "backup";
            # home-manager.sharedModules = [ nix-openclaw.homeManagerModules.openclaw ];
            home-manager.users.jay = import ./home/nixos.nix;
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
