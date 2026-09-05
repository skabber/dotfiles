-- ──────────────────────────────────────────────────────────────
-- Hyprland — modern setup · Catppuccin Mocha
-- Terminal: ghostty · Bar: waybar · Launcher: rofi
-- ──────────────────────────────────────────────────────────────

------------------
---- MONITORS ----
------------------

-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = "auto",
})

---------------------
---- MY PROGRAMS ----
---------------------

local terminal    = "ghostty"
local fileManager = "nautilus"
local menu        = "rofi -show drun"
local windowMenu  = "rofi -show window"
local lockCmd     = "hyprlock"

-------------------
---- AUTOSTART ----
-------------------

hl.on("hyprland.start", function()
    hl.exec_cmd("waybar")                      -- status bar
    hl.exec_cmd("mako")                        -- notifications
    hl.exec_cmd("nm-applet --indicator")       -- network tray icon
    hl.exec_cmd("hyprpaper")                   -- wallpaper
    hl.exec_cmd("hypridle")                    -- idle: auto-lock + screen off
    hl.exec_cmd("wl-paste --type text --watch cliphist store")  -- clipboard history
    hl.exec_cmd("1password --silent")           -- 1Password: tray, Quick Access, SSH agent, polkit agent
end)

-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

-----------------------
---- LOOK AND FEEL ----
-----------------------

hl.config({
    general = {
        gaps_in  = 6,
        gaps_out = 14,

        border_size = 2,

        -- Catppuccin Mocha: mauve -> blue gradient
        col = {
            active_border   = { colors = { "rgba(cba6f7ee)", "rgba(89b4faee)" }, angle = 135 },
            inactive_border = "rgba(585b70aa)",
        },

        resize_on_border = true,
        allow_tearing    = true,    -- only applies to fullscreen apps that request it (games)

        -- magnet-snap floating windows to edges and gaps
        snap = {
            enabled      = true,
            respect_gaps = true,
            window_gap   = 8,
            monitor_gap  = 8,
        },

        layout = "dwindle",
    },

    decoration = {
        rounding       = 12,
        rounding_power = 2,

        active_opacity   = 1.0,
        inactive_opacity = 0.94,

        shadow = {
            enabled      = true,
            range        = 12,
            render_power = 3,
            color        = 0xcc1a1a2e,
        },

        blur = {
            enabled  = true,
            size     = 6,
            passes   = 3,
            vibrancy = 0.17,
        },
    },

    animations = { enabled = true },
})

-- Curves and per-behaviour animations
hl.curve("easeOutQuint",   { type = "bezier", points = { {0.23, 1},    {0.32, 1} } })
hl.curve("easeInOutCubic", { type = "bezier", points = { {0.65, 0.05}, {0.36, 1} } })
hl.curve("linear",         { type = "bezier", points = { {0, 0},       {1, 1}    } })
hl.curve("almostLinear",   { type = "bezier", points = { {0.5, 0.5},   {0.75, 1} } })
hl.curve("quick",          { type = "bezier", points = { {0.15, 0},    {0.1, 1}  } })
hl.curve("easy",           { type = "spring", mass = 1, stiffness = 238.1191, dampening = 24.21279333 })

