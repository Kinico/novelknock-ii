#!/usr/bin/env bash
# Puts every saved file back into ~/.config (ii, Hyprland keybinds/rules, ii settings).
# Run this after an update resets anything.
cd "$(dirname "$0")" || exit 1
REPO="$(pwd)"
CFG="$HOME/.config"
echo "Unlocking..."
sudo chattr -R -i "$CFG/quickshell/ii" 2>/dev/null
sudo chattr -i "$CFG/hypr/hyprland/keybinds.lua" 2>/dev/null
sudo chattr -R -i "$CFG/hypr/custom" 2>/dev/null
grep -v '^#' files.list | while read -r f; do
  [ -z "$f" ] && continue
  src="$REPO/config/$f"
  [ -f "$src" ] || continue
  mkdir -p "$(dirname "$CFG/$f")"
  cp -v "$src" "$CFG/$f"
done
bash "$REPO/lock-novelknock.sh"
hyprctl reload >/dev/null 2>&1
echo "Done. Restart Quickshell with: pkill qs; qs -c ii"
