-- NovelKnock LITE (laptop). No monitor/workspace rules: one screen, workspaces 1 to 5 work as usual.

hl.window_rule({
    match = { class = "twintaillauncher" },
    float = true,
})

-- Blur only where it matters (kitty, Zen, the Quickshell panels), same settings as the PC
hl.window_rule({
    name  = "no-blur-default",
    match = { class = ".*" },
    no_blur = true,
})

hl.window_rule({
    name  = "kitty-frosted",
    match = { class = "^(kitty)$" },
    opacity = "0.85 override 0.75 override",
})

hl.window_rule({
    name  = "kitty-blur",
    match = { class = "^(kitty|zen)$" },
    no_blur = false,
})

hl.window_rule({
    match = { class = "^(kitty)$" },
    fullscreen_state = 0,
})

hl.config({
    decoration = {
        blur = {
            enabled  = true,
            size     = 2,     -- same blur as the PC
            passes   = 2,
            vibrancy = 0.1696,
        },
        shadow = { enabled = false },
    },
})

-- Quickshell bar, sidebars, music sheet, wallpaper picker (Super+Z) and overview get the frosted look
hl.layer_rule({ match = { namespace = "quickshell:(bar|sidebarLeft|sidebarRight|mediaControls|wallpaperSelector|overview)" }, blur = true })
hl.layer_rule({ match = { namespace = "quickshell:(bar|sidebarLeft|sidebarRight|mediaControls|wallpaperSelector|overview)" }, ignore_alpha = 0.2 })

-- Touchpad: two-finger swipe left/right switches workspace.
-- Handled by scripts/nk-swipe.py (started in hyprland/execs.lua), because Hyprland's scroll binds
-- ignore touchpad fingers. Apps still get their normal sideways scrolling.