hl.animation({ leaf = "global",        enabled = true,  speed = 10,   bezier = "default" })
hl.animation({ leaf = "border",        enabled = true,  speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows",       enabled = true,  speed = 4.79, spring = "easy" })
hl.animation({ leaf = "windowsIn",     enabled = true,  speed = 4.1,  spring = "easy",   style = "popin 87%" })
hl.animation({ leaf = "windowsOut",    enabled = true,  speed = 1.49, bezier = "linear", style = "popin 87%" })
hl.animation({ leaf = "fadeIn",        enabled = true,  speed = 1.73, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut",       enabled = true,  speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "fade",          enabled = true,  speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "layers",        enabled = true,  speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn",      enabled = true,  speed = 4,    bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut",     enabled = true,  speed = 1.5,  bezier = "linear",      style = "fade" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true,  speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true,  speed = 1.39, bezier = "almostLinear" })
hl.animation({ leaf = "workspaces",    enabled = true,  speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "zoomFactor",    enabled = true,  speed = 7,    bezier = "quick" })

-- Dwindle: preserve the split when closing windows
hl.config({
    dwindle = {
        preserve_split = true,
    },
})

hl.config({
    master = {
        new_status = "master",
    },
})

-- Window groups (tabbed windows) — style the tab bar, Catppuccin Mocha
hl.config({
    group = {
        col = {
            border_active   = { colors = { "rgba(cba6f7ee)", "rgba(89b4faee)" }, angle = 135 },
            border_inactive = "rgba(585b70aa)",
        },
        groupbar = {
            height     = 18,
            font_size  = 10,
            gradients  = false,
            rounding   = 8,
            text_color = "rgba(cdd6f4ff)",
            col = {
                active   = "rgba(cba6f7aa)",   -- mauve
                inactive = "rgba(45475aaa)",   -- surface1
            },
        },
    },
})

-- Cursor zoom (magnifier): zoom_factor is driven by the Super+Z binds
hl.config({
    cursor = {
        zoom_rigid = true,
    },
})

----------------
----  MISC  ----
----------------

hl.config({
    misc = {
        disable_hyprland_logo = true,
        vrr                     = 2,    -- adaptive sync in fullscreen (no-op if the panel can't)
    },
})

---------------
---- INPUT ----
---------------

hl.config({
    input = {
        kb_layout  = "us",
        kb_variant = "",
        kb_model   = "",
        kb_options = "",
        kb_rules   = "",

        follow_mouse = 1,
        sensitivity  = 0,

        touchpad = {
            natural_scroll = true,
        },
    },
})

-- 3-finger swipe to switch workspaces
hl.gesture({
    fingers   = 3,
    direction = "horizontal",
    action    = "workspace",
})

---------------------
---- KEYBINDINGS ----
---------------------

local mainMod = "SUPER"

-- ── Apps ──────────────────────────────────────────────
hl.bind(mainMod .. " + Q", hl.dsp.exec_cmd(terminal))            -- terminal: ghostty
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))         -- files: nautilus
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd(menu))                -- app launcher: rofi (drun)
hl.bind(mainMod .. " + SHIFT + R", hl.dsp.exec_cmd("rofi -show run"))  -- command runner
hl.bind("SUPER + TAB", hl.dsp.exec_cmd(windowMenu))              -- window switcher
hl.bind(mainMod .. " + SHIFT + V", hl.dsp.exec_cmd(
    'cliphist list | rofi -dmenu -p Clipboard | cliphist decode | wl-copy'
))
hl.bind(mainMod .. " + O", hl.dsp.exec_cmd("1password --quick-access"))  -- 1Password Quick Access

-- ── Window management ─────────────────────────────────
hl.bind(mainMod .. " + C", hl.dsp.window.close())
hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))         -- dwindle only
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen())          -- toggle fullscreen

-- ── Session ───────────────────────────────────────────
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd(lockCmd))             -- lock screen: hyprlock
hl.bind(mainMod .. " + M", hl.dsp.exit())

-- ── Layout: dwindle <-> scrolling (0.56 built-in PaperWM-style layout) ──
local layout = "dwindle"
hl.bind(mainMod .. " + Y", function()
    layout = (layout == "dwindle") and "scrolling" or "dwindle"
    hl.config({ general = { layout = layout } })
end)

-- ── Window groups (tabbed windows) ────────────────────
hl.bind(mainMod .. " + G",            hl.dsp.group.toggle())      -- tab/untab focused window
hl.bind(mainMod .. " + CTRL + G",     hl.dsp.group.lock_active()) -- lock the active group
hl.bind(mainMod .. " + CTRL + left",  hl.dsp.group.prev())        -- previous tab
hl.bind(mainMod .. " + CTRL + right", hl.dsp.group.next())        -- next tab
hl.bind(mainMod .. " + SHIFT + G",    hl.dsp.window.move({ out_of_group = true }))

