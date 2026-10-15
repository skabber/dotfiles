# IronClaw Obsidian Vault Sync

Git hub-and-spoke sync between the local Obsidian vaults on `nixos-ripper`
and the IronClaw agent workspace, with the self-hosted Gitea on `nixos` as
the hub. The IronClaw sandbox only exposes files at the scoped `/workspace`
mount (real host path is redacted), so the sync runs entirely through git
remotes both sides can reach.

```
nixos-ripper                            Gitea (nixos)                        IronClaw /workspace
vault-sync-skabber.timer    ──push──▶  skabber/vault-skabber       ──pull/push──▶  obsidian-vaults/Skabber
vault-sync-stablekernel.timer ─push─▶  skabber/vault-stablekernel  ──pull/push──▶  obsidian-vaults/StableKernel
       ▲________ pull --rebase --autostash every 10 min (over tailnet SSH) ________|
```

- Local side pushes via SSH (`git@nixos.tail69fe1.ts.net`, key
  `~/.ssh/id_ed25519`, registered in Gitea) — reachable on the tailnet.
- IronClaw side reaches Gitea over the public internet via Tailscale Funnel:
  `https://nixos.tail69fe1.ts.net:8443` → `127.0.0.1:3000`.

## Local side (NixOS)

- Module: `modules/services/vault-sync.nix`, enabled in
  `hosts/nixos-ripper/default.nix` with both vaults (Gitea SSH remotes).
- Each vault gets `vault-sync-<name>.service` + `.timer` (default every
  10 min, `Persistent = true`): commit local changes, rebase onto
  `origin/main`, push.
- Excluded via per-vault `.gitignore`: `smart-second-brain` vectorstores
  (346 MB model), per-device Obsidian workspace state, `.trash/`.
- Logs: `journalctl -u vault-sync-skabber.service -f`

## Funnel exposure (nixos host)

The funnel is runtime state in tailscaled (like all `tailscale serve`
entries). To (re-)enable after `funnel reset` or tailscaled restarts:

```bash
tailscale funnel --bg --https=8443 http://127.0.0.1:3000
```

To disable: `tailscale funnel reset` (WARNING: as of tailscale 1.102 this
clears ALL serve config — re-add from `tailscale serve status` output; the
off subcommand errors with "handler does not exist"). Verify exposure only
from an external vantage (e.g. `curl "https://api.allorigins.win/raw?url=https%3A%2F%2Fnixos.tail69fe1.ts.net%3A8443%2Fapi%2Fv1%2Fversion"`)
— a tailnet machine can reach the backend directly regardless.

Registration MUST stay disabled while funnel is on (enforced in
`hosts/nixos/default.nix`: `services.gitea.settings.service.DISABLE_REGISTRATION = true`).
Vault repos are private — anonymous clones get 404.

## One-time IronClaw setup

1. Create a Gitea token for the agent: Gitea → Settings → Applications →
   Generate New Token, scope `write:repository`, name e.g. `ironclaw-vault-sync`.

2. Paste this to the IronClaw agent (replace `<TOKEN>`):

```bash
mkdir -p /workspace/obsidian-vaults && cd /workspace/obsidian-vaults
git clone https://skabber:<TOKEN>@nixos.tail69fe1.ts.net:8443/skabber/vault-skabber.git Skabber
git clone https://skabber:<TOKEN>@nixos.tail69fe1.ts.net:8443/skabber/vault-stablekernel.git StableKernel

cat > sync.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
for d in /workspace/obsidian-vaults/Skabber /workspace/obsidian-vaults/StableKernel; do
  git -C "$d" pull --rebase --autostash
  git -C "$d" add -A
  git -C "$d" -c user.name="IronClaw" -c user.email="ironclaw@skabber.com" \
    -c commit.gpgsign=false commit -m "ironclaw: sync $(date -u +%FT%TZ)" || true
  git -C "$d" push
done
EOF
chmod +x sync.sh
```

## Agent workflow

- Before working on notes: `/workspace/obsidian-vaults/sync.sh` (or at least
  `git -C <vault> pull --rebase --autostash` in each vault).
- After editing: `sync.sh` again — it pulls, commits, and pushes both vaults.
- The local timer picks the changes up within ~10 minutes.

## Conflicts

If the same note is edited on both sides between syncs, the rebase stops.
The local service auto-aborts and retries (check `journalctl -u
vault-sync-*`); resolve manually in the affected vault: `git status`,
edit the conflict markers, `git rebase --continue`, `git push`.

## Notes

- Local remotes: SSH via host sshd on nixos (port 22, tailnet); IronClaw
  uses token-embedded HTTPS via the funnel URL — the token lives only in
  the tenant's `.git/config`.
- GitHub mirrors `skabber/vault-skabber` and `skabber/vault-stablekernel`
  were used briefly before the move to Gitea — delete them if still present.
