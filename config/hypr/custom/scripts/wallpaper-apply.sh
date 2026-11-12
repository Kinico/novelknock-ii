#!/usr/bin/env bash
# Wallpaper Engine wallpapers for the Super+Z picker.
#   wallpaper-apply.sh list                   JSON list of installed Workshop wallpapers
#   wallpaper-apply.sh info <dir>             size, tags and resolution of one wallpaper (JSON)
#   wallpaper-apply.sh apply <dir> [screen]   play it on one display (or all displays when no screen)
#   wallpaper-apply.sh reapply                restart with the same wallpapers (after changing settings)
#   wallpaper-apply.sh restore                start the last picked layout again (used by the watchdog at login)
#   wallpaper-apply.sh boot                   at login: start the last wallpapers with your settings (no app needed)
#   wallpaper-apply.sh props <dir>            the wallpaper's own options (colors, switches, sliders...) as JSON
#   wallpaper-apply.sh autorestart on|off     turn the watchdog's auto-restart on or off
# Global settings (the Settings page): ~/.config/linux-wallpaperengine/global-settings.json
#   { "fps": 30, "pauseFullscreen": false, "scaling": "fill", "volume": 100, "mute": true, "noautomute": false,
#     "audio": true, "mouse": true, "parallax": true, "particles": true, "autoRestart": true, "translate": true }
# Per-wallpaper settings override them: ~/.config/linux-wallpaperengine/wallpaper-settings.json
#   { "<id>": { "scaling": "fit", "volume": 60, ..., "props": { "<option name>": <value> } } }
# Wallpaper and scaling are per display. Volume, audio, mouse, parallax and particles are shared by the
# engine: volume is the loudest of the wallpapers showing, the others turn off only if every
# wallpaper showing has them off.
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/wallpaper-watchdog"
ARGS="$STATE/last-args"
CWD="$STATE/last-cwd"
PICKED="$STATE/picked-args"
ENGINE_DIR="${NK_ENGINE_DIR:-/opt/linux-wallpaperengine}"
STEAM="$HOME/.local/share/Steam"
SETTINGS="$HOME/.config/linux-wallpaperengine/wallpaper-settings.json"
GLOBAL="$HOME/.config/linux-wallpaperengine/global-settings.json"
PATTERN='^([^ ]*/)?linux-wallpaperengine( |$)'   # only the engine itself: its command line starts with the program
SELF="$(readlink -f "$0")"
mkdir -p "$STATE" "$(dirname "$SETTINGS")"
log() { echo "$(date '+%F %T') $*" >> "$STATE/log"; }

workshop_dirs() {
    {
        echo "$STEAM/steamapps"
        grep -o '"path"[[:space:]]*"[^"]*"' "$STEAM/steamapps/libraryfolders.vdf" 2>/dev/null \
            | sed 's/.*"path"[[:space:]]*"\(.*\)"/\1\/steamapps/'
    } | awk '!seen[$0]++' | while read -r lib; do
        [ -d "$lib/workshop/content/431960" ] && echo "$lib/workshop/content/431960"
    done
}

start_engine() {   # start_engine <args file>
    mapfile -t cmd < "$1"
    # keep only the options: the program is always ./linux-wallpaperengine in the engine folder
    local first=-1 n
    for n in "${!cmd[@]}"; do
        case "${cmd[$n]}" in --*) first=$n; break ;; esac
    done
    [ "$first" -ge 0 ] || return 1
    cmd=(./linux-wallpaperengine "${cmd[@]:$first}")
    pkill -f "$PATTERN"
    sleep 0.5
    pgrep -f "$PATTERN" >/dev/null && pkill -9 -f "$PATTERN"
    local dir
    dir=$(cat "$CWD" 2>/dev/null)
    [ -x "$dir/linux-wallpaperengine" ] || dir=$ENGINE_DIR
    (
        cd "$dir" || exit
        export LD_LIBRARY_PATH="$ENGINE_DIR/lib:$LD_LIBRARY_PATH"
        unset MANGOHUD                 # the game overlay must not load into the wallpaper
        setsid "${cmd[@]}" >/dev/null 2>&1 < /dev/null 7>&- &
    )
}

