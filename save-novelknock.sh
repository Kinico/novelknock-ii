#!/usr/bin/env bash
# Copies your current setup from ~/.config into this folder, then uploads it to GitHub (if set up).
cd "$(dirname "$0")" || exit 1
REPO="$(pwd)"
CFG="$HOME/.config"
grep -v '^#' files.list | while read -r f; do
  [ -z "$f" ] && continue
  [ -f "$CFG/$f" ] || continue
  mkdir -p "$(dirname "$REPO/config/$f")"
  cp "$CFG/$f" "$REPO/config/$f"
done
echo "Saved your current files into $REPO/config"
if [ -d "$REPO/.git" ]; then
  git -C "$REPO" add -A
  git -C "$REPO" commit -m "Update $(date '+%Y-%m-%d %H:%M')" >/dev/null && echo "Committed."
  git -C "$REPO" push && echo "Uploaded to GitHub."
fi
