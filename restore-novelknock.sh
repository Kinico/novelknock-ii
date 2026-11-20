#!/usr/bin/env bash
# Puts every saved file back into ~/.config (ii, Hyprland keybinds/rules, ii settings).
# Run this after an update resets anything.
cd "$(dirname "$0")" || exit 1
REPO="$(pwd)"
CFG="$HOME/.config"
# LITE mode (laptop): on when installed with --lite, remembered in ~/.config/novelknock/lite
LITE=0
{ [ "${NK_LITE:-0}" = 1 ] || [ -f "$CFG/novelknock/lite" ]; } && LITE=1
echo "Unlocking..."
sudo chattr -R -i "$CFG/quickshell/ii" 2>/dev/null
sudo chattr -i "$CFG/hypr/hyprland/keybinds.lua" "$CFG/hypr/hyprland/execs.lua" 2>/dev/null
sudo chattr -R -i "$CFG/hypr/custom" 2>/dev/null
grep -v '^#' files.list | while read -r f; do
  [ -z "$f" ] && continue
  # the PC monitor layout does not belong on the laptop
  [ "$LITE" = 1 ] && [ "$f" = "hypr/monitors.lua" ] && continue
  # the laptop keeps its own ii settings (wallpaper, workspaces shown, ...) after the first install
  [ "$LITE" = 1 ] && [ "$f" = "illogical-impulse/config.json" ] && [ -f "$CFG/$f" ] && [ -f "$CFG/novelknock/lite-config-done" ] && continue
  src="$REPO/config/$f"
  [ -f "$src" ] || continue
  mkdir -p "$(dirname "$CFG/$f")"
  cp -v "$src" "$CFG/$f"
done
[ "$LITE" = 1 ] && bash "$REPO/lite/apply-lite.sh" && touch "$CFG/novelknock/lite-config-done"
bash "$REPO/lock-novelknock.sh"
hyprctl reload >/dev/null 2>&1
echo "Done. Restart Quickshell with: pkill qs; qs -c ii"
