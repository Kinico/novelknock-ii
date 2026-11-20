#!/usr/bin/env python3
"""NovelKnock: work around linux-wallpaperengine not hiding things inside hidden groups.

In Wallpaper Engine, switching off a group (a dock, a clock "component", ...) hides everything in
it. linux-wallpaperengine only hides the group itself, so its contents keep showing (empty dock
slots as white squares, clocks that were switched off...). Before the engine starts, this writes a
scene.json next to the wallpaper's scene.pkg (loose files win over the package) in which every
layer inside a hidden group is hidden itself, using the wallpaper's current options.

Also hides layers listed in ~/.config/linux-wallpaperengine/hide-objects.json
  { "<workshop id>": [<layer id>, ...] }   (for things with no option, like broken watermark text)

Usage: scene-fix.py <the engine's arguments>   (reads every --bg and --set-property name=value)
It is rebuilt from scene.pkg every time, so a wallpaper update or an option change is picked up.
"""
import json, os, struct, sys

HIDE = os.path.expanduser("~/.config/linux-wallpaperengine/hide-objects.json")
MARK = "nk_scene_fix"

def read_pkg_scene(pkg):
    with open(pkg, "rb") as f:
        d = f.read()
    o = 0
    def u32():
        nonlocal o
        v = struct.unpack_from("<I", d, o)[0]
        o += 4
        return v
    n = u32(); o += n
    entries = []
    for _ in range(u32()):
        ln = u32(); name = d[o:o + ln].decode("utf-8", "replace"); o += ln
        entries.append((name, u32(), u32()))
    for name, off, size in entries:
        if name == "scene.json":
            return d[o + off:o + off + size]
    return None

def truthy(v):
    if isinstance(v, bool):
        return v
    if isinstance(v, (int, float)):
        return v != 0
    return str(v).strip().lower() not in ("", "0", "false", "null", "none")

def own_visible(obj, props):
    v = obj.get("visible", True)
    if isinstance(v, bool):
        return v
    if not isinstance(v, dict):
        return True
    user = v.get("user")
    if user is None:
        return truthy(v.get("value", True))  # scripted or plain value: keep its default
    if isinstance(user, str):
        return truthy(props[user]) if user in props else truthy(v.get("value", True))
    if isinstance(user, dict) and "name" in user:
        name = user["name"]
        if name not in props:
            return truthy(v.get("value", True))
        return str(props[name]).strip() == str(user.get("condition", "")).strip()
    return True

def fix(wall_dir, overrides, hide_ids):
    pkg = os.path.join(wall_dir, "scene.pkg")
    out = os.path.join(wall_dir, "scene.json")
    if not os.path.isfile(pkg):
        return  # loose wallpaper: its scene.json is the original, never touch it
    raw = read_pkg_scene(pkg)
    if raw is None:
        return
    scene = json.loads(raw)
    try:
        with open(os.path.join(wall_dir, "project.json"), encoding="utf-8") as f:
            pj = json.load(f)
        defaults = {k: (p or {}).get("value") for k, p in ((pj.get("general") or {}).get("properties") or {}).items()}
    except Exception:
        defaults = {}
    props = dict(defaults)
    props.update(overrides)

    objs = {o.get("id"): o for o in scene.get("objects", []) if isinstance(o, dict)}
    memo = {}
    def effective(oid, depth=0):
        if oid in memo:
            return memo[oid]
        o = objs.get(oid)
        if o is None or depth > 64:
            return True
        vis = own_visible(o, props)
        parent = o.get("parent")
        try:
            parent = int(parent) if parent is not None else None
        except (TypeError, ValueError):
            parent = None
        if vis and parent is not None and parent in objs:
            vis = effective(parent, depth + 1)
        memo[oid] = vis
        return vis

    changed = 0
    for oid, o in objs.items():
        if oid in hide_ids or (own_visible(o, props) and not effective(oid)):
            o["visible"] = False
            changed += 1

    already = False
    if os.path.isfile(out):
        try:
            with open(out, "rb") as f:
                cur = f.read()
            already = cur == raw or MARK in json.loads(cur)  # ours, or an untouched copy of the original
        except Exception:
            already = False
        if not already:
            return  # a scene.json we did not write: leave it alone
    if changed:
        scene[MARK] = changed
        tmp = out + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(scene, f, ensure_ascii=False)
        os.replace(tmp, out)
        print(f"scene-fix: {os.path.basename(wall_dir)}: hid {changed} layers", file=sys.stderr)
    elif already:
        with open(out, "wb") as f:  # nothing to fix any more: put the original back
            f.write(raw)

def main(argv):
    dirs, overrides = [], {}
    for i, a in enumerate(argv):
        if a == "--bg" and i + 1 < len(argv):
            dirs.append(argv[i + 1].rstrip("/"))
        elif a == "--set-property" and i + 1 < len(argv) and "=" in argv[i + 1]:
            k, v = argv[i + 1].split("=", 1)
            overrides[k] = v
    try:
        with open(HIDE, encoding="utf-8") as f:
            hides = json.load(f)
    except Exception:
        hides = {}
    for d in dict.fromkeys(dirs):
        try:
            fix(d, overrides, set(int(x) for x in hides.get(os.path.basename(d), [])))
        except Exception as e:
            print(f"scene-fix: {d}: {e}", file=sys.stderr)

main(sys.argv[1:])
