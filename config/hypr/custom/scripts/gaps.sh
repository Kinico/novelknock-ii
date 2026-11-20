#!/usr/bin/env bash
# Window gaps for the Settings app (Quick > Bar & screen > Window gaps).
#   gaps.sh get              -> {"in": 4, "out": 5}
#   gaps.sh set <in> <out>   -> saves ~/.config/hypr/gaps.lua (outside the locked custom folder) and reloads Hyprland
F="$HOME/.config/hypr/gaps.lua"
case "$1" in
    get)
        i=$(grep -oP 'gaps_in\s*=\s*\K[0-9]+' "$F" 2>/dev/null | head -1)
        o=$(grep -oP 'gaps_out\s*=\s*\K[0-9]+' "$F" 2>/dev/null | head -1)
        printf '{"in": %s, "out": %s}\n' "${i:-4}" "${o:-5}"
        ;;
    set)
        i=$(( ${2:-4} )); o=$(( ${3:-5} ))
        cat > "$F" <<LUA
-- Written by the Settings app (Quick > Bar & screen > Window gaps), loaded from custom/general.lua
hl.config({
    general = {
        gaps_in = $i,
        gaps_out = $o,
    },
})
LUA
        hyprctl reload >/dev/null
        ;;
    *) echo "usage: $0 get | set <in> <out>" >&2; exit 1 ;;
esac