-- ── Adjust mode (Super+A): arrows resize, Shift+arrows move, Esc/Enter exits ──
hl.define_submap("adjust", function()
    local step = 40
    hl.bind("left",          hl.dsp.window.resize({ x = -step, y = 0, relative = true }), { repeating = true })
    hl.bind("right",         hl.dsp.window.resize({ x =  step, y = 0, relative = true }), { repeating = true })
    hl.bind("up",            hl.dsp.window.resize({ x = 0, y = -step, relative = true }), { repeating = true })
    hl.bind("down",          hl.dsp.window.resize({ x = 0, y =  step, relative = true }), { repeating = true })
    hl.bind("SHIFT + left",  hl.dsp.window.move({ x = -step, y = 0, relative = true }), { repeating = true })
    hl.bind("SHIFT + right", hl.dsp.window.move({ x =  step, y = 0, relative = true }), { repeating = true })
    hl.bind("SHIFT + up",    hl.dsp.window.move({ x = 0, y = -step, relative = true }), { repeating = true })
    hl.bind("SHIFT + down",  hl.dsp.window.move({ x = 0, y =  step, relative = true }), { repeating = true })
    hl.bind("escape", hl.dsp.submap("reset"))
    hl.bind("return", hl.dsp.submap("reset"))
end)
hl.bind(mainMod .. " + A", hl.dsp.submap("adjust"))

-- ── Magnifier (cursor zoom) ───────────────────────────
local zoomLevel = 1
local function zoomBy(step)
    zoomLevel = math.min(math.max(zoomLevel + step, 1), 5)
    hl.config({ cursor = { zoom_factor = zoomLevel } })
end
hl.bind(mainMod .. " + Z",         function() zoomBy(0.25) end,  { repeating = true })
hl.bind(mainMod .. " + SHIFT + Z", function() zoomBy(-0.25) end, { repeating = true })

-- ── Tags: mark a window, jump back to it ──────────────
local markTag = "marked"
hl.bind(mainMod .. " + SHIFT + T", function()
    local w = hl.get_active_window()
    if not w then return end
    local tags = w.tags or {}
    if type(tags) == "string" then tags = { tags } end
    local marked = false
    for _, t in ipairs(tags) do
        if t == markTag then marked = true end
    end
    hl.dispatch(hl.dsp.window.tag({ tag = marked and ("-" .. markTag) or ("+" .. markTag) }))
end)
hl.bind(mainMod .. " + T", function()
    local marked = hl.get_windows({ tag = markTag })
    if marked[1] then
        hl.dispatch(hl.dsp.focus({ window = marked[1].address }))
    end
end)

-- ── Screenshots ───────────────────────────────────────
-- Full screen -> file
hl.bind("Print", hl.dsp.exec_cmd(
    'mkdir -p ~/Pictures/Screenshots && grim ~/Pictures/Screenshots/full-$(date +%Y%m%d-%H%M%S).png && notify-send -t 2000 "Screenshot" "Full screen saved"'
))
-- Region -> file
hl.bind("SUPER + Print", hl.dsp.exec_cmd(
    'mkdir -p ~/Pictures/Screenshots && grim -g "$(slurp)" ~/Pictures/Screenshots/region-$(date +%Y%m%d-%H%M%S).png && notify-send -t 2000 "Screenshot" "Region saved"'
))
-- Region -> clipboard
hl.bind("ALT + Print", hl.dsp.exec_cmd(
    'grim -g "$(slurp)" - | wl-copy && notify-send -t 2000 "Screenshot" "Region copied to clipboard"'
))
-- Same on keyboards without a Print key (P for Print): full / region->file / region->clipboard
hl.bind("SUPER + CTRL + P", hl.dsp.exec_cmd(
    'mkdir -p ~/Pictures/Screenshots && grim ~/Pictures/Screenshots/full-$(date +%Y%m%d-%H%M%S).png && notify-send -t 2000 "Screenshot" "Full screen saved"'
))
hl.bind("SUPER + SHIFT + P", hl.dsp.exec_cmd(
    'mkdir -p ~/Pictures/Screenshots && grim -g "$(slurp)" ~/Pictures/Screenshots/region-$(date +%Y%m%d-%H%M%S).png && notify-send -t 2000 "Screenshot" "Region saved"'
))
hl.bind("SUPER + ALT + P", hl.dsp.exec_cmd(
    'grim -g "$(slurp)" - | wl-copy && notify-send -t 2000 "Screenshot" "Region copied to clipboard"'
))

