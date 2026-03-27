# ComfyUI Service
# Node-based Stable Diffusion UI with AMD ROCm GPU support
# https://github.com/Comfy-Org/ComfyUI

{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.comfyui;

  pythonEnv = pkgs.python3.withPackages (ps: with ps; [ pip virtualenv ]);

  rocmLibPath = lib.makeLibraryPath [
    pkgs.rocmPackages.clr
    pkgs.rocmPackages.rocm-runtime
    pkgs.rocmPackages.hipblas
    pkgs.stdenv.cc.cc.lib
    pkgs.zstd
    pkgs.zlib
  ];
in
{
  options.comfyui = {
    enable = mkEnableOption "ComfyUI Stable Diffusion node UI";

    port = mkOption {
      type = types.port;
      default = 8188;
      description = "Port for the ComfyUI web interface.";
    };

    listenAddress = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Address to bind the ComfyUI server.";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/comfyui";
      description = "Directory for ComfyUI persistent data (models, outputs, custom nodes).";
    };

    gfxVersion = mkOption {
      type = types.str;
      default = "11.0.0";
      description = "HSA_OVERRIDE_GFX_VERSION for AMD GPU compatibility.";
    };

    extraArgs = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Extra command-line arguments for ComfyUI.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to open the firewall port.";
    };
  };

  config = mkIf cfg.enable {
    # Create persistent directories
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 comfyui comfyui -"
      "d ${cfg.dataDir}/models 0755 comfyui comfyui -"
      "d ${cfg.dataDir}/output 0755 comfyui comfyui -"
      "d ${cfg.dataDir}/input 0755 comfyui comfyui -"
      "d ${cfg.dataDir}/custom_nodes 0755 comfyui comfyui -"
    ];

    users.users.comfyui = {
      isSystemUser = true;
      group = "comfyui";
      home = cfg.dataDir;
    };
    users.groups.comfyui = {};

    # One-shot: clone/update repo, create venv, install deps with ROCm PyTorch
    systemd.services.comfyui-setup = {
      description = "ComfyUI venv setup";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "comfyui";
        Group = "comfyui";
        StateDirectory = "comfyui";
        WorkingDirectory = cfg.dataDir;
        Environment = [
          "HOME=${cfg.dataDir}"
          "HSA_OVERRIDE_GFX_VERSION=${cfg.gfxVersion}"
        ];
        ExecStart = pkgs.writeShellScript "comfyui-setup" ''
          set -e

          REPO="${cfg.dataDir}/ComfyUI"
          VENV="${cfg.dataDir}/venv"

          # Clone or update ComfyUI
          if [ ! -d "$REPO" ]; then
            ${pkgs.git}/bin/git clone https://github.com/Comfy-Org/ComfyUI.git "$REPO"
          else
            cd "$REPO"
            ${pkgs.git}/bin/git fetch origin
            ${pkgs.git}/bin/git reset --hard origin/master
          fi

          # Symlink persistent dirs into the repo
          for dir in models output input custom_nodes; do
            rm -rf "$REPO/$dir"
            ln -sfn "${cfg.dataDir}/$dir" "$REPO/$dir"
          done

          # Create or reuse venv
          if [ ! -d "$VENV" ]; then
            ${pythonEnv}/bin/python -m venv "$VENV"
          fi
          source "$VENV/bin/activate"

          # Install PyTorch with ROCm support
          pip install --quiet \
            torch torchvision torchaudio \
            --index-url https://download.pytorch.org/whl/rocm6.2.4

          # Install ComfyUI requirements
          pip install --quiet -r "$REPO/requirements.txt"
        '';
        TimeoutStartSec = 600;
      };
      path = [ pkgs.git ];
    };

    # Main ComfyUI service
    systemd.services.comfyui = {
      description = "ComfyUI Stable Diffusion Node UI";
      after = [ "network.target" "comfyui-setup.service" ];
      requires = [ "comfyui-setup.service" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        HSA_OVERRIDE_GFX_VERSION = cfg.gfxVersion;
        TORCH_ROCM_AOTRITON_ENABLE_EXPERIMENTAL = "1";
        LD_LIBRARY_PATH = "${rocmLibPath}:/run/opengl-driver/lib";
        HOME = cfg.dataDir;
      };

      serviceConfig = {
        User = "comfyui";
        Group = "comfyui";
        SupplementaryGroups = [ "video" "render" ];
        WorkingDirectory = "${cfg.dataDir}/ComfyUI";
        ExecStart = let
          args = [
            "--listen" cfg.listenAddress
            "--port" (toString cfg.port)
            "--disable-auto-launch"
            "--use-pytorch-cross-attention"
          ] ++ cfg.extraArgs;
        in "${pkgs.writeShellScript "comfyui-run" ''
          export LD_LIBRARY_PATH="${rocmLibPath}:/run/opengl-driver/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
          source ${cfg.dataDir}/venv/bin/activate
          exec python main.py ${lib.concatStringsSep " " args}
        ''}";
        Restart = "on-failure";
        RestartSec = 10;
      };
    };

    # Tailscale Serve: HTTPS proxy for ComfyUI
    systemd.services.tailscale-serve-comfyui = {
      description = "Tailscale Serve for ComfyUI";
      after = [ "tailscaled.service" "comfyui.service" ];
      wants = [ "tailscaled.service" "comfyui.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.tailscale ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStartPre = "${pkgs.bash}/bin/bash -c 'for i in $(seq 1 30); do tailscale status >/dev/null 2>&1 && exit 0; sleep 1; done; exit 1'";
        ExecStart = "${pkgs.tailscale}/bin/tailscale serve --bg --https=${toString cfg.port} http://127.0.0.1:${toString cfg.port}";
        ExecStop = "${pkgs.tailscale}/bin/tailscale serve --https=${toString cfg.port} off";
      };
    };

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];
  };
}
