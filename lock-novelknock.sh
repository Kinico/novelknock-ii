#!/usr/bin/env bash
# Locks the ii folder and your Hyprland keybinds/rules so updates can't change them.
CFG="$HOME/.config"
sudo chattr -R +i "$CFG/quickshell/ii" 2>/dev/null
sudo chattr +i "$CFG/hypr/hyprland/keybinds.lua" "$CFG/hypr/hyprland/execs.lua"
sudo chattr -R +i "$CFG/hypr/custom" 2>/dev/null
echo "Locked. (Messages about symlinks are harmless.)"
