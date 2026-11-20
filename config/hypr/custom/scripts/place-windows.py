#!/usr/bin/env python3
"""NovelKnock: open new windows where they were launched, not where the cursor happens to be.

Hyprland puts a new window on the monitor the cursor is on when the window appears. Games and
slow apps can take a while, so if you moved the mouse to the other monitor in the meantime the
window lands there. This helper listens to Hyprland and moves each new window (silently) to:

 1. the workspace of the window that launched it: a game started from Steam or Twintail Launcher
    goes to where the Steam / Twintail window is, a dialog or second window of an app goes to
    where you were using that app (the most recently focused related window wins);
 2. otherwise, for something started in the last minute (app launcher, keybind, terminal), the
    workspace that was focused at the moment it was started.
Windows it can't place are left alone. Log: ~/.local/state/place-windows.log
"""
import json, os, socket, subprocess, sys, time, fcntl

STATE = os.path.expanduser("~/.local/state")
LOG = os.path.join(STATE, "place-windows.log")
os.makedirs(STATE, exist_ok=True)

# one copy per Hyprland session
lock = open(os.path.join(STATE, "place-windows.lock"), "w")
try:
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
except OSError:
    sys.exit(0)

def log(msg):
    try:
        with open(LOG, "a") as f:
            f.write(time.strftime("%Y-%m-%d %H:%M:%S ") + msg + "\n")
        if os.path.getsize(LOG) > 200_000:
            os.replace(LOG, LOG + ".old")
    except OSError:
        pass

def hypr(*args):
    try:
        return subprocess.run(["hyprctl", *args], capture_output=True, text=True, timeout=3).stdout
    except Exception:
        return ""

def hypr_json(what):
    try:
        return json.loads(hypr(what, "-j") or "null")
    except ValueError:
        return None

def now():
    return time.clock_gettime(time.CLOCK_BOOTTIME)

HZ = os.sysconf("SC_CLK_TCK")
INTENT = os.path.join(STATE, "place-windows.intent")  # written by the app search when you open something
last_intent = 0

def proc_info(pid):
    """(parent pid, process name, start time in seconds since boot) or None."""
    try:
        with open(f"/proc/{pid}/stat") as f:
            data = f.read()
        name = data[data.index("(") + 1:data.rindex(")")]
        rest = data[data.rindex(")") + 2:].split()
        return int(rest[1]), name, int(rest[19]) / HZ
    except (OSError, ValueError, IndexError):
        return None

# processes that are "the desktop", not a launcher: stop climbing the tree here
STOP = {"Hyprland", "hyprland", "qs", "quickshell", ".quickshell-wra", "noctalia-qs", "systemd", "uwsm", "start-hyprland",
        "dbus-daemon", "dbus-broker", "gnome-keyring-d", "xdg-desktop-por", "sddm", "sddm-helper", "greetd",
        "login", "init", "kded6"}

def ancestors(pid):
    """pid and its parents up to (not including) the desktop."""
    chain = []
    seen = set()
    while pid and pid > 1 and pid not in seen:
        seen.add(pid)
        info = proc_info(pid)
        if not info or info[1] in STOP:
            break
        chain.append(pid)
        pid = info[0]
    return chain

def descendant_of(pid, root, cache):
    if pid in cache:
        return root in cache[pid]
    cache[pid] = set(ancestors(pid))
    return root in cache[pid]

# history of which workspace was focused when, for "where was I when I launched it"
history = []  # [(time, workspace id)]

def note_focus(ws):
    try:
        ws = int(ws)
    except (TypeError, ValueError):
        return
    if ws <= 0:  # special workspaces
        return
    if not history or history[-1][1] != ws:
        history.append((now(), ws))
        del history[:-500]

def focused_at(t):
    ws = None
    for ts, w in history:
        if ts <= t:
            ws = w
        else:
            break
    return ws

def place(addr):
    clients = hypr_json("clients") or []
    win = next((c for c in clients if c.get("address") == addr), None)
    if not win:
        return
    ws_now = win.get("workspace", {}).get("id", 0)
    if ws_now <= 0 or win.get("pid", 0) <= 0:
        return
    pid = win["pid"]
    chain = ancestors(pid)
    target, why = None, ""

    # 1. a related window: same process, or windows of the nearest ancestor that has any
    others = [c for c in clients if c.get("address") != addr and c.get("pid", 0) > 0
              and c.get("workspace", {}).get("id", 0) > 0 and not c.get("hidden")]
    cache = {}
    for anc in chain:
        related = [c for c in others if c["pid"] == anc or descendant_of(c["pid"], anc, cache)]
        if related:
            best = min(related, key=lambda c: c.get("focusHistoryID", 1 << 30))
            target = best["workspace"]["id"]
            why = f"launched from {best.get('class', '?')}"
            break

    # 2. opened from the app search in the last 30 s (also covers apps already running in the background)
    global last_intent
    if target is None:
        try:
            with open(INTENT) as f:
                stamp = float(f.read().strip())
        except (OSError, ValueError):
            stamp = 0
        age = time.time() - stamp
        if stamp and stamp != last_intent and 0 <= age < 30:
            last_intent = stamp
            target = focused_at(now() - age)
            why = "opened from the app search"

    # 3. started recently (keybind, terminal...): the workspace focused when it was started
    if target is None and chain:
        start = min((proc_info(p) or (0, "", now()))[2] for p in chain)
        if now() - start < 60:
            target = focused_at(start)
            why = "workspace focused at launch"

    name = f"{win.get('class', '?')} [{win.get('title', '')[:40]}]"
    if target and target != ws_now:
        hypr("dispatch", f'hl.dsp.window.move({{ workspace = "{target}", follow = false, window = "address:{addr}" }})')
        log(f"{name}: {ws_now} -> {target} ({why})")
    elif target:
        log(f"{name}: already on {ws_now} ({why})")
    else:
        log(f"{name}: left on {ws_now} (no launcher found)")

def main():
    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    run = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    if not sig:
        log("not inside Hyprland, exiting")
        return
    path = os.path.join(run, "hypr", sig, ".socket2.sock")
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    for _ in range(30):
        try:
            s.connect(path)
            break
        except OSError:
            time.sleep(1)
    else:
        log(f"could not connect to {path}")
        return
    aw = hypr_json("activeworkspace")
    if aw:
        note_focus(aw.get("id"))
    log("started")
    buf = b""
    while True:
        data = s.recv(65536)
        if not data:  # Hyprland is gone
            log("Hyprland closed, exiting")
            return
        buf += data
        while b"\n" in buf:
            line, buf = buf.split(b"\n", 1)
            ev, _, arg = line.decode("utf-8", "replace").partition(">>")
            try:
                if ev == "workspacev2":
                    note_focus(arg.split(",", 1)[0])
                elif ev == "focusedmonv2":
                    note_focus(arg.rsplit(",", 1)[-1])
                elif ev == "openwindow":
                    place("0x" + arg.split(",", 1)[0])
            except Exception as e:  # never die on one bad event
                log(f"error on {ev}: {e}")

main()
