import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common.models.hyprland
import qs.services

QuickToggleModel {
    id: root
    name: Translation.tr("Game mode")
    toggled: !confOpt.value
    icon: "gamepad"
    property bool prevSilent: false // NovelKnock: notification state to put back
    // NovelKnock: also stop the live wallpaper and set the CPU to performance (game-mode.sh)
    function extras(state) {
        Quickshell.execDetached(["bash", "-c", `exec bash "$HOME/.config/hypr/custom/scripts/game-mode.sh" ${state}`]);
    }

    mainAction: () => {
        root.toggled = !root.toggled;
        if (root.toggled) {
            HyprlandConfig.setMany({
                "animations:enabled": 0,
                "decoration:shadow:enabled": 0,
                "decoration:blur:enabled": 0,
                "general:gaps_in": 0,
                "general:gaps_out": 0,
                "general:border_size": 1,
                "decoration:rounding": 0,
                "general:allow_tearing": 1
            });
            root.prevSilent = Notifications.silent;
            Notifications.silent = true;
            root.extras("on");
        } else {
            HyprlandConfig.resetMany([ //
                "animations:enabled", //
                "decoration:shadow:enabled", //
                "decoration:blur:enabled", //
                "general:gaps_in", //
                "general:gaps_out", //
                "general:border_size", //
                "decoration:rounding", //
                "general:allow_tearing", //
            ]);
            Notifications.silent = root.prevSilent;
            root.extras("off");
        }
    }

    HyprlandConfigOption {
        id: confOpt
        key: "animations:enabled"
    }

    tooltipText: Translation.tr("Game mode")
}
