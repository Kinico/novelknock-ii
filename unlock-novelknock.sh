#!/usr/bin/env bash
# Unlocks everything so you (or Claude) can edit it. Run lock-novelknock.sh afterwards.
CFG="$HOME/.config"
sudo chattr -R -i "$CFG/quickshell/ii" 2>/dev/null
sudo chattr -i "$CFG/hypr/hyprland/keybinds.lua" "$CFG/hypr/hyprland/execs.lua"
sudo chattr -R -i "$CFG/hypr/custom" 2>/dev/null
echo "Unlocked. Run lock-novelknock.sh when you're done."
