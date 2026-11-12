pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.overlay

// NovelKnock: in-game performance overlay (MangoHud) with live GPU stats. Super+F12 toggles it in game.
StyledOverlayWidget {
    id: root
    title: "Performance"
    minimumWidth: 380
    minimumHeight: 360

    readonly property string script: `${FileUtils.trimFileProtocol(Directories.config)}/hypr/custom/scripts/perf-hud.sh`
    property var hud: ({ shown: false, position: "top-left", items: {}, installed: true, loaded: true })
    property var live: ({})

    function run(args) {
        actionProc.command = ["bash", root.script].concat(args);
        actionProc.running = true;
    }
    function refreshStatus() {
        statusProc.running = false;
        statusProc.running = true;
    }
    Component.onCompleted: root.refreshStatus()

    Process {
        id: actionProc
        onExited: root.refreshStatus()
    }
    Process {
        id: statusProc
        command: ["bash", root.script, "status"]
        stdout: StdioCollector {
            id: statusOut
            onStreamFinished: {
                try {
                    root.hud = JSON.parse(statusOut.text);
                } catch (e) {}
            }
        }
    }
    Process {
        id: statsProc
        command: ["bash", root.script, "stats"]
        stdout: StdioCollector {
            id: statsOut
            onStreamFinished: {
                try {
                    root.live = JSON.parse(statsOut.text);
                } catch (e) {}
            }
        }
    }
    Timer { // live readings only while the widget is on screen
        interval: 1500
        running: root.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!statsProc.running) statsProc.running = true;
            if (!statusProc.running) root.refreshStatus();
        }
    }

    component Stat: Rectangle {
        id: stat
        property string statIcon
        property string statLabel
        property string statValue
        Layout.fillWidth: true
        implicitHeight: 54
        radius: Appearance.rounding.small
        color: Appearance.colors.colLayer2
        RowLayout {
            anchors {
                fill: parent
                leftMargin: 10
                rightMargin: 10
            }
            spacing: 8
            MaterialSymbol {
                text: stat.statIcon
                iconSize: 22
                color: Appearance.colors.colPrimary
            }
            ColumnLayout {
                spacing: 0
                StyledText {
                    text: stat.statValue
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.family: Appearance.font.family.numbers
                    color: Appearance.colors.colOnLayer2
                }
                StyledText {
                    text: stat.statLabel
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }
    component Toggle: RippleButton {
        id: tog
        property string togItem
        property string togLabel
        implicitHeight: 30
        implicitWidth: togText.implicitWidth + 22
        buttonRadius: 15
        toggled: !!(root.hud.items ?? {})[togItem]
        colBackground: Appearance.colors.colLayer2
        colBackgroundToggled: Appearance.colors.colSecondaryContainer
        colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
        onClicked: root.run(["set", tog.togItem, tog.toggled ? "false" : "true"])
        contentItem: StyledText {
            id: togText
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: tog.togLabel
            font.pixelSize: Appearance.font.pixelSize.small
            color: tog.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
        }
    }

    contentItem: OverlayBackground {
        radius: root.contentRadius
        implicitWidth: column.implicitWidth + 24
        implicitHeight: column.implicitHeight + 24

        ColumnLayout {
            id: column
            anchors {
                fill: parent
                margins: 12
            }
            spacing: 10

            // in-game overlay switch
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                MaterialSymbol {
                    text: "sports_esports"
                    iconSize: 24
                    color: Appearance.colors.colOnLayer1
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        text: "In-game overlay"
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: !root.hud.installed || !root.hud.loaded ? Appearance.colors.colError : Appearance.colors.colSubtext
                        text: !root.hud.installed ? "MangoHud is not installed: sudo pacman -S mangohud lib32-mangohud"
                            : !root.hud.loaded ? "Log out and back in once so games load MangoHud"
                            : "FPS and stats inside games. Super+F12 toggles it, no restart needed"
                    }
                }
                StyledSwitch {
                    checked: !!root.hud.shown
                    onClicked: {
                        root.run([checked ? "show" : "hide"]);
                        checked = Qt.binding(() => !!root.hud.shown);
                    }
                }
            }

            // live readings
            GridLayout {
                Layout.fillWidth: true
                columns: 3
                columnSpacing: 6
                rowSpacing: 6
                Stat {
                    statIcon: "speed"
                    statLabel: "GPU usage"
                    statValue: `${root.live.gpu ?? 0}%`
                }
                Stat {
                    statIcon: "thermostat"
                    statLabel: `GPU, hotspot ${root.live.hotspot ?? 0}°C`
                    statValue: `${root.live.gpuTemp ?? 0}°C`
                }
                Stat {
                    statIcon: "memory_alt"
                    statLabel: "VRAM"
                    statValue: `${((root.live.vramUsed ?? 0) / 1073741824).toFixed(1)} / ${Math.round((root.live.vramTotal ?? 0) / 1073741824)}G`
                }
                Stat {
                    statIcon: "bolt"
                    statLabel: `GPU clock, ${root.live.power ?? 0} W`
                    statValue: `${root.live.clock ?? 0} MHz`
                }
                Stat {
                    statIcon: "planner_review"
                    statLabel: `CPU, ${root.live.cpuTemp ?? 0}°C`
                    statValue: `${Math.round((ResourceUsage.cpuUsage ?? 0) * 100)}%`
                }
                Stat {
                    statIcon: "mode_fan"
                    statLabel: "GPU fan"
                    statValue: `${root.live.fan ?? 0} rpm`
                }
            }

            // what the in-game overlay shows
            StyledText {
                text: "Show in game"
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }
            Flow {
                Layout.fillWidth: true
                spacing: 6
                Toggle { togItem: "fps"; togLabel: "FPS" }
                Toggle { togItem: "graph"; togLabel: "Frame graph" }
                Toggle { togItem: "gpu"; togLabel: "GPU" }
                Toggle { togItem: "gputemp"; togLabel: "GPU temp" }
                Toggle { togItem: "vram"; togLabel: "VRAM" }
                Toggle { togItem: "clocks"; togLabel: "Clocks" }
                Toggle { togItem: "power"; togLabel: "Power" }
                Toggle { togItem: "cpu"; togLabel: "CPU" }
                Toggle { togItem: "cputemp"; togLabel: "CPU temp" }
                Toggle { togItem: "ram"; togLabel: "RAM" }
            }

            // corner
            StyledText {
                text: "Corner"
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: [["top-left", "Top left"], ["top-right", "Top right"], ["bottom-left", "Bottom left"], ["bottom-right", "Bottom right"]]
                    delegate: RippleButton {
                        id: cornerBtn
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 30
                        buttonRadius: 15
                        toggled: root.hud.position === modelData[0]
                        colBackground: Appearance.colors.colLayer2
                        colBackgroundToggled: Appearance.colors.colSecondaryContainer
                        colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                        onClicked: root.run(["position", modelData[0]])
                        contentItem: StyledText {
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: cornerBtn.modelData[1]
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: cornerBtn.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
                        }
                    }
                }
            }

            // text size
            StyledText {
                text: "Size"
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: [["small", "Small"], ["medium", "Medium"], ["large", "Large"], ["huge", "Huge"]]
                    delegate: RippleButton {
                        id: sizeBtn
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 30
                        buttonRadius: 15
                        toggled: (root.hud.size ?? "medium") === modelData[0]
                        colBackground: Appearance.colors.colLayer2
                        colBackgroundToggled: Appearance.colors.colSecondaryContainer
                        colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                        onClicked: root.run(["size", modelData[0]])
                        contentItem: StyledText {
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: sizeBtn.modelData[1]
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: sizeBtn.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
                        }
                    }
                }
            }
        }
    }
}
