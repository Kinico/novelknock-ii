#!/usr/bin/env bash
# NovelKnock: login screen.
#   bash sddm-setup.sh           -> KDE Plasma's Breeze login screen, with your current wallpaper as background
#   bash sddm-setup.sh breeze    -> same
#   bash sddm-setup.sh <preset>  -> Keyitdev's sddm-astronaut instead: astronaut, black_hole, cyberpunk,
#                                   hyprland_kath, jake_the_dog, japanese_aesthetic, pixel_sakura,
#                                   pixel_sakura_static, post-apocalyptic_hacker, purple_leaves
set -u
THEME="breeze"
for a in "$@"; do
    case "$a" in
        --*) ;;
        *) THEME="$a" ;;
    esac
done
sudo mkdir -p /etc/sddm.conf.d

if [ "$THEME" = breeze ]; then
    echo "Installing SDDM and the Plasma login screen (Breeze)..."
    # the Breeze SDDM theme ships in plasma-desktop; it only runs at the login screen, not in Hyprland
    sudo pacman -S --needed --noconfirm sddm plasma-desktop breeze || { echo "pacman failed."; exit 1; }
    B=/usr/share/sddm/themes/breeze
    # Use the rice wallpaper as the login background (theme.conf.user is not touched by updates)
    wp="$(python3 -c "import json,os;print(json.load(open(os.path.expanduser('~/.config/illogical-impulse/config.json'))).get('background',{}).get('wallpaperPath',''))" 2>/dev/null)"
    if [ -n "$wp" ] && [ -f "$wp" ]; then
        ext="${wp##*.}"
        sudo cp "$wp" "$B/nk-background.$ext"
        printf '[General]\nbackground=nk-background.%s\ntype=image\n' "$ext" | sudo tee "$B/theme.conf.user" >/dev/null
        echo "Login background: $wp"
    else
        echo "No wallpaper picked yet, keeping the Plasma background. Run this again after you pick one (Super+Z)."
    fi
    printf '[Theme]\nCurrent=breeze\nCursorTheme=breeze_cursors\n' | sudo tee /etc/sddm.conf.d/zz-novelknock-theme.conf >/dev/null
    PREVIEW="$B"
else
    T=/usr/share/sddm/themes/sddm-astronaut-theme
    echo "Installing SDDM and the sddm-astronaut theme..."
    sudo pacman -S --needed --noconfirm sddm qt6-svg qt6-virtualkeyboard qt6-multimedia-ffmpeg git || { echo "pacman failed."; exit 1; }
    # straight from its GitHub (the AUR package resets the chosen preset on every update)
    if [ -d "$T/.git" ]; then
        sudo git -C "$T" pull --ff-only || true
    else
        sudo rm -rf "$T"
        sudo git clone -b master --depth 1 https://github.com/keyitdev/sddm-astronaut-theme.git "$T" || { echo "Could not download the theme."; exit 1; }
    fi
    sudo cp -r "$T"/Fonts/* /usr/share/fonts/ 2>/dev/null
    [ -f "$T/Themes/$THEME.conf" ] || { echo "No preset called $THEME, using pixel_sakura_static."; THEME=pixel_sakura_static; }
    sudo sed -i "s|^ConfigFile=.*|ConfigFile=Themes/$THEME.conf|" "$T/metadata.desktop"
    printf '[Theme]\nCurrent=sddm-astronaut-theme\n\n[General]\nInputMethod=qtvirtualkeyboard\n' | sudo tee /etc/sddm.conf.d/zz-novelknock-theme.conf >/dev/null
    PREVIEW="$T"
fi

# Win over other theme settings: conf.d files load in name order (zz- goes last),
# and /etc/sddm.conf beats all of them, so its Current= line is changed too.
sudo rm -f /etc/sddm.conf.d/novelknock-theme.conf
want_theme="$(sed -n 's/^Current=//p' /etc/sddm.conf.d/zz-novelknock-theme.conf)"
for f in /etc/sddm.conf /etc/sddm.conf.d/*.conf; do
    [ -f "$f" ] || continue
    [ "$f" = /etc/sddm.conf.d/zz-novelknock-theme.conf ] && continue
    if grep -q '^Current=' "$f"; then
        echo "Overriding the theme set in $f"
        sudo sed -i "s|^Current=.*|Current=$want_theme|" "$f"
    fi
done

# Use SDDM as the login screen, unless another one is already set up
cur="$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null)"
if [ -z "$cur" ] || [ ! -e "$cur" ]; then
    sudo systemctl enable sddm.service
elif [ "$(basename "$cur")" != "sddm.service" ]; then
    echo "Note: your login screen is $(basename "$cur" .service), not SDDM. To switch:"
    echo "  sudo systemctl disable $(basename "$cur") && sudo systemctl enable sddm"
fi
echo "Login screen set ($THEME). You will see it next time you log out or reboot."
echo "Preview now: sddm-greeter-qt6 --test-mode --theme $PREVIEW"
