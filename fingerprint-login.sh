#!/usr/bin/env bash
# NovelKnock: phone-style fingerprint at the SDDM login screen.
# The login screen starts the fingerprint check by itself, so you just touch the sensor, no keys.
# Typing your password still works and is checked first.
#   bash fingerprint-login.sh          turn it on (needs a finger enrolled: fprintd-enroll)
#   bash fingerprint-login.sh --off    back to the normal Breeze login screen and PAM file
set -u
SRC=/usr/share/sddm/themes/breeze
DST=/usr/share/sddm/themes/breeze-finger
PAM=/etc/pam.d/sddm
CONF=/etc/sddm.conf.d/zz-novelknock-theme.conf

if [ "${1:-}" = "--off" ]; then
    [ -f "$PAM.nk-backup" ] && sudo cp "$PAM.nk-backup" "$PAM"
    for f in /etc/sddm.conf /etc/sddm.conf.d/*.conf; do
        [ -f "$f" ] && sudo sed -i 's|^Current=breeze-finger$|Current=breeze|' "$f"
    done
    sudo rm -f /etc/sddm.conf.d/.nk-finger
    echo "Fingerprint login screen off. Back to normal Breeze."
    exit 0
fi

command -v fprintd-list >/dev/null || { echo "Install fprintd first: sudo pacman -S fprintd"; exit 1; }
fprintd-list "$USER" 2>/dev/null | grep -q "Fingerprints for user" || { echo "No finger enrolled yet. Run: fprintd-enroll"; exit 1; }
[ -f "$SRC/Main.qml" ] || { echo "Breeze login theme not found. Run: bash sddm-setup.sh"; exit 1; }

# 1. Copy of Breeze that starts the fingerprint check on its own (a copy, so Plasma updates don't undo it)
sudo rm -rf "$DST"
sudo cp -r "$SRC" "$DST"
sudo sed -i 's/^Theme-Id=breeze$/Theme-Id=breeze-finger/' "$DST/metadata.desktop"
sudo python3 - "$DST/Main.qml" "$USER" <<'PY'
import sys
p, user = sys.argv[1], sys.argv[2]
s = open(p).read()
marker = "    Connections {\n        target: sddm\n"
assert marker in s, "Breeze Main.qml changed, cannot patch"
timer = '''    // NovelKnock: start the fingerprint check by itself, like a phone.
    // An empty password goes past the password check (PAM) to the fingerprint reader.
    property bool nkFingerPending: false
    Timer {
        id: nkFingerTimer
        interval: 1200
        running: true
        repeat: false
        onTriggered: {
            root.nkFingerPending = true
            root.notificationMessage = "Touch the fingerprint sensor, or type your password"
            sddm.login(userModel.lastUser || "%s", "", sessionButton.currentIndex)
        }
    }

''' % user
s = s.replace(marker, timer + marker, 1)
old = '''        function onLoginFailed() {
            notificationMessage = i18ndc("plasma-desktop-sddm-theme", "@info:status", "Login Failed")'''
new = '''        function onLoginFailed() {
            if (root.nkFingerPending) {
                // fingerprint timed out or did not match: quietly hand over to the password box
                root.nkFingerPending = false
                notificationMessage = "Fingerprint not read, type your password"
                footer.enabled = true
                mainStack.enabled = true
                userListComponent.userList.opacity = 1
                return
            }
            notificationMessage = i18ndc("plasma-desktop-sddm-theme", "@info:status", "Login Failed")'''
assert old in s, "Breeze onLoginFailed changed, cannot patch"
s = s.replace(old, new, 1)
open(p, "w").write(s)
PY
[ $? -eq 0 ] || { echo "Could not patch the theme."; exit 1; }

# 2. PAM: typed password checked first (instant), an empty one falls through to the fingerprint (10s wait)
[ -f "$PAM.nk-backup" ] || sudo cp "$PAM" "$PAM.nk-backup"
sudo cp "$PAM.nk-backup" "$PAM"
sudo sed -i '1a auth       [success=done default=ignore]  pam_unix.so\nauth       sufficient   pam_fprintd.so timeout=10' "$PAM"

# 3. Use it
sudo mkdir -p /etc/sddm.conf.d
if [ -f "$CONF" ]; then
    sudo sed -i 's|^Current=.*|Current=breeze-finger|' "$CONF"
else
    printf '[Theme]\nCurrent=breeze-finger\nCursorTheme=breeze_cursors\n' | sudo tee "$CONF" >/dev/null
fi
# /etc/sddm.conf beats conf.d, so any other theme line is switched too
for f in /etc/sddm.conf /etc/sddm.conf.d/*.conf; do
    [ -f "$f" ] && grep -q '^Current=' "$f" && sudo sed -i 's|^Current=.*|Current=breeze-finger|' "$f"
done
sudo rm -f /etc/sddm.conf.d/zz-autologin.conf
sudo touch /etc/sddm.conf.d/.nk-finger
echo "Done. Reboot: the login screen starts the fingerprint check by itself, just touch the sensor."
echo "Undo any time: bash fingerprint-login.sh --off"
