-- NovelKnock LITE (laptop). No monitor/workspace rules: one screen, workspaces 1 to 5 work as usual.

hl.window_rule({
    match = { class = "twintaillauncher" },
    float = true,
})

-- Kitty and Zen stay slightly see-through, but without blur
hl.window_rule({
    name  = "kitty-frosted",
    match = { class = "^(kitty)$" },
    opacity = "0.92 override 0.85 override",
})

hl.window_rule({
    match = { class = "^(kitty)$" },
    fullscreen_state = 0,
})

-- The heavy stuff on old Intel graphics: blur and shadows. Both off.
hl.config({
    decoration = {
        blur = { enabled = false },
        shadow = { enabled = false },
    },
    misc = {
        vfr = true,  -- only redraw when something changes, saves battery
    },
})
