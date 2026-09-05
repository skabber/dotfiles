# Hyprland Setup Guide

This repo ships a modern Hyprland desktop — Catppuccin Mocha theme, **ghostty** terminal,
**waybar** status bar, **rofi** launcher, **mako** notifications, and **hyprlock** lock
screen. Hyprland is enabled in [`modules/desktop.nix`](../modules/desktop.nix), so every
host that imports that module (nixos-ripper, framework-13, framework-16) gets it.

## Components

| Component | What it does | Source in this repo |
|---|---|---|
| [Hyprland](https://hyprland.org) | Wayland compositor (tiling WM) | `config/hypr/hyprland.lua` |
| [Ghostty](https://ghostty.org) | Terminal emulator | `~/.config/ghostty/config` (local) |
| [Waybar](https://github.com/Alexays/Waybar) | Status bar (top) | `config/waybar/{config.jsonc,style.css}` |
| [Rofi](https://github.com/davatorium/rofi) | App launcher / window switcher | `config/rofi/config.rasi` |
| [Mako](https://github.com/emersion/mako) | Notification daemon | `config/mako/config` |
| [hyprlock](https://github.com/hyprwm/hyprlock) | Lock screen | `config/hypr/hyprlock.conf` |
| [hyprpaper](https://github.com/hyprwm/hyprpaper) | Wallpaper (NixOS "nineish", Catppuccin Mocha) | `home/hyprland.nix` |
| [hypridle](https://github.com/hyprwm/hypridle) | Idle daemon: auto-lock, screens off, suspend | `config/hypr/hypridle.conf` |
| [Satty](https://github.com/gabm/Satty) | Screenshot annotation (arrows, text, blur) | `config/hypr/hyprland.lua` binds |
| [wl-screenrec](https://github.com/Decodetalkers/wl-screenrec) | Screen + audio recording | `config/hypr/hyprland.lua` binds |
| [gpu-screen-recorder](https://git.dec05eba.com/gpu-screen-recorder/about/) | Replay buffer ("save the last 30 s") | `config/hypr/hyprland.lua` binds |
| [cliphist](https://github.com/sentriz/cliphist) | Clipboard history | `config/hypr/hyprland.lua` binds |
| hyprsysteminfo | System info panel | package — run `hyprsysteminfo` |

> **How this is wired (the Nix way):** the config files live in this repo under
> `config/` and [Home Manager](https://nix-community.github.io/home-manager/) ships
> them into `~/.config` as symlinks into the nix store (`home/hyprland.nix`, imported
> by the AMD desktop hosts). After a rebuild, `~/.config/hypr/hyprland.lua` etc. are
> **read-only symlinks** — edit them *here* and rebuild, don't edit `~/.config`
> directly (changes there would be clobbered on the next switch). The *packages*
> come from `modules/desktop.nix`.
>
> Ghostty's config is still a local `~/.config` file; add it to `config/` the same
> way if you want it declarative too.

## Starting Hyprland

1. Rebuild and switch (see [Applying changes](#applying-changes)) at least once so all
   packages are installed.
2. Log out. On the GDM login screen, click your name, then click the **gear icon**
   (bottom-right corner) and pick **Hyprland**.
3. Log in. Waybar, mako, hyprpaper, and the network tray icon start automatically.

The machine still boots into GNOME by default as the other session — switching between
GNOME and Hyprland is just a matter of picking the session at login.

## Quickstart — the 5 keys you need

| Keys | Action |
|---|---|
| `Super+Q` | Open a terminal (ghostty) |
| `Super+R` | App launcher (type to search, Enter to launch) |
| `Super+O` | 1Password Quick Access (search any password) |
| `Super+C` | Close the focused window |
| `Super+1…9,0` | Switch to workspace 1–10 |
| `Super+L` | Lock the screen |

`Super` is the **Windows key**. Everything else builds on this.

## Daily usage

### Windows

Hyprland tiles windows automatically: each new window splits the screen (dwindle
layout). The basics:

- **Move focus** — `Super+←/→/↑/↓` (or just move the mouse; focus follows it)
- **Move a window** — hold `Super` and drag it with the mouse, or `Super+Shift+<number>`
  to send it to another workspace
- **Resize** — hold `Super` and drag with the right mouse button, or drag window borders
  (`resize_on_border` is on)
- **Float a window** — `Super+V` toggles floating/tiled
- **Swap the split** — `Super+J` flips the orientation after a split
- **Full screen** — `Super+F` toggles the focused window between tiled and fullscreen
- **Scratchpad** — `Super+S` shows/hides a hidden workspace (drop windows in with
  `Super+Shift+S`); great for a music player or a quick notes window
- **Tab groups** — `Super+G` tabs the focused window into a group (a slim tab bar
  appears at the top). `Super+Ctrl+←/→` flips through the tabs, `Super+Shift+G`
  pulls the focused tab back out, `Super+Ctrl+G` locks the group's membership.
  Great for stacking terminals or reference docs
- **Adjust mode** — `Super+A` enters a modal key mode: arrows resize the focused
  window, `Shift+arrows` move it, `Esc`/`Enter` leave the mode. No modifier
  gymnastics needed
- **Magnifier** — `Super+Z` / `Super+Shift+Z` zoom the screen in/out around the
  cursor (up to 5×, smoothly animated); zooming back to 1× turns it off. Handy
  for tiny text on the 13" panel
- **Mark & jump** — `Super+Shift+T` tags the focused window `marked`, `Super+T`
  jumps straight back to it from anywhere. (Tags are Hyprland's per-window
  labels — window rules can also match on them)
- **Floating snap** — floated windows magnetically snap to screen edges, the
  gaps, and other windows while dragging
- **Scrolling layout** — `Super+Y` flips between dwindle (binary splits) and the
  built-in scrolling layout (PaperWM-style horizontal columns). Press it again
  to go back; windows stay put

### Workspaces

- `Super+1` … `Super+9`, `Super+0` — switch to workspace 1–10
- `Super+Shift+1…0` — carry the focused window to that workspace
- `Super+mouse wheel` — cycle through workspaces
- 3-finger horizontal swipe on the touchpad — switch workspaces (works on the
  Framework laptops' touchpads)
- Workspaces are per-monitor on multi-display setups

> Heads-up: Hyprland 0.56 (what we run) has no built-in overview dispatcher yet —
> `Super+Tab` (window switcher) plus the scrolling layout are the closest things
> for now. Watch for it in newer releases.

### The launcher (rofi)

| Keys | Mode | What it's for |
|---|---|---|
| `Super+R` | Apps (drun) | Launch installed applications — fuzzy search |
| `Super+Shift+R` | Run | Run a command, like a shell prompt |
| `Super+Tab` | Window | Switch between open windows by title |
| `Super+Shift+V` | Clipboard | Search everything you've copied; `Enter` copies it back |

Type to fuzzy-search, `Enter` to confirm, `Esc` to dismiss, arrow keys to move through
results. Waybar's Nix logo (left corner) also opens the app launcher on click.

The clipboard mode is [cliphist](https://github.com/sentriz/cliphist), fed by a
`wl-paste --watch` watcher that starts with the session. Clear the history with
`cliphist wipe` (e.g. after copying a password).

### The status bar (waybar)

Left to right: **launcher** · **workspaces** (highlighted = current, click to switch) ·
**focused window title** | **clock** (click to toggle time/date, right-click for the
calendar tooltip) | **CPU** · **RAM** · **network** · **volume** · **tray**.

- Click the volume pill → pavucontrol; right-click → mute
- Scroll the volume pill → adjust volume
- Tray icons (network, applets) appear on the right

### Screenshots

| Keys | Action |
|---|---|
| `Print` | Full screen → file in `~/Pictures/Screenshots/` |
| `Super+Print` | Draw a region with the mouse → file |
| `Alt+Print` | Draw a region → clipboard (paste with the app's paste key, or `wl-paste`) |
| `Super+Ctrl+P` | Full screen → file — for keyboards without a `Print` key |
| `Super+Shift+P` | Draw a region → file — for keyboards without a `Print` key |
| `Super+Alt+P` | Draw a region → clipboard — for keyboards without a `Print` key |
| `Ctrl+Print` / `Ctrl+Alt+P` | Draw a region → **Satty** to annotate, then save/copy |

Each plain screenshot fires a mako notification confirming where it went.

The Satty bind drops the region into an editor: arrows, text, rectangles,
blur/highlight, cropping. `Ctrl+S` saves to `~/Pictures/Screenshots/annotated-*`,
`Ctrl+C` copies to the clipboard, `Esc` discards. (`Ctrl+Alt+P` is the variant
for keyboards without a `Print` key.)

### Recording

| Keys | Action |
|---|---|
| `Shift+Print` / `Shift+Alt+P` | Record a region + system audio (wl-screenrec) → `~/Videos/` |
| `Ctrl+Shift+Print` / `Ctrl+Shift+Alt+P` | Stop recording and save |
| `Super+F11` | Toggle the replay daemon — keeps the last 30 s in memory |
| `Super+F12` | Write the last 30 s to `~/Videos/Replays/` |

The replay buffer is `gpu-screen-recorder`: it encodes on the GPU and only
touches disk when you press `Super+F12`, so you can leave it running during a
game and save the highlight after the fact. Check it's running with
`pgrep -a gpu-screen-recorder`.

### Screen sharing in calls

The NixOS Hyprland module ships hyprwm's own portal (`xdg-desktop-portal-hyprland`),
so Firefox/Chromium/Zoom screen sharing works out of the box — pick a monitor or
window in the portal picker. If a call app offers "entire screen" only, picking
the specific monitor usually behaves better.

### Notifications (mako)

Notifications stack in the top-right corner and auto-dismiss after 5 s
(critical ones stay until dismissed). Manage them from a terminal:

```bash
makoctl dismiss          # dismiss the newest
makoctl restore          # bring the last one back
makoctl dismiss -a       # dismiss all
makoctl list             # see history
```

### Passwords (1Password)

1Password starts silently with the session (tray icon, right side of the bar) and takes
care of three auth flows:

- **Quick Access** — `Super+O` opens a rofi-style search over everything in your
  vault: passwords, TOTP codes, SSH keys. Enter copies, and the browser extension
  or `op` CLI handle autofill/authentication.
- **SSH agent** — `ssh` and `git` already point at 1Password's agent socket
  (`~/.1password/agent.sock`, wired in `home/common.nix`), so `git push`, ssh logins
  and commit signing (your gitconfig signs with SSH) pop the 1Password prompt
  instead of asking for a key passphrase. Enable it once in the app:
  **1Password → Settings → Developer → Use the SSH agent**. Check with
  `ssh-add -l` (lists `1Password` as the agent comment).
- **System (polkit) prompts** — Hyprland has no built-in authentication agent, so
  when a GUI tool asks for admin rights (GParted, system updates, etc.) 1Password
  serves the prompt — this is what `polkitPolicyOwners = [ "jay" ]` in
  `modules/common.nix` grants. If you quit 1Password entirely, those prompts have
  no agent until it's running again.

`op` (the 1Password CLI) is installed on every host; with **Integrate with 1Password
CLI** enabled in the app's Developer settings, `op` unlocks biometrically through the
same session link.

### Locking

`Super+L` locks with hyprlock: the screen blurs, a clock appears, and your password +
YubiKey unlock it. `Super+M` exits the whole Hyprland session back to GDM.

hypridle backs that up when you walk away: after 5 idle minutes the session locks
itself, after 6 the screens switch off (`config/hypr/hypridle.conf`; uncomment the
suspend listener there on the laptops). Test without waiting:
`hyprctl dispatch forceidle 5`.

## Full keybinding reference

| Keys | Action |
|---|---|
| `Super+Q` | Terminal (ghostty) |
| `Super+E` | File manager (nautilus) |
| `Super+R` | App launcher |
| `Super+Shift+R` | Command runner |
| `Super+Tab` | Window switcher |
| `Super+C` | Close window |
| `Super+V` | Toggle float |
| `Super+P` | Toggle pseudo-tiling |
| `Super+J` | Toggle split orientation |
| `Super+F` | Toggle fullscreen |
| `Super+L` | Lock screen |
| `Super+M` | Exit Hyprland |
| `Super+←/→/↑/↓` | Move focus |
| `Super+1…0` | Switch workspace |
| `Super+Shift+1…0` | Move window to workspace |
| `Super+S` / `Super+Shift+S` | Toggle scratchpad / move window to it |
| `Super+mouse wheel` | Cycle workspaces |
| 3-finger horizontal swipe | Switch workspace (touchpad) |
| `Super+Y` | Toggle dwindle ↔ scrolling layout |
| `Super+G` | Toggle window group (tabs) |
| `Super+Ctrl+←/→` | Previous/next tab in group |
| `Super+Ctrl+G` | Lock/unlock the active group |
| `Super+Shift+G` | Move window out of its group |
| `Super+A` | Adjust mode: arrows resize, `Shift+arrows` move, `Esc`/`Enter` exits |
| `Super+Z` / `Super+Shift+Z` | Magnifier zoom in / out |
| `Super+T` / `Super+Shift+T` | Jump to / toggle `marked` tag on focused window |
| `Super+Shift+V` | Clipboard history (rofi) |
| `Super+O` | 1Password Quick Access |
| `Super+drag LMB` / `Super+drag RMB` | Move / resize window |
| `Print` / `Super+Print` / `Alt+Print` | Screenshot: full / region→file / region→clipboard |
| `Ctrl+Print` | Region → Satty annotator |
| `Super+Ctrl+P` / `Super+Shift+P` / `Super+Alt+P` | Screenshot (no `Print` key): full / region→file / region→clipboard |
| `Ctrl+Alt+P` | Region → Satty (no `Print` key) |
| `Shift+Print` / `Ctrl+Shift+Print` | Start / stop region recording with audio (`Shift+Alt+P` / `Ctrl+Shift+Alt+P` without a `Print` key) |
| `Super+F11` / `Super+F12` | Toggle replay daemon / save last 30 s to `~/Videos/Replays/` |
| `XF86Audio*` keys | Volume, mic mute, media (playerctl) |
| `XF86MonBrightness*` keys | Brightness |

## Customizing

All edits below go in `config/hypr/hyprland.lua` (then rebuild + `hyprctl reload`).
The config is [Lua](https://wiki.hypr.land/Configuring/Start/) — this Hyprland version
reads the `.lua` file, not `hyprland.conf`.

### Change the accent colors

The active window border is a mauve→blue gradient. Swap in any two colors (look in the
`general` section):

```lua
col = {
    active_border   = { colors = { "rgba(cba6f7ee)", "rgba(89b4faee)" }, angle = 135 },
    inactive_border = "rgba(585b70aa)",
},
```

Waybar/rofi/mako use CSS-level `@define-color` / rasi variables with the same palette
(the Catppuccin Mocha names: `mauve`, `blue`, `lavender`, `green`, `red`, `yellow`…).
Change them once in each file to retheme everything.

### Add a keybinding

Bindings follow `hl.bind("<keys>", <action>)`. Some examples:

```lua
-- Launch something
hl.bind("SUPER + B", hl.dsp.exec_cmd("firefox"))

-- Launch with a shell pipeline
hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd("grim - | wl-copy"))

-- A dispatcher action (see the Hyprland wiki "Dispatchers" page)
hl.bind("SUPER + SHIFT + F", hl.dsp.window.fullscreen())
```

### Change gaps, rounding, blur

All in the `look and feel` section of `hyprland.lua`:

```lua
general   = { gaps_in = 6, gaps_out = 14, border_size = 2 },
decoration = { rounding = 12, blur = { size = 6, passes = 3 } },
```

### Autostart apps

Edit the startup hook near the top of `config/hypr/hyprland.lua`:

```lua
hl.on("hyprland.start", function()
    hl.exec_cmd("waybar")
    hl.exec_cmd("mako")
    hl.exec_cmd("nm-applet --indicator")
    -- hl.exec_cmd("firefox")          -- add anything you want
end)
```

### Float / pin specific apps

Window rules already float `pavucontrol` and `nm-connection-editor`. Add your own:

```lua
hl.window_rule({
    name  = "float-spotify",
    match = { class = "^Spotify$" },
    float = true,
})
```

Find a window's class with `hyprctl clients` while the app is open (look for `class:`).

## Applying changes

| What changed | How to apply |
|---|---|
| Anything in `config/` (hyprland.lua, waybar, rofi, mako, hyprlock) | `./scripts/rebuild.sh` (ships new symlinks), then: |
| — `config/hypr/hyprland.lua` | …then `hyprctl reload` (no re-login needed) |
| — `config/waybar/*` | …then `pkill waybar && waybar &` |
| — `config/rofi/*` | nothing — rofi reads it on every launch |
| — `config/mako/config` | …then `makoctl reload` |
| — `config/hypr/hyprlock.conf` | nothing — read at next lock |
| — `config/hypr/hypridle.conf` | …then `pkill hypridle && hypridle &` |
| — hyprpaper.conf (generated in `home/hyprland.nix`) | `pkill hyprpaper && hyprpaper &` (or just log back in) |
| Anything under `modules/` or `home/` in this repo | `./scripts/rebuild.sh` (or `sudo nixos-rebuild switch --flake .#<host>`) |

> Fast loop while tinkering: `./scripts/rebuild.sh` only rebuilds what changed — the
> config files are tiny, so a rebuild after editing `config/` takes seconds.

## Troubleshooting

**A config edit didn't take effect** — remember `~/.config` files are store symlinks;
edit the repo copies under `config/`, rebuild, then `hyprctl reload`. If you broke the
Lua syntax, Hyprland logs the error; check `journalctl --user -b` (the session runs
under UWSM, so errors also land in `~/.local/state/hypr/` or the journal) and re-edit.
Syntax-check the source file outside a session with any Lua interpreter (the `hl.*`
API gets stubbed out):

```bash
nix shell nixpkgs#luajit -c luajit -e 'local mt;mt={__index=function(t,k)local v=setmetatable({},mt);rawset(t,k,v);return v end,__call=function(f,...)return setmetatable({},mt) end};hl=setmetatable({},mt);dofile("config/hypr/hyprland.lua");print("OK")'
```

(run from the repo root; prints `OK` if the config parses — an error + line number
otherwise)

**Waybar is missing / duplicated** — it's started by the `hyprland.start` hook; if you
experiment manually, `pkill waybar` first, then relaunch from a terminal to see errors.

**No sound / volume key does nothing** — PipeWire is enabled system-wide; check
`wpctl status` and pick a default sink in pavucontrol (Waybar volume pill).

**Screenshots are black under apps like games** — normal for Wayland screencopy with
protected content; region screenshots still work.

**gnome apps look wrong under Hyprland** — GNOME apps still run fine; they just use the
GTK theme set by dconf. `gsettings set org.gnome.desktop.interface color-scheme
'prefer-dark'` gives a dark theme that matches.

**Where do logs live?** — `journalctl --user -b /usr/bin/Hyprland` (session),
`journalctl --user -b -u waybar` etc. for autostarted tools.

## Adding Hyprland to another host

It's already available everywhere `modules/desktop.nix` is imported — the host also
needs `./hyprland.nix` imported from its `home/<host>.nix` (nixos-ripper,
framework-13, and framework-16 all have it). For the NVIDIA host (`nixos`), you'd
want a `desktop-nvidia.nix` variant — see the Hyprland wiki section on
NVIDIA before trying it there.
