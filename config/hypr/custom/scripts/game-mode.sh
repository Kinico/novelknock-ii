#!/usr/bin/env bash
# Extra steps for the Game mode switch (the switch itself also turns off blur, animations, shadows and gaps).
#   game-mode.sh on    stop the live wallpaper (frees GPU and VRAM) and set the CPU to performance
#   game-mode.sh off   put the power profile back and start the wallpaper again
#   game-mode.sh status
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/wallpaper-watchdog"
FLAG="$STATE/gamemode"                 # while this exists the watchdog leaves the wallpaper off
PATTERN='(^|/)linux-wallpaperengine( |$)'
APPLY="$(dirname "$(readlink -f "$0")")/wallpaper-apply.sh"
mkdir -p "$STATE"
log() { echo "$(date '+%F %T') game mode: $*" >> "$STATE/log"; }

case "$1" in
    on)
        [ -e "$FLAG" ] && exit 0
        touch "$FLAG"
        if pgrep -f "$PATTERN" >/dev/null; then
            touch "$STATE/gamemode-had-wallpaper"
            pkill -f "$PATTERN"
        fi
        if command -v powerprofilesctl >/dev/null; then
            powerprofilesctl get > "$STATE/gamemode-profile" 2>/dev/null
            powerprofilesctl set performance 2>/dev/null
        fi
        log "on (wallpaper stopped, CPU set to performance)"
        ;;
    off)
        [ -e "$FLAG" ] || exit 0
        if [ -s "$STATE/gamemode-profile" ] && command -v powerprofilesctl >/dev/null; then
            powerprofilesctl set "$(cat "$STATE/gamemode-profile")" 2>/dev/null
        fi
        rm -f "$STATE/gamemode-profile"
        if [ -e "$STATE/gamemode-had-wallpaper" ]; then
            rm -f "$STATE/gamemode-had-wallpaper"
            pgrep -f "$PATTERN" >/dev/null || bash "$APPLY" reapply
            sleep 2                    # the wallpaper is up before the watchdog is allowed to act again
        fi
        rm -f "$FLAG"
        log "off (wallpaper and power profile restored)"
        ;;
    status)
        [ -e "$FLAG" ] && echo on || echo off
        ;;
    *)
        echo "usage: $0 on | off | status" >&2; exit 1 ;;
esac
