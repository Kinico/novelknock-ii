-- NovelKnock LITE (laptop). No monitor/workspace rules: one screen, workspaces 1 to 5 work as usual.

hl.window_rule({
    match = { class = "twintaillauncher" },
    float = true,
})

-- Blur only where it matters (kitty, Zen, the Quickshell panels), in the cheap "xray" mode:
-- xray blurs just the wallpaper once instead of every window behind, so it is light on old Intel graphics
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
            enabled = true,
            xray    = true,  -- the cheap mode
            size    = 3,
            passes  = 1,     -- PC uses 2
            vibrancy = 0.1696,
        },
        shadow = { enabled = false },
    },
})

-- Quickshell bar, sidebars and music sheet get the same frosted look as on the PC
hl.layer_rule({ match = { namespace = "quickshell:(bar|sidebarLeft|sidebarRight|mediaControls)" }, blur = true })
hl.layer_rule({ match = { namespace = "quickshell:(bar|sidebarLeft|sidebarRight|mediaControls)" }, ignore_alpha = 0.2 })

-- Touchpad: two-finger swipe left/right switches workspace
-- (the 3- and 4-finger gestures from end-4 still work too)
hl.gesture({ fingers = 2, direction = "horizontal", action = "workspace" })
