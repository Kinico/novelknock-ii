# NovelKnock-style Quickshell ii

My end-4 dots-hyprland "ii" Quickshell setup restyled after end-4's old NovelKnock (EWW) rice:
centered pill bar with scrollable pages, "Knock" left sidebar, "System" right sidebar,
bottom music sheet with visualizer and per-app mixer. Colors follow the wallpaper.

Also keeps my Hyprland keybinds (workspace scrolling stays inside each monitor's 1-5 / 6-10)
and custom rules (blur behind the Quickshell panels).

## Install (one line)
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Kinico/novelknock-ii/master/install.sh)"
```
It downloads this repo into `~/Documents/novelknock-ii`, backs up the files it replaces,
installs and locks everything, starts the wallpaper watchdog and restarts Quickshell.
Run the same line again any time to update.

## Scripts
- `install.sh`            the one-line installer above
- `save-novelknock.sh`    copy current files from ~/.config into here and push to GitHub
- `restore-novelknock.sh` put everything back after an update resets it (then locks it)
- `lock-novelknock.sh` / `unlock-novelknock.sh`  lock or unlock the files against changes

## Live wallpaper extras
- `wallpaper-watchdog.sh` restarts linux-wallpaperengine if it dies or a monitor comes back,
  and keeps a separate zoom / X / Y for every wallpaper.
- `wallpaper-colors.sh` matches the theme colors to the wallpaper (toggle and "Next color" in the
  Knock sidebar). It reads a picture of the live wallpaper saved by the patched engine in
  `wallpaperengine/` (rebuild it with `makepkg -si` there), or the wallpaper's preview image.

The list of saved files is in `files.list`.

Based on end-4/dots-hyprland (https://github.com/end-4/dots-hyprland), GPL-3.0.