# build the engine command: build_args <dir|-> <screen|all>   ("-" keeps the current wallpapers)
build_args() {
    local monitors
    monitors=$(hyprctl monitors 2>/dev/null | awk '/^Monitor /{print $2}' | paste -sd, -)
    python3 - "$ARGS" "$SETTINGS" "$1" "$2" "$monitors" "$STEAM" "$GLOBAL" <<'PYEOF'
import json, os, sys
args_p, settings_p, new_dir, target, monitors, steam, global_p = sys.argv[1:8]
picked_p = os.path.join(os.path.dirname(args_p), "picked-args")
monitors = [m for m in monitors.split(",") if m]
try:
    old = [l.rstrip("\n") for l in open(args_p)]
except Exception:
    old = []
if "--bg" not in old:                      # damaged or empty: use the last picked command
    try:
        old = [l.rstrip("\n") for l in open(picked_p)]
    except Exception:
        pass
try:
    settings = json.load(open(settings_p))
except Exception:
    settings = {}
glob = {"fps": None, "pauseFullscreen": None, "scaling": "fill", "volume": 100, "mute": True, "noautomute": False,
        "audio": True, "mouse": True, "parallax": True, "particles": True}
try:
    glob.update(json.load(open(global_p)))
except Exception:
    pass

# current layout from the running command
screens, mapping, default_bg, cur = [], {}, "", None
keep = {"fps": "30", "assets": os.path.join(steam, "steamapps/common/wallpaper_engine/assets"),
        "nofspause": True, "layer": None, "exe": "./linux-wallpaperengine"}
i = 0
if old:
    # skip whatever is in front of the options; the program is always ./linux-wallpaperengine
    i = next((j for j, part in enumerate(old) if part.startswith("--")), len(old))
    keep["nofspause"] = "--no-fullscreen-pause" in old
while i < len(old):
    a = old[i]
    nxt = old[i + 1] if i + 1 < len(old) else ""
    if a in ("--screen-root", "-r"):
        cur = nxt; screens.append(nxt); i += 2; continue
    if a in ("--bg", "-b"):
        if cur: mapping[cur] = nxt
        default_bg = nxt; i += 2; continue
    if a in ("--fps", "-f"): keep["fps"] = nxt; i += 2; continue
    if a == "--assets-dir": keep["assets"] = nxt; i += 2; continue
    if a == "--layer": keep["layer"] = nxt; i += 2; continue
    i += 1
for s in screens:
    mapping.setdefault(s, default_bg)

order = monitors or screens
if new_dir != "-":
    for s in order:
        if target in ("all", "") or s == target:
            mapping[s] = new_dir
fallback = new_dir if new_dir != "-" else default_bg
for s in order:
    if not mapping.get(s):
        mapping[s] = fallback
mapping = {s: mapping[s] for s in order if mapping.get(s)}
if not mapping:
    sys.exit(1)

def st(d):
    v = settings.get(os.path.basename(d.rstrip("/")), {})
    out = {k: v.get(k, glob[k]) for k in ("scaling", "volume", "audio", "mouse", "parallax", "particles")}
    out["props"] = v.get("props", {})
    return out

def prop_value(val):
    if isinstance(val, bool):
        return "1" if val else "0"
    if isinstance(val, str) and val.startswith("#") and len(val) == 7:
        r, g, b = (int(val[i:i + 2], 16) / 255 for i in (1, 3, 5))
        return f"{r:.3f} {g:.3f} {b:.3f}"
    return str(val)

cmd = ["./linux-wallpaperengine"]
for s, d in mapping.items():
    cmd += ["--screen-root", s, "--bg", d, "--scaling", st(d)["scaling"]]
shown = [st(d) for d in dict.fromkeys(mapping.values())]
vol = max(x["volume"] for x in shown)
if glob["mute"] or vol <= 0:          # "Mute all wallpapers" in Settings wins
    cmd.append("--silent")
else:
    cmd += ["--volume", str(round(min(100, vol) * 128 / 100))]
if glob["noautomute"]: cmd.append("--noautomute")
if all(not x["audio"] for x in shown): cmd.append("--no-audio-processing")
if all(not x["mouse"] for x in shown): cmd.append("--disable-mouse")
if all(not x["parallax"] for x in shown): cmd.append("--disable-parallax")
if all(not x["particles"] for x in shown): cmd.append("--disable-particles")
props = {}
for x in shown:
    props.update(x["props"])
for name, val in props.items():
    cmd += ["--set-property", f"{name}={prop_value(val)}"]
cmd += ["--fps", str(glob["fps"] or keep["fps"])]
nofspause = (not glob["pauseFullscreen"]) if glob["pauseFullscreen"] is not None else keep["nofspause"]
if nofspause: cmd.append("--no-fullscreen-pause")
if keep["layer"]: cmd += ["--layer", keep["layer"]]
cmd += ["--assets-dir", keep["assets"]]
print("\n".join(cmd))
PYEOF
}

