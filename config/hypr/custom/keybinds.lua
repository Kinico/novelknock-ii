hl.bind("CTRL+SUPER+ALT+Slash", hl.dsp.exec_cmd("xdg-open ~/.config/hypr/custom/keybinds.lua"), {description = "Edit user keybinds"} )
hl.bind("SUPER + F12", hl.dsp.exec_cmd("bash $HOME/.config/hypr/custom/scripts/perf-hud.sh toggle"), { description = "Games: show or hide the FPS and stats overlay" })
hl.bind("SUPER + ALT + X", hl.dsp.global("quickshell:mediaFullscreenToggle"), { description = "Shell: Fullscreen music view with lyrics" })
