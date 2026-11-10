-- Workspace-to-monitor assignment
for i = 1, 5 do
    hl.workspace_rule({ workspace = tostring(i), monitor = "HDMI-A-1", default = true, persistent = true })
end

for i = 6, 10 do
    hl.workspace_rule({ workspace = tostring(i), monitor = "DP-3", default = true, persistent = true })
end

hl.config({
    input = {
        sensitivity = -0.5,
        accel_profile = "flat",
    },
})

hl.window_rule({
    match = { class = "twintaillauncher" },
    float = true,
})

hl.window_rule({
    name  = "disable-blur-for-kitty",
    match = { class = "kitty" },
    no_blur = true,
})

hl.window_rule({
  name = "kitty-frosted",
  match = { class = "kitty" },
  opacity = "0.85 override 0.75 override",
  no_blur = true
})

-- Per-window toggle — decides WHICH windows get blur excluded
hl.window_rule({
    name  = "no-blur-default",
    match = { class = ".*" },
    no_blur = true,
})

hl.window_rule({
    name  = "kitty-blur",
    match = { class = "^(kitty|zen)$" },
    no_blur = false,
})

hl.config({
    decoration = {
        blur = {
            enabled  = true,
            size     = 2,     -- radius of the blur
            passes   = 2,     -- how many blur passes (stacks for a smoother/heavier look)
            vibrancy = 0.1696,
        },
    },
})

   hl.window_rule({
       match = { class = "^(kitty)$" },
       fullscreen_state = 0,
   })

-- NovelKnock Quickshell: blur behind the bar, sidebars and bottom music sheet
hl.layer_rule({ match = { namespace = "quickshell:(bar|sidebarLeft|sidebarRight|mediaControls)" }, blur = true })
hl.layer_rule({ match = { namespace = "quickshell:(bar|sidebarLeft|sidebarRight|mediaControls)" }, ignore_alpha = 0.2 })
