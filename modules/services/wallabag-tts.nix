# Wallabag TTS Service
# Converts Wallabag articles to podcast episodes via TTS (standalone axum server)

{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.wallabag-tts;

  wallabag-tts-pkg = pkgs.rustPlatform.buildRustPackage {
    pname = "wallabag-tts-server";
    version = "0.1.0";
    src = cfg.sourceDir;

    cargoLock.lockFile = "${cfg.sourceDir}/Cargo.lock";

    buildNoDefaultFeatures = true;
    buildFeatures = [ "standalone" ];

    nativeBuildInputs = [ pkgs.pkg-config ];
    buildInputs = [ pkgs.openssl ];
  };
in
{
  options.wallabag-tts = {
    enable = mkEnableOption "Wallabag TTS podcast service";

    sourceDir = mkOption {
      type = types.path;
      default = /home/jay/Projects/wallbag-rust;
      description = "Path to the wallbag-rust source directory.";
    };

    port = mkOption {
      type = types.port;
      default = 3001;
      description = "Port for the HTTP server.";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/wallabag-tts";
      description = "Directory for audio files and episode metadata.";
    };

    environmentFile = mkOption {
      type = types.path;
      description = "Path to environment file with secrets (WALLABAG_*, TTS_API_KEY, etc).";
    };

    ttsApiUrl = mkOption {
      type = types.str;
      default = "https://nixos.tail69fe1.ts.net:8880/v1/audio/speech";
      description = "TTS API endpoint URL.";
    };

    ttsModel = mkOption {
      type = types.str;
      default = "kokoro";
      description = "TTS model name.";
    };

    ttsVoice = mkOption {
      type = types.str;
      default = "af_heart";
      description = "TTS voice name.";
    };

    podcastTitle = mkOption {
      type = types.str;
      default = "Wallabag Articles";
      description = "RSS feed title.";
    };

    podcastDescription = mkOption {
      type = types.str;
      default = "Articles from Wallabag, read aloud";
      description = "RSS feed description.";
    };

    podcastBaseUrl = mkOption {
      type = types.str;
      default = "http://localhost:3001";
      description = "Public base URL for audio file links in the feed.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to open the firewall port.";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.wallabag-tts = {
      description = "Wallabag TTS Podcast Service";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        LISTEN_ADDR = "0.0.0.0:${toString cfg.port}";
        DATA_DIR = cfg.dataDir;
        TTS_API_URL = cfg.ttsApiUrl;
        TTS_MODEL = cfg.ttsModel;
        TTS_VOICE = cfg.ttsVoice;
        PODCAST_TITLE = cfg.podcastTitle;
        PODCAST_DESCRIPTION = cfg.podcastDescription;
        PODCAST_BASE_URL = cfg.podcastBaseUrl;
      };

      serviceConfig = {
        Type = "exec";
        ExecStart = "${wallabag-tts-pkg}/bin/wallabag-tts-server";
        EnvironmentFile = cfg.environmentFile;
        StateDirectory = "wallabag-tts";
        WorkingDirectory = cfg.dataDir;
        DynamicUser = true;
        Restart = "on-failure";
        RestartSec = 10;

        # Hardening
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ cfg.dataDir ];
        PrivateTmp = true;
      };
    };

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];
  };
}