# key the watchdog uses: the wallpaper ids in the command, each once, joined with "+"
args_key() {
    awk 'p=="--bg"{sub(/\/+$/,""); n=split($0,a,"/"); if(!seen[a[n]]++) printf "%s%s", (k?"+":""), a[n]; k=1} {p=$0}' "$1"
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
            "tags": [str(t) for t in (pj.get("tags") or [])][:12],
            "preview": prev_path,
            "added": os.path.getmtime(d),
        })
items.sort(key=lambda i: i["added"], reverse=True)   # newest subscriptions first
print(json.dumps(items))
'
        ;;
    info)
        dir="${2%/}"
        size=$(du -sb "$dir" 2>/dev/null | cut -f1)
        res=""
        file=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("file",""))' "$dir/project.json" 2>/dev/null)
        if [ -n "$file" ] && [ -f "$dir/$file" ] && command -v ffprobe >/dev/null; then
            case "$file" in *.mp4|*.webm|*.mkv|*.avi|*.mov)
                res=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$dir/$file" 2>/dev/null | head -1) ;;
            esac
        fi
        printf '{"size": %s, "resolution": "%s"}\n' "${size:-0}" "$res"
        ;;
    apply)
        dir="${2%/}"
        [ -f "$dir/project.json" ] || { echo "not a wallpaper folder: $dir" >&2; exit 1; }
        build_args "$dir" "${3:-all}" > "$PICKED.tmp" || exit 1
        mv "$PICKED.tmp" "$PICKED"
        args_key "$PICKED" > "$STATE/picked-key"
        start_engine "$PICKED"
        ;;
    reapply)
        [ -s "$ARGS" ] || exit 0
        build_args - all > "$PICKED.tmp" || exit 1
        mv "$PICKED.tmp" "$PICKED"
        args_key "$PICKED" > "$STATE/picked-key"
        start_engine "$PICKED"
        ;;
    restore)
        [ -s "$PICKED" ] && start_engine "$PICKED"
        ;;
    __run)   # removed (it could start itself over and over); kept so an old saved command just stops
        exit 0
        ;;
    boot)
        exec 7>"$STATE/boot.lock"
        flock -n 7 || exit 0
        # A watchdog (and engine) from the previous login can outlive the logout. It can no longer talk
        # to Hyprland and it blocks the new watchdog, so the wallpaper would never come back.
        pkill -f 'wallpaper-watchdog\.sh' 2>/dev/null
        pkill -f "$PATTERN" 2>/dev/null
        rm -f "$STATE/gamemode" "$STATE/gamemode-had-wallpaper" "$STATE/gamemode-profile"   # Game mode does not carry over a login
        # wait until the monitors have settled (same list twice in a row, up to ~10 s)
        prev=""
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            cur=$(hyprctl monitors 2>/dev/null | awk '/^Monitor /{print $2}' | sort | tr '\n' ' ')
            [ -n "$cur" ] && [ "$cur" = "$prev" ] && break
            prev=$cur
            sleep 1
        done
        if [ -s "$ARGS" ]; then
            # last wallpapers per display, rebuilt for the monitors connected right now
            build_args - all > "$PICKED.tmp" && mv "$PICKED.tmp" "$PICKED" && args_key "$PICKED" > "$STATE/picked-key"
        fi
        if [ -s "$PICKED" ]; then
            log "login: starting your wallpaper ($(cat "$STATE/picked-key" 2>/dev/null)) on: $cur"
            for try in 1 2 3; do
                start_engine "$PICKED"
                sleep 5
                pgrep -f "$PATTERN" >/dev/null && break
                log "login: the wallpaper stopped right after starting (try $try), starting it again"
            done
        elif command -v wallpaperx >/dev/null; then
            log "login: no saved wallpaper yet, opening wallpaperx once"
            setsid wallpaperx >/dev/null 2>&1 < /dev/null 7>&- &    # first time ever: let the app start one
        fi
        # the watchdog starts from here, after the old one is gone
        setsid bash "$(dirname "$SELF")/wallpaper-watchdog.sh" >/dev/null 2>&1 < /dev/null 7>&- &
        ;;
    props)
        python3 - "${2%/}/project.json" "$GLOBAL" "${XDG_CACHE_HOME:-$HOME/.cache}/novelknock/translations.json" <<'PYEOF'
import html, json, os, re, sys, urllib.parse, urllib.request
try:
    pj = json.load(open(sys.argv[1], encoding="utf-8", errors="replace"))
except Exception:
    print("[]"); sys.exit(0)
props = (pj.get("general") or {}).get("properties") or {}

def label(text, name):
    t = re.sub(r"<[^>]*>", " ", str(text or ""))
    t = re.sub(r"\s+", " ", html.unescape(t)).strip()
    if t.lower().startswith("ui_"):
        t = re.sub(r"^ui_(browse_properties_)?", "", t, flags=re.I).replace("_", " ").strip().capitalize()
    return t or name

