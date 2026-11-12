#!/usr/bin/env bash
# Keeps linux-wallpaperengine alive, using the exact command it was last running with.
# - Remembers the running wallpaper's command line every 2 seconds.
# - If the engine is gone for ~6 seconds (long enough for the app to switch wallpapers), it starts it again.
# - If a monitor is turned off and on (or plugged back in), it restarts the engine so the wallpaper comes back.
# - Waits for every monitor the wallpaper uses to be present before starting it.
# - Keeps a separate zoom / X / Y for every wallpaper (view-presets.json), swapping view.json when the wallpaper changes.
# - Matches the theme colors to each wallpaper (wallpaper-colors.sh), unless turned off in the Knock sidebar.
# - Pause it:  touch ~/.local/state/wallpaper-watchdog/paused   (remove the file to resume)
# - Log:       ~/.local/state/wallpaper-watchdog/log
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/wallpaper-watchdog"
mkdir -p "$STATE"
ARGS="$STATE/last-args"
CWD="$STATE/last-cwd"
LOG="$STATE/log"
PATTERN='(^|/)linux-wallpaperengine( |$)'

# only one watchdog at a time (the lock is not passed to the wallpaper engine, so a
# restarted engine can never block a new watchdog from starting)
exec 9>"$STATE/watchdog.lock"
flock -w 15 9 || exit 0   # waits a moment in case an old watchdog is still shutting down

log() { echo "$(date '+%F %T') $*" >> "$LOG"; }

monitors() {
    hyprctl monitors 2>/dev/null | awk '/^Monitor /{print $2}' | sort | tr '\n' ' '
}

# screens the saved wallpaper command draws on (values after --screen-root)
needed_screens() {
    awk 'prev=="--screen-root"{print} {prev=$0}' "$ARGS" 2>/dev/null
}

# ---- per-wallpaper zoom / X / Y ----
VIEWDIR="$HOME/.config/linux-wallpaperengine"
VIEW="$VIEWDIR/view.json"
view_mtime=""

wallpaper_key() {   # workshop id(s) of the wallpaper(s) in the saved command
    awk 'p=="--bg"{sub(/\/+$/,""); n=split($0,a,"/"); printf "%s%s", (k?"+":""), a[n]; k=1} {p=$0}' "$ARGS"
}

presets() {   # presets <sync|store> <key> <bg paths...>
    python3 - "$VIEWDIR" "$@" <<'PYEOF'
import json, os, sys
d, action, key, bgs = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]
os.makedirs(d, exist_ok=True)
view_p, pre_p, cur_p = (os.path.join(d, n) for n in ("view.json", "view-presets.json", "current-wallpaper.json"))
def load(p, default):
    try:
        with open(p) as f: return json.load(f)
    except Exception: return default
def save(p, data):
    tmp = p + ".tmp"
    with open(tmp, "w") as f: json.dump(data, f, indent=2)
    os.replace(tmp, p)
pre = load(pre_p, {})
view = load(view_p, {})
old = load(cur_p, {}).get("key", "")
if action == "sync" and old and old != key:
    pre[old] = view                    # remember the old wallpaper's values
    view = pre.get(key, {})            # new wallpaper: its own values, or default
    save(view_p, view)
pre[key] = view
save(pre_p, pre)
titles = []
for bg in bgs:
    t = load(os.path.join(bg, "project.json"), {}).get("title") or os.path.basename(bg.rstrip("/"))
    titles.append(t)
save(cur_p, {"key": key, "title": " + ".join(titles)})
PYEOF
}

sync_presets() {
    [ -s "$ARGS" ] || return
    local key m
    key=$(wallpaper_key)
    [ -n "$key" ] || return
    if [ "$key" != "$last_key" ]; then
        mapfile -t bgs < <(awk 'p=="--bg"{print} {p=$0}' "$ARGS")
        presets sync "$key" "${bgs[@]}"
        [ -n "$last_key" ] && log "wallpaper changed to $key, loaded its zoom / X / Y"
        last_key=$key
        # theme colors for this wallpaper (in the background, it waits for the engine's picture)
        local started
        started=$(stat -c %Y "/proc/$pid" 2>/dev/null || date +%s)
        setsid bash "$(dirname "$(readlink -f "$0")")/wallpaper-colors.sh" auto "$started" >/dev/null 2>&1 9>&- < /dev/null &
        view_mtime=$(stat -c %y "$VIEW" 2>/dev/null)
        return
    fi
    m=$(stat -c %y "$VIEW" 2>/dev/null)
    if [ -n "$m" ] && [ "$m" != "$view_mtime" ]; then
        view_mtime=$m
        presets store "$key"
    fi
}

screens_ready() {
    local mons s
    mons=" $(monitors)"
    for s in $(needed_screens); do
        [[ "$mons" == *" $s "* ]] || return 1
    done
    return 0
}

start_engine() {
    mapfile -t cmd < "$ARGS"
    local dir
    dir=$(cat "$CWD" 2>/dev/null)
    (
        cd "${dir:-/opt/linux-wallpaperengine}" || exit
        export LD_LIBRARY_PATH="/opt/linux-wallpaperengine/lib:$LD_LIBRARY_PATH"
        setsid "${cmd[@]}" >/dev/null 2>&1 9>&- &
    )
}

missing=0
restarts=()
last_key=""
last_mons=$(monitors)
while true; do
    sleep 2

    # ---- monitor turned off/on or plugged in ----
    mons=$(monitors)
    if [ -n "$mons" ] && [ "$mons" != "$last_mons" ]; then
        sleep 2                                   # let the monitor settle
        mons2=$(monitors)
        if [ "$mons2" != "$mons" ]; then continue; fi   # still changing, check again next loop
        last_mons=$mons
        if [ ! -e "$STATE/paused" ] && [ -s "$ARGS" ] && screens_ready; then
            log "monitors changed ($mons), restarting wallpaper"
            pkill -f "$PATTERN"
            sleep 1
            pgrep -f "$PATTERN" >/dev/null && pkill -9 -f "$PATTERN"
            start_engine
            missing=0
            sleep 6
            continue
        fi
    fi

    # ---- engine running: remember its command ----
    pid=$(pgrep -o -f "$PATTERN")
    if [ -n "$pid" ] && [ -r "/proc/$pid/cmdline" ]; then
        missing=0
        tr '\0' '\n' < "/proc/$pid/cmdline" > "$ARGS.tmp" && [ -s "$ARGS.tmp" ] && mv "$ARGS.tmp" "$ARGS"
        readlink "/proc/$pid/cwd" > "$CWD" 2>/dev/null
        sync_presets
        continue
    fi

    # ---- engine gone ----
    missing=$((missing + 1))
    [ "$missing" -ge 3 ] && [ -s "$ARGS" ] && [ ! -e "$STATE/paused" ] || continue
    screens_ready || continue                     # a monitor is off, wait for it to come back

    now=$(date +%s)
    # stop after 5 restarts in 5 minutes so a broken wallpaper can't loop forever
    recent=()
    for t in "${restarts[@]}"; do [ $((now - t)) -lt 300 ] && recent+=("$t"); done
    restarts=("${recent[@]}")
    if [ "${#restarts[@]}" -ge 5 ]; then
        log "crashed 5 times in 5 minutes, pausing"
        notify-send "Wallpaper keeps crashing" "Auto-restart paused. Remove ~/.local/state/wallpaper-watchdog/paused to resume." 2>/dev/null
        touch "$STATE/paused"
        continue
    fi
    restarts+=("$now")
    log "wallpaper engine not running, restarting"
    start_engine
    missing=0
    sleep 8
done
