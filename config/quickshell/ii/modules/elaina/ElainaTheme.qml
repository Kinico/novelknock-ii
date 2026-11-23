pragma Singleton
import QtQuick
import Quickshell

// Elaina "traveling witch" palette: navy robe, white blouse, lavender ribbon, silver hair, gold star.
// Fixed colors on purpose, so the look stays the same whatever the wallpaper is.
Singleton {
    readonly property color robe: "#171a30"          // deepest navy
    readonly property color robeSoft: "#222744"      // panels
    readonly property color robeLine: "#3a4068"      // borders, dotted route
    readonly property color blouse: "#f4efe3"        // parchment white
    readonly property color blouseInk: "#2a2846"     // text on parchment
    readonly property color lavender: "#b9a6ea"
    readonly property color ribbon: "#7f5cc2"        // deeper purple
    readonly property color silver: "#d8d6e2"
    readonly property color gold: "#e8c874"
    readonly property color text: "#ece9f7"
    readonly property color muted: "#9c97b9"
    readonly property color danger: "#e58b9b"

    readonly property color barFill: Qt.rgba(0.09, 0.10, 0.19, 0.80)
    readonly property color cardFill: Qt.rgba(0.13, 0.15, 0.27, 0.85)

    readonly property string serif: "Noto Serif"
    readonly property string sans: "Lexend"

    readonly property real radius: 14
}
