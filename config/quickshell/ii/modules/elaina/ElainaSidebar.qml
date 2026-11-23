pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Bluetooth
import Quickshell.Services.Mpris
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.elaina

// The Travel Journal: Elaina's right sidebar, a parchment page with charms, sliders,
// the song she is humming, letters (notifications) and the way home (power buttons).
Scope {
    id: root

    component Serif: Text {
        font.family: ElainaTheme.serif
        color: ElainaTheme.blouseInk
        renderType: Text.NativeRendering
    }
    component Sans: Text {
        font.family: ElainaTheme.sans
        color: ElainaTheme.blouseInk
        renderType: Text.NativeRendering
    }
    component SectionTitle: RowLayout {
        property string label
        Layout.fillWidth: true
        spacing: 8
        MaterialSymbol {
            text: "star"
            fill: 1
            iconSize: 13
            color: ElainaTheme.gold
        }
        Serif {
            text: parent.label
            font.pixelSize: 15
            font.italic: true
            color: ElainaTheme.ribbon
        }
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Qt.rgba(0.5, 0.36, 0.76, 0.35)
        }
    }
    component Charm: Rectangle {
        id: charm
        property string icon
        property string label
        property bool active: false
        signal toggled()
        signal more()
        Layout.fillWidth: true
        implicitHeight: 64
        radius: 14
        color: charm.active ? ElainaTheme.robeSoft : (charmMouse.containsMouse ? Qt.rgba(0.5, 0.36, 0.76, 0.14) : Qt.rgba(0.5, 0.36, 0.76, 0.07))
        border.width: 1
        border.color: charm.active ? ElainaTheme.gold : Qt.rgba(0.5, 0.36, 0.76, 0.3)
        Behavior on color { ColorAnimation { duration: 140 } }
        scale: charmMouse.pressed ? 0.95 : charmMouse.containsMouse ? 1.03 : 1
        Behavior on scale { NumberAnimation { duration: ElainaTheme.fast; easing.type: Easing.OutBack } }
        ColumnLayout {
            anchors.centerIn: parent
            spacing: 2
            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                text: charm.icon
                fill: charm.active ? 1 : 0
                iconSize: 21
                color: charm.active ? ElainaTheme.gold : ElainaTheme.ribbon
            }
            Sans {
                Layout.alignment: Qt.AlignHCenter
                text: charm.label
                font.pixelSize: 10
                color: charm.active ? ElainaTheme.text : ElainaTheme.blouseInk
            }
        }
        MouseArea {
            id: charmMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: event => event.button === Qt.RightButton ? charm.more() : charm.toggled()
        }
    }
    component InkSlider: RowLayout {
        id: slider
        property string icon
        property real level: 0
        signal moved(real value)
        Layout.fillWidth: true
        spacing: 10
        MaterialSymbol {
            text: slider.icon
            iconSize: 19
            color: ElainaTheme.ribbon
        }
        Item {
            Layout.fillWidth: true
            implicitHeight: 22
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 6
                radius: 3
                color: Qt.rgba(0.5, 0.36, 0.76, 0.18)
                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1, slider.level))
                    height: parent.height
                    radius: 3
                    color: ElainaTheme.ribbon
                }
            }
            MaterialSymbol { // a little star as the handle
                x: Math.max(0, Math.min(parent.width - width, parent.width * slider.level - width / 2))
                anchors.verticalCenter: parent.verticalCenter
                text: "star"
                fill: 1
                iconSize: 18
                color: ElainaTheme.gold
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                function setFrom(x) {
                    slider.moved(Math.max(0, Math.min(1, x / width)));
                }
                onPressed: mouse => setFrom(mouse.x)
                onPositionChanged: mouse => { if (pressed) setFrom(mouse.x); }
                onWheel: event => slider.moved(Math.max(0, Math.min(1, slider.level + (event.angleDelta.y > 0 ? 0.05 : -0.05))))
            }
        }
        Sans {
            Layout.preferredWidth: 32
            horizontalAlignment: Text.AlignRight
            text: `${Math.round(slider.level * 100)}`
            font.pixelSize: 11
            color: ElainaTheme.muted
        }
    }


    PanelWindow {
        id: panel
        visible: GlobalStates.sidebarRightOpen || closeLinger.running
        Timer {
            id: closeLinger
            interval: ElainaTheme.smooth + 40
        }
        Connections {
            target: GlobalStates
            function onSidebarRightOpenChanged() {
                if (!GlobalStates.sidebarRightOpen) {
                    closeLinger.restart();
                    page.wasHovered = false;
                }
            }
        }
        WlrLayershell.namespace: "quickshell:sidebarRight"
        WlrLayershell.keyboardFocus: GlobalStates.sidebarRightOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        exclusiveZone: 0
        implicitWidth: 410
        color: "transparent"
        anchors {
            top: true
            right: true
            bottom: true
        }

        function hide() {
            GlobalStates.sidebarRightOpen = false;
        }
        onVisibleChanged: {
            if (visible) GlobalFocusGrab.addDismissable(panel);
            else GlobalFocusGrab.removeDismissable(panel);
        }
        Connections {
            target: GlobalFocusGrab
            function onDismissed() {
                panel.hide();
            }
        }

        readonly property var brightnessMonitor: Brightness.getMonitorForScreen(panel.screen)
        readonly property MprisPlayer player: MprisController.activePlayer

        // ===== The page =====
        Rectangle {
            id: page
            anchors {
                fill: parent
                topMargin: 6
                rightMargin: 10
                bottomMargin: 10
                leftMargin: 10
            }
            radius: 18
            color: ElainaTheme.pageFill
            border.width: 2
            border.color: ElainaTheme.robe
            focus: GlobalStates.sidebarRightOpen
            opacity: GlobalStates.sidebarRightOpen ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: ElainaTheme.smooth; easing.type: Easing.OutCubic } }
            transform: Translate {
                x: GlobalStates.sidebarRightOpen ? 0 : 60
                Behavior on x { NumberAnimation { duration: ElainaTheme.smooth; easing.type: Easing.OutCubic } }
            }
            // "Unhover to close", same as the NovelKnock sidebars
            property bool wasHovered: false
            HoverHandler {
                onHoveredChanged: {
                    if (hovered) page.wasHovered = true;
                    else if (page.wasHovered && GlobalStates.sidebarRightOpen) {
                        page.wasHovered = false;
                        GlobalStates.sidebarRightOpen = false;
                    }
                }
            }
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) panel.hide();
            }

            ElainaArt { // ~/Pictures/Elaina/page.*, a faint picture in the corner of the page
                name: "page"
                anchors {
                    right: parent.right
                    bottom: parent.bottom
                    margins: 8
                }
                width: parent.width * 0.75
                height: parent.height * 0.45
                fillMode: Image.PreserveAspectFit
                horizontalAlignment: Image.AlignRight
                verticalAlignment: Image.AlignBottom
                sourceSize.height: 700
                opacity: 0.13
            }

            // Inner stitched border, like a leather bound journal
            Rectangle {
                anchors {
                    fill: parent
                    margins: 6
                }
                radius: 14
                color: "transparent"
                border.width: 1
                border.color: Qt.rgba(0.5, 0.36, 0.76, 0.25)
            }

            ColumnLayout {
                anchors {
                    fill: parent
                    margins: 18
                }
                spacing: 14

                // ----- Header -----
                Rectangle {
                    id: header
                    Layout.fillWidth: true
                    implicitHeight: cover.found ? 140 : 82
                    radius: 14
                    color: ElainaTheme.robe
                    // Cover picture from ~/Pictures/Elaina/cover.*, cropped to the header with rounded corners
                    ElainaArt {
                        id: cover
                        name: "cover"
                        anchors.fill: parent
                        sourceSize.width: 820
                        visible: false
                    }
                    Rectangle {
                        id: coverMask
                        anchors.fill: parent
                        radius: header.radius
                        visible: false
                    }
                    OpacityMask {
                        anchors.fill: parent
                        visible: cover.found
                        source: cover
                        maskSource: coverMask
                    }
                    Rectangle { // darken the bottom so the writing stays readable
                        anchors.fill: parent
                        visible: cover.found
                        radius: header.radius
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Qt.rgba(0.09, 0.10, 0.19, 0.05) }
                            GradientStop { position: 0.55; color: Qt.rgba(0.09, 0.10, 0.19, 0.45) }
                            GradientStop { position: 1.0; color: Qt.rgba(0.09, 0.10, 0.19, 0.92) }
                        }
                    }
                    RowLayout {
                        anchors {
                            left: parent.left
                            right: parent.right
                            bottom: parent.bottom
                            leftMargin: 16
                            rightMargin: 16
                        }
                        height: 82
                        spacing: 14
                        WitchHat {
                            visible: !cover.found
                            implicitWidth: 46
                            implicitHeight: 40
                            hatColor: ElainaTheme.robeSoft
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Serif {
                                text: "Travel Journal"
                                font.pixelSize: 22
                                font.italic: true
                                color: ElainaTheme.text
                            }
                            Sans {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: {
                                    const h = DateTime.clock.date.getHours();
                                    const part = h < 5 ? "Still awake" : h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening";
                                    return `${part}, traveler`;
                                }
                                font.pixelSize: 12
                                color: ElainaTheme.lavender
                            }
                            Sans {
                                text: `Entry for ${DateTime.collapsedCalendarFormat}`
                                font.pixelSize: 10
                                color: ElainaTheme.muted
                            }
                        }
                        Serif {
                            Layout.alignment: Qt.AlignVCenter
                            text: DateTime.time
                            font.pixelSize: 24
                            color: ElainaTheme.gold
                        }
                    }
                }

                // ----- Charms -----
                SectionTitle { label: "Charms" }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Charm {
                        icon: Network.ethernet ? "lan" : "wifi"
                        label: Network.ethernet ? "Wired" : "Wi-Fi"
                        active: Network.ethernet || Network.wifiEnabled
                        onToggled: Network.toggleWifi()
                        onMore: Quickshell.execDetached(["bash", "-c", Network.ethernet ? Config.options.apps.networkEthernet : Config.options.apps.network])
                    }
                    Charm {
                        visible: BluetoothStatus.available
                        icon: "bluetooth"
                        label: "Bluetooth"
                        active: BluetoothStatus.enabled
                        onToggled: {
                            if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter.enabled;
                        }
                        onMore: Quickshell.execDetached(["bash", "-c", Config.options.apps.bluetooth])
                    }
                    Charm {
                        icon: "do_not_disturb_on"
                        label: "Quiet"
                        active: Notifications.silent
                        onToggled: Notifications.silent = !Notifications.silent
                    }
                    Charm {
                        icon: "coffee"
                        label: "Awake"
                        active: Idle.inhibit
                        onToggled: Idle.toggleInhibit()
                    }
                    Charm {
                        icon: "nightlight"
                        label: "Night"
                        active: Hyprsunset.temperatureActive
                        onToggled: Hyprsunset.toggleTemperature()
                    }
                }

                InkSlider {
                    icon: (Audio.sink?.audio?.muted ?? false) ? "volume_off" : "volume_up"
                    level: Audio.sink?.audio?.volume ?? 0
                    onMoved: value => {
                        if (Audio.sink?.audio) Audio.sink.audio.volume = value;
                    }
                }
                InkSlider {
                    visible: !!panel.brightnessMonitor
                    icon: "light_mode"
                    level: panel.brightnessMonitor?.brightness ?? 0
                    onMoved: value => panel.brightnessMonitor?.setBrightness(Math.max(0.01, value))
                }

                // ----- Now playing -----
                SectionTitle {
                    visible: !!panel.player
                    label: "A song for the road"
                }
                Rectangle {
                    visible: !!panel.player
                    Layout.fillWidth: true
                    implicitHeight: 70
                    radius: 14
                    color: ElainaTheme.robeSoft
                    RowLayout {
                        anchors {
                            fill: parent
                            leftMargin: 14
                            rightMargin: 10
                        }
                        spacing: 10
                        MaterialSymbol {
                            text: "music_note"
                            iconSize: 26
                            color: ElainaTheme.gold
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: panel.player?.trackTitle ?? ""
                                font.family: ElainaTheme.serif
                                font.pixelSize: 14
                                color: ElainaTheme.text
                            }
                            Text {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: panel.player?.trackArtist ?? ""
                                font.family: ElainaTheme.sans
                                font.pixelSize: 11
                                color: ElainaTheme.lavender
                            }
                        }
                        Repeater {
                            model: [
                                { icon: "skip_previous", run: () => panel.player?.previous() },
                                { icon: panel.player?.isPlaying ? "pause" : "play_arrow", run: () => panel.player?.togglePlaying() },
                                { icon: "skip_next", run: () => panel.player?.next() }
                            ]
                            delegate: MaterialSymbol {
                                required property var modelData
                                text: modelData.icon
                                iconSize: 24
                                fill: 1
                                color: ElainaTheme.text
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: parent.modelData.run()
                                }
                            }
                        }
                    }
                }

                // ----- Letters -----
                SectionTitle { label: `Letters (${Notifications.list.length})` }
                ListView {
                    id: letters
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 8
                    model: ScriptModel {
                        values: [...Notifications.list].reverse()
                    }
                    add: Transition {
                        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: ElainaTheme.smooth }
                        NumberAnimation { property: "x"; from: 30; to: 0; duration: ElainaTheme.smooth; easing.type: Easing.OutCubic }
                    }
                    remove: Transition {
                        NumberAnimation { property: "opacity"; to: 0; duration: ElainaTheme.fast }
                        NumberAnimation { property: "x"; to: 60; duration: ElainaTheme.fast }
                    }
                    displaced: Transition {
                        NumberAnimation { property: "y"; duration: ElainaTheme.smooth; easing.type: Easing.OutCubic }
                    }
                    delegate: Rectangle {
                        id: letter
                        required property var modelData
                        width: ListView.view.width
                        implicitHeight: letterCol.implicitHeight + 18
                        radius: 12
                        color: letterHover.hovered ? Qt.rgba(0.5, 0.36, 0.76, 0.15) : Qt.rgba(0.5, 0.36, 0.76, 0.08)
                        Behavior on color { ColorAnimation { duration: ElainaTheme.fast } }
                        HoverHandler { id: letterHover }
                        border.width: 1
                        border.color: Qt.rgba(0.5, 0.36, 0.76, 0.22)
                        ColumnLayout {
                            id: letterCol
                            anchors {
                                left: parent.left
                                right: parent.right
                                top: parent.top
                                margins: 10
                                rightMargin: 30
                            }
                            spacing: 2
                            Sans {
                                text: letter.modelData.appName || "A letter"
                                font.pixelSize: 10
                                color: ElainaTheme.ribbon
                            }
                            Serif {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: letter.modelData.summary
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                            }
                            Sans {
                                Layout.fillWidth: true
                                visible: text.length > 0
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                textFormat: Text.PlainText
                                text: letter.modelData.body
                                font.pixelSize: 11
                                color: "#55527a"
                            }
                        }
                        MaterialSymbol {
                            anchors {
                                right: parent.right
                                top: parent.top
                                margins: 8
                            }
                            text: "close"
                            iconSize: 16
                            color: ElainaTheme.muted
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -4
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Notifications.discardNotification(letter.modelData.notificationId)
                            }
                        }
                    }
                    Column {
                        anchors.centerIn: parent
                        visible: letters.count === 0
                        spacing: 4
                        ElainaArt { // ~/Pictures/Elaina/letters.*
                            id: lettersArt
                            name: "letters"
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 170
                            height: 130
                            fillMode: Image.PreserveAspectFit
                            sourceSize.height: 260
                            opacity: 0.9
                        }
                        MaterialSymbol {
                            visible: !lettersArt.found
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "mail"
                            iconSize: 30
                            color: Qt.rgba(0.5, 0.36, 0.76, 0.45)
                        }
                        Serif {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "No letters today"
                            font.italic: true
                            font.pixelSize: 13
                            color: ElainaTheme.muted
                        }
                    }
                }

                // ----- Footer: clear letters + the way home -----
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Rectangle {
                        visible: Notifications.list.length > 0
                        implicitHeight: 34
                        implicitWidth: clearText.implicitWidth + 24
                        radius: 17
                        color: clearMouse.containsMouse ? Qt.rgba(0.5, 0.36, 0.76, 0.18) : "transparent"
                        border.width: 1
                        border.color: Qt.rgba(0.5, 0.36, 0.76, 0.35)
                        Sans {
                            id: clearText
                            anchors.centerIn: parent
                            text: "Clear letters"
                            font.pixelSize: 11
                            color: ElainaTheme.ribbon
                        }
                        MouseArea {
                            id: clearMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Notifications.discardAllNotifications()
                        }
                    }
                    Item { Layout.fillWidth: true }
                    Repeater {
                        model: [
                            { icon: "lock", run: () => Session.lock() },
                            { icon: "bedtime", run: () => Session.suspend() },
                            { icon: "logout", run: () => { GlobalStates.sidebarRightOpen = false; GlobalStates.sessionOpen = true; } },
                            { icon: "power_settings_new", run: () => { GlobalStates.sidebarRightOpen = false; GlobalStates.sessionOpen = true; } }
                        ]
                        delegate: Rectangle {
                            id: homeBtn
                            required property var modelData
                            implicitWidth: 34
                            implicitHeight: 34
                            radius: 17
                            color: homeMouse.containsMouse ? ElainaTheme.robe : Qt.rgba(0.5, 0.36, 0.76, 0.1)
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: homeBtn.modelData.icon
                                iconSize: 18
                                color: homeMouse.containsMouse ? ElainaTheme.gold : ElainaTheme.ribbon
                            }
                            MouseArea {
                                id: homeMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: homeBtn.modelData.run()
                            }
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "sidebarRight"
        function toggle(): void {
            GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
        }
        function close(): void {
            GlobalStates.sidebarRightOpen = false;
        }
        function open(): void {
            GlobalStates.sidebarRightOpen = true;
        }
    }
    GlobalShortcut {
        name: "sidebarRightToggle"
        description: "Toggles right sidebar on press"
        onPressed: GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen
    }
    GlobalShortcut {
        name: "sidebarRightOpen"
        description: "Opens right sidebar on press"
        onPressed: GlobalStates.sidebarRightOpen = true
    }
    GlobalShortcut {
        name: "sidebarRightClose"
        description: "Closes right sidebar on press"
        onPressed: GlobalStates.sidebarRightOpen = false
    }
}