def to_hex(v):
    try:
        parts = [float(x) for x in str(v).replace(",", " ").split()[:3]]
        if max(parts) > 1.0:
            parts = [x / 255 for x in parts]
        return "#" + "".join(f"{round(max(0, min(1, x)) * 255):02X}" for x in parts)
    except Exception:
        return "#FFFFFF"

out = []
for name, p in sorted(props.items(), key=lambda kv: (kv[1] or {}).get("order", 0) if isinstance(kv[1], dict) else 0):
    if not isinstance(p, dict) or name == "schemecolor":   # schemecolor only colors the Windows taskbar
        continue
    kind = str(p.get("type", "")).lower()
    item = {"name": name, "type": kind, "label": label(p.get("text"), name)}
    if kind == "bool":
        item["value"] = bool(p.get("value")) and str(p.get("value")).lower() not in ("0", "false")
    elif kind == "slider":
        item.update(value=float(p.get("value", 0) or 0), min=float(p.get("min", 0) or 0),
                    max=float(p.get("max", 100) or 100), step=float(p.get("step", 0) or 0))
    elif kind == "combo":
        opts = [{"label": label(o.get("label"), str(o.get("value"))), "value": str(o.get("value"))}
                for o in (p.get("options") or []) if isinstance(o, dict)]
        if not opts:
            continue
        item.update(value=str(p.get("value", opts[0]["value"])), options=opts)
    elif kind == "color":
        item["value"] = to_hex(p.get("value", "1 1 1"))
    elif kind == "textinput":
        item["value"] = str(p.get("value", ""))
    elif kind == "text":
        if item["label"] == name:      # pure image or empty text, nothing to show
            continue
    else:
        continue                       # files, folders and groups are not supported here
    out.append(item)

# ---- English labels: keep the English half of bilingual labels, translate the rest once and cache it ----
try:
    translate_on = json.load(open(sys.argv[2])).get("translate", True)
except Exception:
    translate_on = True
CJK_ETC = re.compile(r"[^\x00-\x7F\u00C0-\u024F]")      # anything that is not plain or accented Latin
def needs(t):
    return bool(CJK_ETC.search(t or ""))
def english_half(t):
    latin = CJK_ETC.sub(" ", t)
    latin = re.sub(r"\s+", " ", latin).strip(" /|:-_()[]{}.,")
    words = re.findall(r"[A-Za-z]{3,}", latin)
    return latin if len(words) >= 1 and len("".join(words)) >= 4 else ""
def clean(t):
    return re.sub(r"^[^\w(]+", "", t).strip()

cache_p = sys.argv[3]
try:
    cache = json.load(open(cache_p))
except Exception:
    cache = {}
todo = []
def english(t):
    if not translate_on or not needs(t):
        return t
    half = english_half(t)
    if half:
        return clean(half)
    if t in cache:
        return cache[t]
    todo.append(t)
    return t

labels = []
for item in out:
    labels.append(item["label"])
    for o in item.get("options", []):
        labels.append(o["label"])
for t in labels:
    english(t)
todo = list(dict.fromkeys(todo))
if todo:
    try:
        q = "\n".join(todo)
        url = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=en&dt=t&q=" + urllib.parse.quote(q)
        with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"}), timeout=6) as r:
            data = json.loads(r.read().decode("utf-8"))
        text = "".join(seg[0] for seg in data[0] if seg and seg[0])
        parts = [x.strip() for x in text.split("\n")]
        if len(parts) == len(todo):
            for src, dst in zip(todo, parts):
                if dst:
                    cache[src] = clean(dst) or dst
        os.makedirs(os.path.dirname(cache_p), exist_ok=True)
        json.dump(cache, open(cache_p, "w"), ensure_ascii=False, indent=1)
    except Exception:
        pass                       # offline: keep the original text, try again next time
for item in out:
    orig = item["label"]
    item["label"] = english(orig) if translate_on else orig
    if item["label"] != orig:
        item["original"] = orig
    for o in item.get("options", []):
        o["label"] = english(o["label"]) if translate_on else o["label"]
print(json.dumps(out, ensure_ascii=False))
PYEOF
        ;;
    autorestart)
        if [ "$2" = "off" ]; then touch "$STATE/paused"; else rm -f "$STATE/paused"; fi
        ;;
    *)
        echo "usage: $0 list | info <dir> | props <dir> | apply <dir> [screen] | reapply | restore | boot | autorestart on|off" >&2
        exit 1 ;;
esac
