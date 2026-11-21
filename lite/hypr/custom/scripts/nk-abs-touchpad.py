#!/usr/bin/env python3
# NovelKnock lite: absolute touchpad, like a drawing tablet (great for osu!).
# Where you touch on the touchpad is where the cursor goes on the screen.
# It takes the touchpad over while it runs (normal touchpad gestures pause), and gives it back when stopped.
#   nk-abs-touchpad.py            run (the Super+A toggle starts and stops it)
# Needs python-evdev, the "input" group and /dev/uinput access (the lite installer sets these up).
import os, signal, sys
try:
    import evdev
    from evdev import ecodes as e, UInput, AbsInfo
except ImportError:
    sys.exit("python-evdev missing: sudo pacman -S python-evdev")

# Use only the middle part of the touchpad edges (0.0 = whole pad). A small margin makes corners easier to reach.
MARGIN = float(os.environ.get("NK_ABS_MARGIN", "0.04"))

def find_touchpad():
    for path in evdev.list_devices():
        d = evdev.InputDevice(path)
        caps = d.capabilities()
        keys = caps.get(e.EV_KEY, [])
        absc = [a if isinstance(a, int) else a[0] for a in caps.get(e.EV_ABS, [])]
        # a touchpad: finger tool, absolute X, and it is a pointer (touchscreens are "direct" instead)
        if e.BTN_TOOL_FINGER in keys and e.ABS_X in absc and e.INPUT_PROP_DIRECT not in d.input_props():
            return d
        d.close()
    return None

pad = find_touchpad()
if not pad:
    sys.exit("No touchpad found")

ax = pad.absinfo(e.ABS_X)
ay = pad.absinfo(e.ABS_Y)
x0 = ax.min + (ax.max - ax.min) * MARGIN
x1 = ax.max - (ax.max - ax.min) * MARGIN
y0 = ay.min + (ay.max - ay.min) * MARGIN
y1 = ay.max - (ay.max - ay.min) * MARGIN
OUT = 32767

# Looks like a VM "tablet" mouse to the system: absolute position + normal buttons
ui = UInput({
    e.EV_KEY: [e.BTN_LEFT, e.BTN_RIGHT, e.BTN_MIDDLE],
    e.EV_ABS: [(e.ABS_X, AbsInfo(0, 0, OUT, 0, 0, 0)), (e.ABS_Y, AbsInfo(0, 0, OUT, 0, 0, 0))],
}, name="NovelKnock absolute touchpad")

def scale(v, lo, hi):
    return int(max(0, min(OUT, (v - lo) / max(1, hi - lo) * OUT)))

def stop(*_):
    try:
        pad.ungrab()
    except Exception:
        pass
    ui.close()
    sys.exit(0)

signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGINT, stop)

pad.grab()   # the touchpad now only talks to this script
touching = False
tx = ty = None
for ev in pad.read_loop():
    if ev.type == e.EV_KEY:
        if ev.code == e.BTN_TOUCH:
            touching = ev.value == 1
        elif ev.code in (e.BTN_LEFT, e.BTN_RIGHT, e.BTN_MIDDLE):   # physical click buttons still click
            ui.write(e.EV_KEY, ev.code, ev.value)
            ui.syn()
    elif ev.type == e.EV_ABS and touching:
        if ev.code == e.ABS_X:
            tx = scale(ev.value, x0, x1)
        elif ev.code == e.ABS_Y:
            ty = scale(ev.value, y0, y1)
    elif ev.type == e.EV_SYN and touching and (tx is not None or ty is not None):
        if tx is not None:
            ui.write(e.EV_ABS, e.ABS_X, tx)
        if ty is not None:
            ui.write(e.EV_ABS, e.ABS_Y, ty)
        ui.syn()
        tx = ty = None
