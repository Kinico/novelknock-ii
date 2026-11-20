#!/usr/bin/env bash
# One-line installer for the NovelKnock-style Quickshell ii setup.
#   curl -sL https://raw.githubusercontent.com/Kinico/novelknock-ii/master/install.sh | bash
# - Downloads (or updates) this repo into ~/Documents/novelknock-ii
# - Backs up the files it is about to replace
# - Copies everything into ~/.config and locks it against updates
# - Starts the wallpaper watchdog and restarts Quickshell
set -u
# (everything is inside { } so it loads fully before running, which keeps "curl | bash" safe)
{
# LITE mode for weaker laptops:  curl -sL .../install.sh | bash -s -- --lite
# (no Wallpaper Engine, no blur or shadows, bar wave off, no PC monitor layout). Remembered for later updates.
# To go back to the full version:  bash install.sh --full
NKS="$HOME/.config/novelknock"
mkdir -p "$NKS"
for a in "$@"; do
    case "$a" in
        --lite) touch "$NKS/lite"; rm -f "$NKS/full" ;;
        --full) touch "$NKS/full"; rm -f "$NKS/lite" ;;
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

# 1b. Fresh machine: no end-4 ii yet, so install it first (NovelKnock replaces parts of it)
if [ ! -f "$CFG/quickshell/ii/shell.qml" ]; then
    say "end-4 dots-hyprland (ii) is not installed yet, installing it first"
    echo "Follow its prompts. When it finishes, this installer carries on with NovelKnock."
    E4="$HOME/.cache/dots-hyprland"
    if [ -d "$E4/.git" ]; then
        git -C "$E4" pull --ff-only || true
    else
        git clone https://github.com/end-4/dots-hyprland.git "$E4" --filter=blob:none || { echo "Could not download end-4 dots."; exit 1; }
    fi
    ( cd "$E4" && ./setup install < /dev/tty ) || { echo "end-4 setup did not finish. Fix that, then run this installer again."; exit 1; }
    [ -f "$CFG/quickshell/ii/shell.qml" ] || { echo "ii still not found after end-4 setup. Run this installer again after it works."; exit 1; }
    cd "$DIR" || exit 1
fi

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
}
