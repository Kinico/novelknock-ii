#!/usr/bin/env bash
# NovelKnock LITE: power profile follows the charger.
#   plugged in  -> performance (smooth video calls, same as Game mode did)
#   on battery  -> balanced
# Turn it off by creating ~/.config/novelknock/no-auto-power
command -v powerprofilesctl >/dev/null || exit 0
[ -f "$HOME/.config/novelknock/no-auto-power" ] && exit 0
pgrep -f "[n]k-power.sh" | grep -vx "$$" | grep -q . && exit 0   # already running

on_ac() {
    for f in /sys/class/power_supply/*/online; do
        [ -f "$f" ] || continue
        t="$(cat "$(dirname "$f")/type" 2>/dev/null)"
        [ "$t" = "Mains" ] || [ "$t" = "USB" ] || continue
        [ "$(cat "$f")" = "1" ] && return 0
    done
    return 1
}

last=""
while true; do
    if on_ac; then want=performance; else want=balanced; fi
    if [ "$want" != "$last" ]; then
        # leave it alone if Game mode is on (it sets performance itself)
        [ -e "${XDG_STATE_HOME:-$HOME/.local/state}/wallpaper-watchdog/gamemode" ] || powerprofilesctl set "$want" 2>/dev/null
        last="$want"
    fi
    sleep 10
done
