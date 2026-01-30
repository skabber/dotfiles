{
  pkgs,
  secrets,
  ...
}:
{

## One time I needed to run a re-sync
##I ran:
#sudo -u MYUERNAME rclone bisync PROTON_FOLDER_LOCATION remote:/ --config=/var/lib/rclone-protondrive/rclone.conf --resync --protondrive-replace-existing-draft=true

  ## Create drive mount
  systemd.tmpfiles.rules = [ "d /mnt/protondrive 0755 root root" ];
  ## Add in rclone config
  ## pass is from rclone obscure 'PASSWORDHERE'
  environment.etc."rclone-proton.conf".text = ''
    [remote]
    type = protondrive
    username = ${secrets.proton.email}
    password = ${secrets.proton.pass}  
  '';

  # Mount proton drive to /mnt/protondrive
  systemd.services.rclone-protondrive-mount = {
    description = "Mount Proton Drive using rclone";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "simple";
      Restart = "on-failure";
      RestartSec = "15s";

      StateDirectory = "rclone-USER"; # Change to rclone-YOURUSER for perms?

      ExecStartPre = ''
        /bin/sh -c 'if [ ! -f "/var/lib/rclone-protondrive/rclone.conf" ]; then ${pkgs.coreutils}/bin/cp /etc/rclone-proton.conf /var/lib/rclone-protondrive/rclone.conf; fi'
      '';

      ExecStart = ''
        ${pkgs.rclone}/bin/rclone mount \
          --config=/var/lib/rclone-protondrive/rclone.conf \
          --allow-other \
          --vfs-cache-mode full \
          remote:/ /mnt/protondrive
      '';

      ExecStop = "${pkgs.fuse}/bin/fusermount -u /mnt/protondrive";
    };

    wantedBy = [ "multi-user.target" ];
  };

  # Mount /mnt/protondrive to documents
  systemd.services.proton-bisync = {
    description = "Bidirectional sync between local directory and Proton Drive";
    after = [
      "network-online.target"
      # If VPN, add here
      "rclone-protondrive-mount.service"
    ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "USER";

      ExecStart = ''
        ${pkgs.rclone}/bin/rclone bisync ${secrets.proton.file_location} remote:/ \
          --config=/var/lib/rclone-protondrive/rclone.conf
      '';
    };
  };
  # Push every time file change
  systemd.paths.proton-bisync-push = {
    description = "Watch for changes in SyncDoc directory";
    pathConfig = {
      PathChanged = "${secrets.proton.file_location}";
      Unit = "proton-bisync.service";
    };
    wantedBy = [ "multi-user.target" ];
  };
  ## Pull every 30min
  systemd.timers.proton-bisync-pull = {
    description = "Timer for Proton Drive bidirectional sync";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "30min";
      Unit = "proton-bisync.service";
    };
  };
}
