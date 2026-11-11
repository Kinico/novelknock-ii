#!/usr/bin/env bash
# Restarts linux-wallpaperengine if it dies, using the exact command it was last running with.
# - Remembers the running wallpaper's command line every 2 seconds.
# - If the engine is gone for ~6 seconds (long enough for the app to switch wallpapers), it starts it again.
# - Pause it:  touch ~/.local/state/wallpaper-watchdog/paused   (remove the file to resume)
# - Log:       ~/.local/state/wallpaper-watchdog/log
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/wallpaper-watchdog"
mkdir -p "$STATE"
ARGS="$STATE/last-args"
CWD="$STATE/last-cwd"
LOG="$STATE/log"

# only one watchdog at a time
exec 9>"$STATE/lock"
flock -n 9 || exit 0

missing=0
restarts=()
while true; do
    pid=$(pgrep -o -f '(^|/)linux-wallpaperengine( |$)')
    if [ -n "$pid" ] && [ -r "/proc/$pid/cmdline" ]; then
        missing=0
        tr '\0' '\n' < "/proc/$pid/cmdline" > "$ARGS.tmp" && [ -s "$ARGS.tmp" ] && mv "$ARGS.tmp" "$ARGS"
        readlink "/proc/$pid/cwd" > "$CWD" 2>/dev/null
    else
        missing=$((missing + 1))
        if [ "$missing" -ge 3 ] && [ -s "$ARGS" ] && [ ! -e "$STATE/paused" ]; then
            now=$(date +%s)
            # stop after 5 restarts in 5 minutes so a broken wallpaper can't loop forever
            recent=()
            for t in "${restarts[@]}"; do [ $((now - t)) -lt 300 ] && recent+=("$t"); done
            restarts=("${recent[@]}")
            if [ "${#restarts[@]}" -ge 5 ]; then
                echo "$(date '+%F %T') crashed 5 times in 5 minutes, pausing" >> "$LOG"
                notify-send "Wallpaper keeps crashing" "Auto-restart paused. Remove ~/.local/state/wallpaper-watchdog/paused to resume." 2>/dev/null
                touch "$STATE/paused"
                continue
            fi
            restarts+=("$now")
            echo "$(date '+%F %T') wallpaper engine not running, restarting" >> "$LOG"
            mapfile -t cmd < "$ARGS"
            dir=$(cat "$CWD" 2>/dev/null)
            (
                cd "${dir:-/opt/linux-wallpaperengine}" || exit
                export LD_LIBRARY_PATH="/opt/linux-wallpaperengine/lib:$LD_LIBRARY_PATH"
                setsid "${cmd[@]}" >/dev/null 2>&1 &
            )
            missing=0
            sleep 10
        fi
    fi
    sleep 2
done
