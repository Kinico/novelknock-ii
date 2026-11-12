#!/usr/bin/env bash
# Matches the ii theme colors to the running Wallpaper Engine wallpaper.
#   wallpaper-colors.sh auto [since]   pick colors for the current wallpaper (called by the watchdog)
#   wallpaper-colors.sh next           use the next color found in this wallpaper (saved per wallpaper)
#   wallpaper-colors.sh on | off       turn matching on, or off (off goes back to your normal ii colors)
# Where the colors come from:
#   1. ~/.cache/linux-wallpaperengine/wallpaper.jpg, a picture of what the engine really draws
#      (saved by the NovelKnock engine build about 3 seconds after a wallpaper loads)
#   2. otherwise the wallpaper's preview image
# Borders are trimmed and only the middle of the picture is used. Dull colors lose to vivid ones.
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/wallpaper-watchdog"
CFG_DIR="$HOME/.config/linux-wallpaperengine"
COLORS="$CFG_DIR/colors.json"
SHOT="${XDG_CACHE_HOME:-$HOME/.cache}/linux-wallpaperengine/wallpaper.jpg"
ARGS="$STATE_DIR/last-args"
SWITCHWALL="$HOME/.config/quickshell/ii/scripts/colors/switchwall.sh"
VENV="$(eval echo "${ILLOGICAL_IMPULSE_VIRTUAL_ENV:-$HOME/.local/state/quickshell/.venv}")"
LOG="$STATE_DIR/log"
mkdir -p "$STATE_DIR" "$CFG_DIR"

log() { echo "$(date '+%F %T') colors: $*" >> "$LOG"; }

# one color job at a time; a newer "auto" makes older waiting ones give up
exec 8>"$STATE_DIR/colors.lock"
echo "$$" > "$STATE_DIR/colors.latest"
flock -w 60 8 || exit 0

action="${1:-auto}"
since="${2:-0}"

json() {   # json get <key> | json set <key> <value>
    python3 - "$COLORS" "$@" <<'PYEOF'
import json, sys
p, op = sys.argv[1], sys.argv[2]
try:
    d = json.load(open(p))
except Exception:
    d = {}
d.setdefault("enabled", True)
if op == "get":
    v = d.get(sys.argv[3], "")
    print(json.dumps(v) if isinstance(v, (dict, list, bool)) else v)
else:
    k, v = sys.argv[3], sys.argv[4]
    d[k] = json.loads(v)
    json.dump(d, open(p, "w"), indent=2)
PYEOF
}

current_key() {
    awk 'p=="--bg"{sub(/\/+$/,""); n=split($0,a,"/"); if(!seen[a[n]]++) printf "%s%s", (k?"+":""), a[n]; k=1} {p=$0}' "$ARGS" 2>/dev/null
}
first_bg() {
    awk 'p=="--bg"{print; exit} {p=$0}' "$ARGS" 2>/dev/null
}

apply_hex() {
    local hex="$1"
    if [ "$(json get applied)" = "$hex" ]; then return; fi
    log "theme color $hex"
    bash "$SWITCHWALL" --noswitch --color "$hex" >/dev/null 2>&1
    json set applied "\"$hex\""
}

case "$action" in
    off)
        json set enabled false
        json set applied '""'
        log "matching turned off, back to normal colors"
        bash "$SWITCHWALL" --noswitch --color clear >/dev/null 2>&1
        exit 0 ;;
    on)
        json set enabled true
        json set applied '""'
        action=auto; since=0 ;;
esac

[ "$(json get enabled)" = "true" ] || exit 0
key=$(current_key)
[ -n "$key" ] || exit 0

if [ "$action" = "next" ]; then
    python3 - "$COLORS" "$key" <<'PYEOF'
