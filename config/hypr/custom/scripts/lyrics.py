#!/usr/bin/env python3
"""Synced lyrics for the fullscreen music view, from LRCLIB (https://lrclib.net, free, no account).
   lyrics.py "<title>" "<artist>" [duration seconds]
Prints JSON: {"synced": [[seconds, "line"], ...], "plain": "text", "found": true, "title": "...", "artist": "..."}
Found lyrics are cached in ~/.cache/novelknock/lyrics, so each song is only looked up once."""
import hashlib, json, os, re, sys, urllib.parse, urllib.request

BASE = os.environ.get("NK_LRCLIB_BASE", "https://lrclib.net")
CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "novelknock", "lyrics")
UA = "novelknock-ii lyrics (https://github.com/Kinico/novelknock-ii)"
NOISE = r"official|video|audio|lyrics?|visuali[sz]er|mv|m/v|hd|hq|4k|remaster(ed)?|live|full|version|explicit|clean|with lyrics|music"


def clean_title(t):
    t = re.sub(r"[\(\[\{【][^\)\]\}】]*(%s)[^\)\]\}】]*[\)\]\}】]" % NOISE, " ", t, flags=re.I)
    t = re.sub(r"\s[\|｜].*$", "", t)
    t = re.sub(r"\s+(official|lyric|music)\s+(video|audio|visualizer).*$", "", t, flags=re.I)
    return re.sub(r"\s+", " ", t).strip(" -–—")


def clean_artist(a):
    a = re.sub(r"\s*-\s*topic$", "", a, flags=re.I)
    a = re.sub(r"\s*(vevo|official)$", "", a, flags=re.I)
    return a.strip()


def fetch(path, params):
    url = f"{BASE}{path}?{urllib.parse.urlencode(params)}"
    try:
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=8) as r:
            return json.loads(r.read().decode("utf-8"))
    except Exception:
        return None


def parse_lrc(text):
    out = []
    for line in (text or "").splitlines():
        stamps = re.findall(r"\[(\d+):(\d+(?:\.\d+)?)\]", line)
        words = re.sub(r"\[[^\]]*\]", "", line).strip()
        for m, s in stamps:
            out.append([round(int(m) * 60 + float(s), 2), words])
    out.sort(key=lambda x: x[0])
    return out


def best(results, duration):
    results = [r for r in (results or []) if isinstance(r, dict) and (r.get("syncedLyrics") or r.get("plainLyrics"))]
    if not results:
        return None
    def score(r):
        gap = abs((r.get("duration") or 0) - duration) if duration else 0
        return (0 if r.get("syncedLyrics") else 1, gap)
    return min(results, key=score)


def lookup(title, artist, duration):
    tries = []
    if artist:
        if duration:
            tries.append(("/api/get", {"track_name": title, "artist_name": artist, "duration": int(duration)}))
        tries.append(("/api/search", {"track_name": title, "artist_name": artist}))
    if " - " in title:                       # "Artist - Song" titles, common for browser players
        a2, t2 = [p.strip() for p in title.split(" - ", 1)]
        tries.append(("/api/search", {"track_name": t2, "artist_name": a2}))
        tries.append(("/api/search", {"track_name": a2, "artist_name": t2}))
    tries.append(("/api/search", {"q": f"{title} {artist}".strip()}))
    tries.append(("/api/search", {"track_name": title}))
    for path, params in tries:
        data = fetch(path, params)
        hit = data if (path == "/api/get" and isinstance(data, dict) and (data.get("syncedLyrics") or data.get("plainLyrics"))) \
            else best(data if isinstance(data, list) else [], duration)
        if hit:
            return hit
    return None


def main():
    title = clean_title(sys.argv[1] if len(sys.argv) > 1 else "")
    artist = clean_artist(sys.argv[2] if len(sys.argv) > 2 else "")
    try:
        duration = float(sys.argv[3]) if len(sys.argv) > 3 else 0
    except ValueError:
        duration = 0
    if not title:
        print(json.dumps({"found": False, "synced": [], "plain": ""}))
        return
    key = hashlib.sha1(f"{artist.lower()}|{title.lower()}".encode()).hexdigest()
    path = os.path.join(CACHE, key + ".json")
    try:
        print(open(path, encoding="utf-8").read())
        return
    except OSError:
        pass
    hit = lookup(title, artist, duration)
    if not hit:
        print(json.dumps({"found": False, "synced": [], "plain": ""}))
        return
    out = {"found": True, "synced": parse_lrc(hit.get("syncedLyrics")), "plain": hit.get("plainLyrics") or "",
           "title": hit.get("trackName") or title, "artist": hit.get("artistName") or artist}
    text = json.dumps(out, ensure_ascii=False)
    try:
        os.makedirs(CACHE, exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)
    except OSError:
        pass
    print(text)


main()
