#!/usr/bin/env bash
# Installs what the Super+Z Workshop tab needs: Node.js (if missing) and steamworks.js,
# the same Steam library the wallpaperx app uses. Safe to run again.
DEST="$HOME/.local/share/novelknock-workshop"
if ! command -v node >/dev/null || ! command -v npm >/dev/null; then
    echo "Installing Node.js and npm (needs your password)..."
    sudo pacman -S --needed nodejs npm || { echo "Could not install Node.js. If pacman says to update first, run: sudo pacman -Syu"; exit 1; }
fi
mkdir -p "$DEST"
[ -f "$DEST/package.json" ] || echo '{"name":"novelknock-workshop","private":true}' > "$DEST/package.json"
echo "Installing steamworks.js..."
npm install --prefix "$DEST" --no-fund --no-audit steamworks.js@0.4.0 || exit 1
echo "Checking Steam..."
node "$HOME/.config/hypr/custom/scripts/workshop.mjs" status
echo "Done. Open Super+Z, then Workshop."
