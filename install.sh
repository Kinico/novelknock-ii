#!/usr/bin/env bash
# One-line installer for the NovelKnock-style Quickshell ii setup.
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/Kinico/novelknock-ii/master/install.sh)"
# - Downloads (or updates) this repo into ~/Documents/novelknock-ii
# - Backs up the files it is about to replace
# - Copies everything into ~/.config and locks it against updates
# - Starts the wallpaper watchdog and restarts Quickshell
set -u
# LITE mode for weaker laptops:  bash install.sh --lite
# (no Wallpaper Engine, no blur or shadows, bar wave off, no PC monitor layout). Remembered for later updates.
# To go back to the full version:  bash install.sh --full
for a in "$@"; do
    case "$a" in
        --lite) mkdir -p "$HOME/.config/novelknock"; touch "$HOME/.config/novelknock/lite" ;;
        --full) rm -f "$HOME/.config/novelknock/lite" ;;
    esac
done
REPO_URL="https://github.com/Kinico/novelknock-ii.git"
DIR="${NK_DIR:-$HOME/Documents/novelknock-ii}"
CFG="$HOME/.config"

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

command -v git >/dev/null || { echo "git is not installed. Install it with: sudo pacman -S git"; exit 1; }

# 1. Get the files
if [ -d "$DIR/.git" ]; then
    say "Updating $DIR"
    git -C "$DIR" pull --ff-only || echo "Could not update (local changes?), using the files already there."
else
    say "Downloading into $DIR"
    mkdir -p "$(dirname "$DIR")"
    git clone "$REPO_URL" "$DIR" || { echo "Download failed."; exit 1; }
fi
cd "$DIR" || exit 1

# 2. Back up what is about to be replaced
BACKUP="$HOME/Documents/novelknock-ii-backup-$(date +%Y-%m-%d_%H-%M-%S)"
say "Backing up your current files to $BACKUP"
grep -v '^#' files.list | while read -r f; do
    [ -z "$f" ] && continue
    [ -f "$CFG/$f" ] || continue
    mkdir -p "$(dirname "$BACKUP/$f")"
    cp "$CFG/$f" "$BACKUP/$f"
done

# 3. Install and lock (asks for your sudo password)
say "Installing into ~/.config"
bash ./restore-novelknock.sh

# 4. Wallpaper watchdog (full version only)
if [ -f "$CFG/novelknock/lite" ]; then
    say "LITE mode: skipping Wallpaper Engine and its watchdog"
    pkill -f wallpaper-watchdog.sh 2>/dev/null
    pkill -f linux-wallpaperengine 2>/dev/null
else
    say "Starting the wallpaper watchdog"
    pkill -f wallpaper-watchdog.sh 2>/dev/null
    sleep 1
    setsid bash "$CFG/hypr/custom/scripts/wallpaper-watchdog.sh" >/dev/null 2>&1 < /dev/null &
    disown 2>/dev/null
fi

# 5. Restart Quickshell (only inside a Hyprland session)
if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    say "Restarting Quickshell"
    pkill -x qs 2>/dev/null; pkill -x quickshell 2>/dev/null
    sleep 1
    setsid qs -c ii >/dev/null 2>&1 < /dev/null &
    disown 2>/dev/null
else
    echo "Not inside Hyprland right now, everything loads next time you log in."
fi

say "Done"
echo "Backup of your old files: $BACKUP"
echo "Optional, for wallpaper zoom and X/Y: build the patched engine in $DIR/wallpaperengine (makepkg -si)"
