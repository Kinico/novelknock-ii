import QtQuick
import Quickshell

import qs.modules.common
import qs.services
import qs.modules.elaina
import qs.modules.ii.background
import qs.modules.ii.cheatsheet
import qs.modules.ii.lock
import qs.modules.ii.mediaControls
import qs.modules.ii.notificationPopup
import qs.modules.ii.onScreenDisplay
import qs.modules.ii.onScreenKeyboard
import qs.modules.ii.overview
import qs.modules.ii.polkit
import qs.modules.ii.regionSelector
import qs.modules.ii.screenTranslator
import qs.modules.ii.sessionScreen
import qs.modules.ii.sidebarLeft
import qs.modules.ii.overlay
import qs.modules.ii.wallpaperSelector

// Elaina: the traveling witch look. Its own bar and Travel Journal (right sidebar);
// everything else (lock screen, overview, popups, left sidebar...) is borrowed from ii.
// Switch with Ctrl+Super+P.
Scope {
    id: family

    // Elaina colors for everything borrowed from ii (left sidebar, lock screen, overview, popups, switches...).
    // While this look is on, these replace the wallpaper colors; switching back to ii puts the wallpaper colors back.
    readonly property var elainaColors: ({
        "background": "#13152a", "surface": "#13152a", "surface_dim": "#13152a", "surface_bright": "#3a3f60",
        "surface_container_lowest": "#0e1020", "surface_container_low": "#181b31", "surface_container": "#1d2038",
        "surface_container_high": "#252945", "surface_container_highest": "#2e3352",
        "on_background": "#ece9f7", "on_surface": "#ece9f7", "on_surface_variant": "#c9c4e0",
        "surface_variant": "#3f4468", "outline": "#8f89b0", "outline_variant": "#3f4468",
        "inverse_surface": "#ece9f7", "inverse_on_surface": "#2a2c44", "inverse_primary": "#6a4fb0",
        "primary": "#c4b2f2", "on_primary": "#2c1f5a", "primary_container": "#6a4fb0", "on_primary_container": "#f1ecff",
        "primary_fixed": "#e6ddff", "primary_fixed_dim": "#c4b2f2", "on_primary_fixed": "#1d1145", "on_primary_fixed_variant": "#4a3888",
        "surface_tint": "#c4b2f2",
        "secondary": "#e8c874", "on_secondary": "#3b2c00", "secondary_container": "#5a4712", "on_secondary_container": "#ffe9b0",
        "secondary_fixed": "#ffe9b0", "secondary_fixed_dim": "#e8c874", "on_secondary_fixed": "#241a00", "on_secondary_fixed_variant": "#54430f",
        "tertiary": "#d8d6e2", "on_tertiary": "#2a2938", "tertiary_container": "#55546a", "on_tertiary_container": "#f0eef8",
        "tertiary_fixed": "#ecebf5", "tertiary_fixed_dim": "#d8d6e2", "on_tertiary_fixed": "#1a1926", "on_tertiary_fixed_variant": "#403f52",
        "error": "#ffb4c0", "on_error": "#67001d", "error_container": "#93102f", "on_error_container": "#ffd9de",
        "scrim": "#000000", "shadow": "#000000"
    })
    property bool applying: false
    function applyPalette() {
        family.applying = true;
        for (const key in family.elainaColors) {
            const m3Key = "m3" + key.replace(/_([a-z])/g, g => g[1].toUpperCase());
            if (m3Key in Appearance.m3colors) Appearance.m3colors[m3Key] = family.elainaColors[key];
        }
        Appearance.m3colors.darkmode = true;
        family.applying = false;
    }
    Component.onCompleted: family.applyPalette()
    Component.onDestruction: MaterialThemeLoader.reapplyTheme()
    // A new wallpaper would bring its own colors back, so put Elaina's back on top
    Connections {
        target: Appearance.m3colors
        function onM3primaryChanged() {
            if (!family.applying && Appearance.m3colors.m3primary.toString() !== Qt.color(family.elainaColors.primary).toString())
                paletteAgain.restart();
        }
    }
    Timer {
        id: paletteAgain
        interval: 250
        onTriggered: family.applyPalette()
    }

    PanelLoader { component: ElainaBar {} }
    PanelLoader { component: ElainaSidebar {} }
    PanelLoader { component: Cheatsheet {} }
    PanelLoader { component: Lock {} }
    PanelLoader { component: NkBottomSheet {} }
    PanelLoader { component: NotificationPopup {} }
    PanelLoader { component: OnScreenDisplay {} }
    PanelLoader { component: OnScreenKeyboard {} }
    PanelLoader { component: Overlay {} }
    PanelLoader { component: Overview {} }
    PanelLoader { component: Polkit {} }
    PanelLoader { component: RegionSelector {} }
    PanelLoader { component: ScreenTranslator {} }
    PanelLoader { component: SessionScreen {} }
    PanelLoader { component: SidebarLeft {} }
    PanelLoader { component: WallpaperSelector {} }
}
