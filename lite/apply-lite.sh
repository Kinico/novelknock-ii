#!/usr/bin/env bash
# NovelKnock LITE: run after the normal files are copied (restore-novelknock.sh does this when lite is on).
# Puts the laptop versions of the Hyprland files on top, turns off the bar wave, blur and other heavy bits.
cd "$(dirname "$0")" || exit 1
LITE="$(pwd)"
CFG="$HOME/.config"

echo "Applying LITE settings..."
# 1. Laptop versions of the Hyprland files
for f in hypr/hyprland/execs.lua hypr/custom/env.lua hypr/custom/rules.lua; do
    mkdir -p "$(dirname "$CFG/$f")"
    cp -v "$LITE/$f" "$CFG/$f"
done

# 2. Bar music wave off by default (cava then only runs while the music sheet is open)
mkdir -p "$CFG/novelknock"
if [ ! -f "$CFG/novelknock/bar-wave.json" ]; then
    printf '{\n  "enabled": false,\n  "strength": 3\n}\n' > "$CFG/novelknock/bar-wave.json"
fi

# 3. Super+Z opens the normal picture picker instead of the Wallpaper Engine library
sel="$CFG/quickshell/ii/modules/ii/wallpaperSelector/WallpaperSelectorContent.qml"
[ -f "$sel" ] && sed -i 's/^\(    property bool weMode: \)true\(.*\)$/\1false\2/' "$sel"
# and the "Wallpaper Engine" entry is taken out of the picker's folder list
[ -f "$sel" ] && python3 - "$sel" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
entry = """                            {
                                icon: "animation",
                                name: "Wallpaper Engine",
                                path: "WALLPAPER_ENGINE"
                            },
"""
open(p, "w").write(s.replace(entry, ""))
PY

# 4. ii settings: no blur on the lock screen, no zoom animation, slower system stats polling,
#    and the wallpaper path from the PC is cleared if that file is not on this machine
cfg="$CFG/illogical-impulse/config.json"
if [ -f "$cfg" ]; then
python3 - "$cfg" <<'PY'
import json, os, sys
p = sys.argv[1]
c = json.load(open(p))
def put(path, value):
    d = c
    keys = path.split(".")
    for k in keys[:-1]:
        d = d.setdefault(k, {})
    d[keys[-1]] = value
put("lock.blur.enable", False)
put("overlay.openingZoomAnimation", False)
put("overlay.darkenScreen", False)
put("resources.updateInterval", 5000)
put("background.parallax.enableWorkspace", False)
put("background.parallax.enableSidebar", False)
put("background.widgets.clock.cookie.constantlyRotate", False)
put("background.widgets.clock.digital.animateChange", False)
wp = c.get("background", {}).get("wallpaperPath", "")
if wp and not os.path.exists(wp):
    put("background.wallpaperPath", "")
json.dump(c, open(p, "w"), indent=4)
PY
fi
echo "LITE settings applied."
