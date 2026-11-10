#!/usr/bin/env bash
# Puts the NovelKnock-style ii files back into ~/.config/quickshell/ii
# Use this if an update ever overwrites them.
set -e
SRC="$(cd "$(dirname "$0")" && pwd)/ii"
DEST="$HOME/.config/quickshell/ii"
[ -d "$DEST" ] || { echo "No ii config found at $DEST"; exit 1; }
cp -v "$SRC/modules/ii/bar/NkBarContent.qml"                  "$DEST/modules/ii/bar/"
cp -v "$SRC/modules/ii/bar/Bar.qml"                           "$DEST/modules/ii/bar/"
cp -v "$SRC/modules/ii/sidebarLeft/NkSidebarLeftContent.qml"  "$DEST/modules/ii/sidebarLeft/"
cp -v "$SRC/modules/ii/sidebarLeft/SidebarLeft.qml"           "$DEST/modules/ii/sidebarLeft/"
cp -v "$SRC/modules/ii/sidebarRight/NkSidebarRightContent.qml" "$DEST/modules/ii/sidebarRight/"
cp -v "$SRC/modules/ii/sidebarRight/SidebarRight.qml"         "$DEST/modules/ii/sidebarRight/"
cp -v "$SRC/modules/ii/mediaControls/NkBottomSheet.qml"       "$DEST/modules/ii/mediaControls/"
cp -v "$SRC/panelFamilies/IllogicalImpulseFamily.qml"         "$DEST/panelFamilies/"
cp -v "$SRC/modules/common/Appearance.qml"                    "$DEST/modules/common/"
echo "Done. Restart Quickshell with: pkill qs; qs -c ii"
