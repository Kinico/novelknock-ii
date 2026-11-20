#!/usr/bin/env python3
# NovelKnock lite: two-finger swipe left/right on the touchpad switches workspace.
# Linux never reports 2 fingers as a swipe gesture (only as scrolling), and Hyprland's scroll binds
# ignore touchpad fingers, so this reads the touchpad straight from libinput and adds up each swipe.
# Needs: libinput (CachyOS has it) and your user in the "input" group (the installer does that).
import json, os, re, subprocess, sys, time

THRESHOLD = 40.0   # how far you swipe sideways before it switches (bigger = longer swipe)
INVERT = os.environ.get("NK_SWIPE_INVERT", "0") == "1"   # flip the direction if it feels backwards

pat = re.compile(r"POINTER_SCROLL_FINGER.*?vert\s+(-?[\d.]+)/[^\s]*\s+horiz\s+(-?[\d.]+)/")

def shown():
    # same number of workspaces as the bar (Settings > Bar > Workspaces shown)
    try:
        cfg = json.load(open(os.path.expanduser("~/.config/illogical-impulse/config.json")))
        return max(1, int(cfg["bar"]["workspaces"]["shown"]))
    except Exception:
        return 5

def switch(step):
    try:
        cur = json.loads(subprocess.run(["hyprctl", "activeworkspace", "-j"],
                                        capture_output=True, text=True).stdout)["id"]
    except Exception:
        return
    n = shown()
    first = (cur - 1) // n * n + 1
    target = max(first, min(first + n - 1, cur + step))   # stays inside the bar's workspaces, like the bar's scroll
    if target != cur:
        subprocess.run(["hyprctl", "dispatch", f"hl.dsp.focus({{workspace = {target}}})"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def run():
    p = subprocess.Popen(["libinput", "debug-events"], stdout=subprocess.PIPE,
                         stderr=subprocess.DEVNULL, text=True, bufsize=1)
    total_h = total_v = 0.0
    fired = False
    for line in p.stdout:
        m = pat.search(line)
        if not m:
            continue
        v, h = float(m.group(1)), float(m.group(2))
        if v == 0.0 and h == 0.0:          # fingers lifted: the swipe is over
            total_h = total_v = 0.0
            fired = False
            continue
        total_h += h
        total_v += abs(v)
        # one switch per swipe, and only for mostly-sideways swipes
        if not fired and abs(total_h) >= THRESHOLD and abs(total_h) > 2 * total_v:
            step = 1 if total_h > 0 else -1
            switch(-step if INVERT else step)
            fired = True
    return p.wait()

while True:          # if libinput stops (suspend, touchpad reset), start it again
    run()
    time.sleep(2)
