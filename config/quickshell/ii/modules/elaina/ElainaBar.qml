pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.elaina
import qs.modules.ii.bar

// Elaina bar: three floating ribbons.
//   Left:   witch hat (left sidebar) + "Chapter N" + the journey route (workspaces as stars)
//   Center: clock and date, written like a journal entry
//   Right:  now playing, tray, status, and the star brooch that opens the Travel Journal
Scope {
    id: bar

    component Ribbon: Rectangle {
        implicitHeight: 42
        radius: ElainaTheme.radius
        color: ElainaTheme.barFill
        border.width: 1
        border.color: ElainaTheme.robeLine
    }
    component Serif: Text {
        font.family: ElainaTheme.serif
        color: ElainaTheme.text
        renderType: Text.NativeRendering
    }
    component Sans: Text {
        font.family: ElainaTheme.sans
        color: ElainaTheme.text
        renderType: Text.NativeRendering
    }


    // Same per monitor ranges as the NovelKnock bar
    readonly property var monitorRanges: ({
        "HDMI-A-1": [1, 5],
        "DP-3": [6, 10]
    })

    Variants {
        model: Quickshell.screens
        LazyLoader {
            id: barLoader
            required property ShellScreen modelData
            active: GlobalStates.barOpen && !GlobalStates.screenLocked
            component: PanelWindow {
                id: win
                screen: barLoader.modelData
                readonly property HyprlandMonitor monitor: Hyprland.monitorFor(win.screen)
                WlrLayershell.namespace: "quickshell:bar"
                color: "transparent"
                implicitHeight: 58
                exclusiveZone: 54
                anchors {
                    top: true
                    left: true
                    right: true
                }
                Component.onCompleted: GlobalFocusGrab.addPersistent(win)
                Component.onDestruction: GlobalFocusGrab.removePersistent(win)

                // ================= LEFT =================
                Ribbon {
                    id: leftRibbon
                    anchors {
                        left: parent.left
                        top: parent.top
                        leftMargin: 10
                        topMargin: 8
                    }
                    implicitWidth: leftRow.implicitWidth + 24

                    readonly property int activeId: win.monitor?.activeWorkspace?.id ?? 1
                    readonly property var fixedRange: bar.monitorRanges[win.monitor?.name ?? ""] ?? null
                    readonly property int groupSize: Math.max(1, Config.options.bar.workspaces.shown ?? 10)
                    readonly property int first: fixedRange ? fixedRange[0] : Math.floor((activeId - 1) / groupSize) * groupSize + 1
                    readonly property int last: fixedRange ? fixedRange[1] : first + groupSize - 1

                    function step(delta) {
                        const target = Math.max(first, Math.min(last, activeId + delta));
                        if (target !== activeId) Hyprland.dispatch(`hl.dsp.focus({workspace = ${target}})`);
                    }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.RightButton
                        onPressed: GlobalStates.overviewOpen = !GlobalStates.overviewOpen
                        onWheel: event => leftRibbon.step(event.angleDelta.y < 0 ? 1 : -1)
                    }

                    RowLayout {
                        id: leftRow
                        anchors.centerIn: parent
                        spacing: 10

                        Item { // her portrait from ~/Pictures/Elaina/avatar.*, or the drawn hat if there is none
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: 32
                            implicitHeight: 32
                            ElainaArt {
                                id: avatar
                                name: "avatar"
                                anchors.fill: parent
                                sourceSize.width: 96
                                sourceSize.height: 96
                                visible: false
                            }
                            Rectangle {
                                id: avatarMask
                                anchors.fill: parent
                                radius: width / 2
                                visible: false
                            }
                            OpacityMask { // round crop
                                anchors.fill: parent
                                visible: avatar.found
                                source: avatar
                                maskSource: avatarMask
                            }
                            Rectangle { // ring
                                anchors.fill: parent
                                visible: avatar.found
                                radius: width / 2
                                color: "transparent"
                                border.width: 1.5
                                border.color: hatMouse.containsMouse ? ElainaTheme.gold : ElainaTheme.lavender
                            }
                            WitchHat {
                                anchors.centerIn: parent
                                visible: !avatar.found
                                implicitWidth: 30
                                implicitHeight: 26
                                hatColor: hatMouse.containsMouse ? ElainaTheme.ribbon : ElainaTheme.robe
                            }
                            MouseArea {
                                id: hatMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen
                            }
                        }

                        ColumnLayout {
                            Layout.alignment: Qt.AlignVCenter
                            spacing: -3
                            Serif {
                                text: `Chapter ${leftRibbon.activeId}`
                                font.pixelSize: 15
                                font.italic: true
                                color: ElainaTheme.lavender
                            }
                            Sans {
                                text: "the journey so far"
                                font.pixelSize: 9
                                color: ElainaTheme.muted
                            }
                        }

                        // The route: stars joined by a dotted path
                        Row {
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 0
                            Repeater {
                                model: leftRibbon.last - leftRibbon.first + 1
                                delegate: Row {
                                    id: stop
                                    required property int index
                                    readonly property int wsId: leftRibbon.first + index
                                    readonly property bool active: leftRibbon.activeId === wsId
                                    readonly property bool visited: HyprlandData.windowList.some(w => w.workspace?.id === wsId)
                                    spacing: 0
                                    Row { // dotted path before every star but the first
                                        visible: stop.index > 0
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 3
                                        Repeater {
                                            model: 3
                                            delegate: Rectangle {
                                                width: 2
                                                height: 2
                                                radius: 1
                                                color: ElainaTheme.robeLine
                                            }
                                        }
                                        leftPadding: 3
                                        rightPadding: 3
                                    }
                                    Item {
                                        width: 24
                                        height: 26
                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "star"
                                            fill: (stop.active || stop.visited) ? 1 : 0
                                            iconSize: stop.active ? 22 : 16
                                            color: stop.active ? ElainaTheme.gold : stop.visited ? ElainaTheme.lavender : ElainaTheme.muted
                                            Behavior on iconSize { NumberAnimation { duration: 160 } }
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: Hyprland.dispatch(`hl.dsp.focus({workspace = ${stop.wsId}})`)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ================= CENTER =================
                Ribbon {
                    id: centerRibbon
                    anchors {
                        horizontalCenter: parent.horizontalCenter
                        top: parent.top
                        topMargin: 8
                    }
                    implicitWidth: centerRow.implicitWidth + 32
                    RowLayout {
                        id: centerRow
                        anchors.centerIn: parent
                        spacing: 12
                        MaterialSymbol {
                            Layout.alignment: Qt.AlignVCenter
                            text: "auto_awesome"
                            iconSize: 16
                            color: ElainaTheme.gold
                        }
                        Serif {
                            Layout.alignment: Qt.AlignVCenter
                            text: DateTime.time
                            font.pixelSize: 20
                            font.weight: Font.DemiBold
                        }
                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            width: 1
                            height: 20
                            color: ElainaTheme.robeLine
                        }
                        Serif {
                            Layout.alignment: Qt.AlignVCenter
                            text: DateTime.collapsedCalendarFormat
                            font.pixelSize: 13
                            font.italic: true
                            color: ElainaTheme.silver
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen
                    }
                }

                // ================= RIGHT =================
                Ribbon {
                    id: rightRibbon
                    anchors {
                        right: parent.right
                        top: parent.top
                        rightMargin: 10
                        topMargin: 8
                    }
                    implicitWidth: rightRow.implicitWidth + 24
                    readonly property MprisPlayer player: MprisController.activePlayer

                    RowLayout {
                        id: rightRow
                        anchors.centerIn: parent
                        spacing: 12

                        // Now playing
                        RowLayout {
                            visible: !!rightRibbon.player
                            spacing: 6
                            MaterialSymbol {
                                text: rightRibbon.player?.isPlaying ? "music_note" : "pause"
                                iconSize: 17
                                color: ElainaTheme.lavender
                            }
                            Sans {
                                Layout.maximumWidth: 180
                                elide: Text.ElideRight
                                text: rightRibbon.player?.trackTitle ?? ""
                                font.pixelSize: 12
                                MouseArea {
                                    anchors.fill: parent
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: event => {
                                        if (event.button === Qt.RightButton) rightRibbon.player?.next();
                                        else rightRibbon.player?.togglePlaying();
                                    }
                                }
                            }
                            Rectangle {
                                width: 1
                                height: 18
                                color: ElainaTheme.robeLine
                            }
                        }

                        SysTray {
                            Layout.alignment: Qt.AlignVCenter
                            showSeparator: false
                        }

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignVCenter
                            text: Network.materialSymbol
                            iconSize: 18
                            color: ElainaTheme.silver
                        }
                        MaterialSymbol {
                            Layout.alignment: Qt.AlignVCenter
                            visible: BluetoothStatus.available
                            text: BluetoothStatus.connected ? "bluetooth_connected" : BluetoothStatus.enabled ? "bluetooth" : "bluetooth_disabled"
                            iconSize: 18
                            color: ElainaTheme.silver
                        }

                        // Volume: scroll to change, click to mute
                        RowLayout {
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 3
                            readonly property real vol: Audio.sink?.audio?.volume ?? 0
                            readonly property bool muted: Audio.sink?.audio?.muted ?? false
                            MaterialSymbol {
                                text: parent.muted ? "volume_off" : parent.vol > 0.5 ? "volume_up" : "volume_down"
                                iconSize: 18
                                color: ElainaTheme.silver
                            }
                            Sans {
                                text: `${Math.round(parent.vol * 100)}`
                                font.pixelSize: 11
                                color: ElainaTheme.muted
                            }
                        }

                        // Battery (laptops only)
                        RowLayout {
                            Layout.alignment: Qt.AlignVCenter
                            visible: Battery.available
                            spacing: 3
                            MaterialSymbol {
                                text: Battery.isCharging ? "battery_charging_full" : "battery_full"
                                iconSize: 18
                                color: Battery.isLowAndNotCharging ? ElainaTheme.danger : ElainaTheme.silver
                            }
                            Sans {
                                text: `${Math.round(Battery.percentage * 100)}%`
                                font.pixelSize: 11
                                color: ElainaTheme.muted
                            }
                        }

                        // Star brooch: opens the Travel Journal
                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: 30
                            implicitHeight: 30
                            radius: 15
                            color: GlobalStates.sidebarRightOpen || broochMouse.containsMouse ? ElainaTheme.ribbon : ElainaTheme.robe
                            border.width: 1.5
                            border.color: ElainaTheme.gold
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "star"
                                fill: 1
                                iconSize: 17
                                color: ElainaTheme.gold
                            }
                            Rectangle { // unread letters
                                visible: Notifications.list.length > 0
                                anchors {
                                    right: parent.right
                                    top: parent.top
                                    margins: -1
                                }
                                width: 9
                                height: 9
                                radius: 5
                                color: ElainaTheme.lavender
                                border.width: 1
                                border.color: ElainaTheme.robe
                            }
                            MouseArea {
                                id: broochMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen
                            }
                        }
                    }

                    MouseArea { // volume scroll anywhere on the right ribbon
                        anchors.fill: parent
                        acceptedButtons: Qt.MiddleButton
                        onClicked: if (Audio.sink?.audio) Audio.sink.audio.muted = !Audio.sink.audio.muted
                        onWheel: event => {
                            if (!Audio.sink?.audio) return;
                            const v = Audio.sink.audio.volume + (event.angleDelta.y > 0 ? 0.05 : -0.05);
                            Audio.sink.audio.volume = Math.max(0, Math.min(1, Math.round(v * 20) / 20));
                        }
                        z: -1
                    }
                }
            }
        }
    }
}