-- Region -> Satty (annotate, then save/copy from Satty's toolbar)
local annotate = 'grim -g "$(slurp)" - | satty --filename - --output-filename ~/Pictures/Screenshots/annotated-%Y%m%d-%H%M%S.png --copy-command "wl-copy" --early-exit save --initial-tool crop'
hl.bind("CTRL + Print",  hl.dsp.exec_cmd(annotate))
hl.bind("CTRL + ALT + P", hl.dsp.exec_cmd(annotate))  -- Print-less variant

-- ── Screen recording (wl-screenrec) ───────────────────
-- Region + system audio; Ctrl+Shift+Print stops and saves
local recStart = 'mkdir -p ~/Videos && wl-screenrec -g "$(slurp)" --audio -f ~/Videos/recording-$(date +%Y%m%d-%H%M%S).mp4'
local recStop  = 'pkill -INT -x wl-screenrec && notify-send -t 2000 "Recording" "Stopped and saved to ~/Videos"'
hl.bind("SHIFT + Print",       hl.dsp.exec_cmd(recStart))
hl.bind("SHIFT + ALT + P",     hl.dsp.exec_cmd(recStart))  -- Print-less variant
hl.bind("CTRL + SHIFT + Print", hl.dsp.exec_cmd(recStop))
hl.bind("CTRL + SHIFT + ALT + P", hl.dsp.exec_cmd(recStop)) -- Print-less variant

-- ── Instant replay (gpu-screen-recorder) ──────────────
-- Super+F11 toggles a background daemon keeping the last 30 s in memory;
-- Super+F12 writes those 30 s to ~/Videos/Replays
hl.bind(mainMod .. " + F11", hl.dsp.exec_cmd(
    'if pgrep -x gpu-screen-recorder >/dev/null; then pkill -x gpu-screen-recorder && notify-send -t 2000 "Replay" "Stopped"; else mkdir -p ~/Videos/Replays && nohup gpu-screen-recorder -w screen -f 60 -a default_output -q medium -c mp4 -r 30 -ro ~/Videos/Replays >/dev/null 2>&1 & notify-send -t 2000 "Replay" "Recording last 30 s (in memory)"; fi'
))
hl.bind(mainMod .. " + F12", hl.dsp.exec_cmd(
    'pkill -USR1 -x gpu-screen-recorder && notify-send -t 2000 "Replay" "Saved last 30 s to ~/Videos/Replays" || notify-send -t 2000 "Replay" "Not running (Super+F11 to start)"'
))

-- ── Focus (arrow keys) ────────────────────────────────
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))

-- ── Workspaces ────────────────────────────────────────
-- SUPER + [0-9] to switch, SUPER + SHIFT + [0-9] to move window
for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    hl.bind(mainMod .. " + " .. key,         hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

-- Scratchpad (special workspace)
hl.bind(mainMod .. " + S",         hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

-- Scroll through workspaces with SUPER + scroll
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- Move/resize windows with SUPER + LMB/RMB
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- ── Multimedia keys ───────────────────────────────────
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true })
hl.bind("XF86MonBrightnessUp",  hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"),                  { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown",hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"),                  { locked = true, repeating = true })
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })

--------------------------------
---- WINDOWS AND WORKSPACES ----
--------------------------------

-- Ignore maximize requests from apps — keeps tiling predictable
hl.window_rule({
    name  = "suppress-maximize-events",
    match = { class = ".*" },
    suppress_event = "maximize",
})

-- Fix some dragging issues with XWayland
hl.window_rule({
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },
    no_focus = true,
})

-- Float common utilities
hl.window_rule({
    name  = "float-utilities",
    match = { class = "^(pavucontrol|nm-connection-editor)$" },
    float = true,
})