import json, sys
p, key = sys.argv[1], sys.argv[2]
d = json.load(open(p))
n = len(d.get("candidates", {}).get(key, [])) or 1
picks = d.setdefault("picks", {})
picks[key] = (picks.get(key, 0) + 1) % n
json.dump(d, open(p, "w"), indent=2)
PYEOF
else
    # ---- find the picture to read colors from ----
    src=""
    # wait up to ~15 s for a fresh picture from the engine (only if this engine build saves one)
    [ -e "$SHOT" ] || since=0
    for _ in $(seq 1 30); do
        [ "$(cat "$STATE_DIR/colors.latest")" = "$$" ] || exit 0   # a newer request took over
        if [ -s "$SHOT" ] && [ "$(stat -c %Y "$SHOT")" -ge "$since" ]; then src="$SHOT"; break; fi
        [ "$since" = "0" ] && break
        sleep 0.5
    done
    bg=$(first_bg)
    preview=""
    for f in "$bg"/preview.jpg "$bg"/preview.png "$bg"/preview.jpeg "$bg"/preview.webp "$bg"/preview.gif "$bg"/preview.*; do
        [ -f "$f" ] && { preview="$f"; break; }
    done

    # ---- pick the colors (in ii's own Python, same color science as the theme) ----
    cands=$(source "$VENV/bin/activate" 2>/dev/null; python3 - "$src" "$preview" <<'PYEOF'
import sys, json
from PIL import Image, ImageChops, ImageStat
from materialyoucolor.quantize import QuantizeCelebi
from materialyoucolor.score.score import Score
from materialyoucolor.utils.color_utils import rgba_from_argb

def usable(path, is_shot):
    if not path:
        return None
    try:
        im = Image.open(path)
        im.seek(0)                      # first frame of a gif
        im = im.convert("RGB")
    except Exception:
        return None
    # trim solid borders (same color as the corner)
    bg = Image.new("RGB", im.size, im.getpixel((0, 0)))
    box = ImageChops.difference(im, bg).convert("L").point(lambda v: 255 if v > 24 else 0).getbbox()
    if box and (box[2] - box[0]) > im.width * 0.4 and (box[3] - box[1]) > im.height * 0.4:
        im = im.crop(box)
    # keep only the middle 70 percent, frames and edge decorations live outside it
    w, h = im.size
    im = im.crop((int(w * 0.15), int(h * 0.15), int(w * 0.85), int(h * 0.85)))
    if is_shot:   # reject a black or blank picture (wallpaper still fading in)
        st = ImageStat.Stat(im.convert("L"))
        if st.mean[0] < 12 or st.stddev[0] < 6:
            return None
    im.thumbnail((128, 128))
    return im

im, used = usable(sys.argv[1], True), "the live wallpaper"
if im is None:
    im, used = usable(sys.argv[2], False), "the preview"
if im is None:
    sys.exit(0)
raw = im.tobytes()
pixels = [(raw[i], raw[i + 1], raw[i + 2], 255) for i in range(0, len(raw), 3)]
result = QuantizeCelebi(pixels, 128)
ranked = Score.score(result)          # up to 4 colors, vivid and common first (same call ii uses)
hexes = []
for argb in ranked:
    if (argb & 0xFFFFFF) == 0x4285F4:  # Score's fallback when nothing is colorful, skip it
        continue
    r, g, b, _ = rgba_from_argb(argb)
    hx = "#{:02X}{:02X}{:02X}".format(round(r), round(g), round(b))
    if hx not in hexes:
        hexes.append(hx)
print(json.dumps({"from": used, "colors": hexes}))
PYEOF
)
    used=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["from"])' "$cands" 2>/dev/null)
    cands=$(python3 -c 'import json,sys; print(json.dumps(json.loads(sys.argv[1])["colors"]))' "$cands" 2>/dev/null)
    if [ -z "$cands" ] || [ "$cands" = "[]" ]; then
        log "no usable colors found for $key, keeping the current theme"
        exit 0
    fi
    log "found colors for $key from $used: $cands"
    python3 - "$COLORS" "$key" "$cands" <<'PYEOF'
import json, sys
p, key, cands = sys.argv[1], sys.argv[2], json.loads(sys.argv[3])
try:
    d = json.load(open(p))
except Exception:
    d = {"enabled": True}
d.setdefault("candidates", {})[key] = cands
json.dump(d, open(p, "w"), indent=2)
PYEOF
fi

hex=$(python3 - "$COLORS" "$key" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
c = d.get("candidates", {}).get(sys.argv[2], [])
if c:
    print(c[d.get("picks", {}).get(sys.argv[2], 0) % len(c)])
PYEOF
)
[ -n "$hex" ] || exit 0
python3 - "$COLORS" "$key" "$hex" <<'PYEOF'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["current"] = {"key": sys.argv[2], "color": sys.argv[3], "count": len(d.get("candidates", {}).get(sys.argv[2], []))}
json.dump(d, open(p, "w"), indent=2)
PYEOF
apply_hex "$hex"
