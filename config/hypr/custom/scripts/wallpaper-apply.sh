#!/usr/bin/env bash
# Wallpaper Engine wallpapers for the Super+Z picker.
#   wallpaper-apply.sh list          JSON list of installed Workshop wallpapers (for the picker)
#   wallpaper-apply.sh apply <dir>   play that wallpaper on all monitors with your usual settings
#   wallpaper-apply.sh restore       start the last picked wallpaper again (used by the watchdog at login)
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/wallpaper-watchdog"
ARGS="$STATE/last-args"
CWD="$STATE/last-cwd"
PICKED="$STATE/picked-args"     # args of a wallpaper chosen in the picker (kept across logins)
ENGINE_DIR="/opt/linux-wallpaperengine"
STEAM="$HOME/.local/share/Steam"
mkdir -p "$STATE"

workshop_dirs() {
    {
        echo "$STEAM/steamapps"
        # extra Steam library folders
        grep -o '"path"[[:space:]]*"[^"]*"' "$STEAM/steamapps/libraryfolders.vdf" 2>/dev/null \
            | sed 's/.*"path"[[:space:]]*"\(.*\)"/\1\/steamapps/'
    } | awk '!seen[$0]++' | while read -r lib; do
        [ -d "$lib/workshop/content/431960" ] && echo "$lib/workshop/content/431960"
    done
}

start_engine() {   # start_engine <args file>
    mapfile -t cmd < "$1"
    [ "${#cmd[@]}" -gt 0 ] || return 1
    pkill -f '(^|/)linux-wallpaperengine( |$)'
    sleep 0.5
    pgrep -f '(^|/)linux-wallpaperengine( |$)' >/dev/null && pkill -9 -f '(^|/)linux-wallpaperengine( |$)'
    local dir
    dir=$(cat "$CWD" 2>/dev/null)
    (
        cd "${dir:-$ENGINE_DIR}" 2>/dev/null || cd "$ENGINE_DIR" || exit
        export LD_LIBRARY_PATH="$ENGINE_DIR/lib:$LD_LIBRARY_PATH"
        setsid "${cmd[@]}" >/dev/null 2>&1 < /dev/null &
    )
}

case "$1" in
    list)
        workshop_dirs | python3 -c '
import json, os, sys
items = []
for root in sys.stdin.read().split():
    for name in os.listdir(root):
        d = os.path.join(root, name)
        p = os.path.join(d, "project.json")
        try:
            with open(p, encoding="utf-8", errors="replace") as f:
                pj = json.load(f)
        except Exception:
            continue
        kind = str(pj.get("type", "")).lower()
        if kind not in ("scene", "video", "web"):
            continue          # application wallpapers can not run on Linux
        prev = pj.get("preview") or ""
        prev_path = os.path.join(d, prev) if prev and os.path.isfile(os.path.join(d, prev)) else ""
        if not prev_path:
            for c in ("preview.jpg", "preview.png", "preview.gif", "preview.jpeg", "preview.webp"):
                if os.path.isfile(os.path.join(d, c)):
                    prev_path = os.path.join(d, c)
                    break
        items.append({
            "id": name,
            "dir": d,
            "title": pj.get("title") or name,
            "type": kind,
            "rating": str(pj.get("contentrating") or "Everyone"),
            "preview": prev_path,
            "added": os.path.getmtime(d),
        })
items.sort(key=lambda i: i["added"], reverse=True)   # newest subscriptions first
print(json.dumps(items))
'
        ;;
    apply)
        dir="${2%/}"
        [ -f "$dir/project.json" ] || { echo "not a wallpaper folder: $dir" >&2; exit 1; }
        if [ -s "$ARGS" ]; then
            # same settings as now (screens, fps, scaling, assets), only the wallpaper changes
            awk -v bg="$dir" 'prev=="--bg"{print bg; prev=""; next} {print; prev=$0}' "$ARGS" > "$PICKED.tmp"
        else
            {
                echo "./linux-wallpaperengine"
                hyprctl monitors 2>/dev/null | awk '/^Monitor /{print "--screen-root"; print $2}'
                printf '%s\n' --bg "$dir" --silent --fps 30 --no-fullscreen-pause --scaling fill \
                    --assets-dir "$STEAM/steamapps/common/wallpaper_engine/assets"
            } > "$PICKED.tmp"
        fi
        mv "$PICKED.tmp" "$PICKED"
        basename "$dir" > "$STATE/picked-key"
        start_engine "$PICKED"
        ;;
    restore)
        [ -s "$PICKED" ] && start_engine "$PICKED"
        ;;
    *)
        echo "usage: $0 list | apply <wallpaper folder> | restore" >&2
        exit 1 ;;
esac
