#!/usr/bin/env bash
# NovelKnock lite: one workspace step per two-finger swipe.
# A swipe sends dozens of sideways-scroll events; only the first one after a short pause switches.
#   swipe-workspace.sh next|prev
GAP_MS=350   # pause that separates two swipes
STATE="${XDG_RUNTIME_DIR:-/tmp}/nk-swipe-last"
now=$(( $(date +%s%N) / 1000000 ))
last=$(cat "$STATE" 2>/dev/null || echo 0)
echo "$now" > "$STATE"
[ $(( now - last )) -lt $GAP_MS ] && exit 0
case "$1" in
    next) hyprctl dispatch 'hl.dsp.focus({ workspace = "r+1" })' >/dev/null ;;
    prev) hyprctl dispatch 'hl.dsp.focus({ workspace = "r-1" })' >/dev/null ;;
esac
