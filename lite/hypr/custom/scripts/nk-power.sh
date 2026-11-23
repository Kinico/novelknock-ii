#!/usr/bin/env bash
# NovelKnock LITE: keeps the CPU on the performance profile.
#   performance all the time (balanced makes Meet and Discord lag on this laptop)
#   balanced only when on battery and at 20% or less, to stretch the last bit
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

low_battery() {
    for b in /sys/class/power_supply/BAT*/capacity; do
        [ -f "$b" ] && [ "$(cat "$b")" -le 20 ] && return 0
    done
    return 1
}

last=""
while true; do
    if ! on_ac && low_battery; then want=balanced; else want=performance; fi
    if [ "$want" != "$last" ]; then
        # leave it alone if Game mode is on (it sets performance itself)
        [ -e "${XDG_STATE_HOME:-$HOME/.local/state}/wallpaper-watchdog/gamemode" ] || powerprofilesctl set "$want" 2>/dev/null
        last="$want"
    fi
    sleep 10
done
