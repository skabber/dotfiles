# Obsidian vault git sync.
#
# Keeps local vaults mirrored to private git remotes (GitHub), which remote
# consumers (e.g. the IronClaw agent workspace) clone and pull/push through.
# Each vault gets a oneshot service + persistent timer: commit local changes,
# rebase onto origin/main (autostash), push. The 346MB smart-second-brain
# vectorstore and per-device Obsidian state are gitignored, not synced.

{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.vault-sync;

  syncScript = pkgs.writeShellScript "vault-sync" ''
    set -euo pipefail
    name="$1"
    path="$2"
    remote="$3"

    cd "$path"

    if [ ! -d .git ]; then
      git init -b main
    fi

    if ! git check-ignore -q .obsidian/workspace.json 2>/dev/null; then
      printf '%s\n' \
        '.obsidian/workspace.json' \
        '.obsidian/workspace-mobile.json' \
        '.obsidian/plugins/smart-second-brain/vectorstores/' \
        '.trash/' \
        '.DS_Store' \
        >> .gitignore
    fi

    if ! git remote get-url origin >/dev/null 2>&1; then
      git remote add origin "$remote"
    fi

    git add -A
    git -c commit.gpgsign=false commit -m "vault-sync: $name $(date --utc +'%Y-%m-%dT%H:%M:%SZ')" || true

    if ! git fetch origin; then
      echo "vault-sync: cannot reach $remote yet, will retry on next timer run" >&2
      exit 0
    fi

    if git rev-parse --verify origin/main >/dev/null 2>&1; then
      if ! git -c rebase.autoStash=true rebase origin/main; then
        git rebase --abort || true
        echo "vault-sync: rebase conflict in $name, manual resolution required" >&2
        exit 1
      fi
    fi

    git push -u origin main
  '';
in
{
  options.vault-sync = {
    enable = mkEnableOption "Obsidian vault git sync";

    user = mkOption {
      type = types.str;
      default = "jay";
      description = "User owning the vaults (needs SSH access to the remote).";
    };

    interval = mkOption {
      type = types.str;
      default = "*:0/10";
      description = "systemd OnCalendar expression between sync runs.";
    };

    vaults = mkOption {
      type = types.listOf (types.submodule {
        options = {
          name = mkOption {
            type = types.str;
            description = "Instance name used in unit names and commit messages.";
          };
          path = mkOption {
            type = types.str;
            description = "Vault directory to sync.";
          };
          remote = mkOption {
            type = types.str;
            description = "git remote URL to sync with.";
          };
        };
      });
      default = [ ];
      description = "Vaults to keep in sync.";
    };
  };

  config = mkIf cfg.enable {
    systemd.services = listToAttrs (flip map cfg.vaults (v: {
      name = "vault-sync-${v.name}";
      value = {
        description = "Git sync for Obsidian vault ${v.name}";
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          User = cfg.user;
          Environment = "HOME=/home/${cfg.user}";
        };
        path = [
          pkgs.git
          pkgs.openssh
          pkgs.coreutils
          pkgs.gnugrep
        ];
        script = ''
          exec ${syncScript} ${escapeShellArg v.name} ${escapeShellArg v.path} ${escapeShellArg v.remote}
        '';
      };
    }));

    systemd.timers = listToAttrs (flip map cfg.vaults (v: {
      name = "vault-sync-${v.name}";
      value = {
        description = "Periodic git sync for Obsidian vault ${v.name}";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.interval;
          Persistent = true;
        };
      };
    }));
  };
}
