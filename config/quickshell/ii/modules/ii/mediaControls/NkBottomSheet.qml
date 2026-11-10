// NovelKnock "bottom sheet" music panel for ii (replaces ii's media popup).
// Slides up from the bottom: collapse / pin buttons, big cover, title, controls,
// cava visualizer behind, per-app volume mixer on the right.
// Opens with Super+M (same shortcut names as ii's media controls), the bar's music
// pill (middle click still plays/pauses), or a click on the 1px line at the bottom edge.
pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire

Scope {
    id: root
    readonly property MprisPlayer player: MprisController.activePlayer
    readonly property string nkFont: "Lexend"
    readonly property real sheetHeight: 300
    property bool pinned: false
    property list<real> visualizerPoints: []

    // Keep app stream volumes readable
    PwObjectTracker {
        objects: Audio.outputAppNodes
    }

    Process { // Audio visualizer (same cava setup ii uses)
        id: cavaProc
        running: GlobalStates.mediaControlsOpen
        onRunningChanged: {
            if (!running) root.visualizerPoints = [];
        }
        command: ["cava", "-p", `${FileUtils.trimFileProtocol(Directories.scriptPath)}/cava/raw_output_config.txt`]
        stdout: SplitParser {
            onRead: data => {
                root.visualizerPoints = data.split(";").map(p => parseFloat(p.trim())).filter(p => !isNaN(p));
            }
        }
    }

    Timer {
        running: GlobalStates.mediaControlsOpen && root.player?.playbackState == MprisPlaybackState.Playing
        interval: 1000
        repeat: true
        onTriggered: root.player.positionChanged()
    }

    // 1px line along the bottom edge: click it to open/close the sheet
    PanelWindow {
        id: bottomLine
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        implicitHeight: 1
        color: "transparent"
        WlrLayershell.namespace: "quickshell:bottomline"
        anchors {
            bottom: true
            left: true
            right: true
        }
        MouseArea {
            anchors.fill: parent
            onClicked: GlobalStates.mediaControlsOpen = !GlobalStates.mediaControlsOpen
        }
    }

    PanelWindow {
        id: sheetWindow
        visible: GlobalStates.mediaControlsOpen || sheet.y < sheetWindow.height
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        implicitHeight: root.sheetHeight + Appearance.sizes.hyprlandGapsOut * 2
        color: "transparent"
        WlrLayershell.namespace: "quickshell:mediaControls"
        WlrLayershell.layer: WlrLayer.Overlay // show above fullscreen apps
        anchors {
            bottom: true
            left: true
            right: true
        }
        mask: Region {
            item: sheet
        }

        onVisibleChanged: {
            if (visible && !root.pinned) GlobalFocusGrab.addDismissable(sheetWindow);
            else GlobalFocusGrab.removeDismissable(sheetWindow);
        }
        Connections {
            target: root
            function onPinnedChanged() {
                if (root.pinned) GlobalFocusGrab.removeDismissable(sheetWindow);
                else if (sheetWindow.visible) GlobalFocusGrab.addDismissable(sheetWindow);
            }
        }
        Connections {
            target: GlobalFocusGrab
            function onDismissed() {
                if (!root.pinned) GlobalStates.mediaControlsOpen = false;
            }
        }

        Rectangle {
            id: sheet
            x: Appearance.sizes.hyprlandGapsOut
            width: parent.width - Appearance.sizes.hyprlandGapsOut * 2
            height: root.sheetHeight
            y: GlobalStates.mediaControlsOpen ? Appearance.sizes.hyprlandGapsOut : sheetWindow.height + 10
            Behavior on y {
                NumberAnimation {
                    duration: 350
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: [0.05, 0.7, 0.1, 1, 1, 1]
                }
            }
            radius: 14
            color: ColorUtils.transparentize(ColorUtils.mix(Appearance.colors.colLayer0Base, Appearance.colors.colPrimaryContainer, 0.8), 0.25)
            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: sheet.width
                    height: sheet.height
                    radius: sheet.radius
                }
            }

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) GlobalStates.mediaControlsOpen = false;
            }

            // ---- Background: blurred cover + tint ----
            Image {
                id: coverSource
                visible: false
                source: root.player?.trackArtUrl ?? ""
                asynchronous: true
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: 600
                sourceSize.height: 600
            }
            FastBlur {
                anchors.fill: parent
                visible: coverSource.status === Image.Ready
                source: coverSource
                radius: 64
            }
            Rectangle {
                anchors.fill: parent
                color: ColorUtils.transparentize(ColorUtils.mix(Appearance.colors.colLayer0Base, Appearance.colors.colPrimaryContainer, 0.7), coverSource.status === Image.Ready ? 0.45 : 0.6)
            }

            // ---- Visualizer bars across the whole sheet ----
            Row {
                anchors {
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                    leftMargin: 20
                    rightMargin: 20
                }
                height: parent.height
                spacing: root.visualizerPoints.length > 0 ? (width - barWidth * root.visualizerPoints.length) / Math.max(1, root.visualizerPoints.length - 1) : 0
                readonly property real barWidth: 7
                Repeater {
                    model: root.visualizerPoints.length
                    delegate: Rectangle {
                        required property int index
                        anchors.bottom: parent.bottom
                        width: parent.barWidth
                        radius: 3
                        height: Math.min(parent.height - 20, (root.visualizerPoints[index] ?? 0) / 1000 * (parent.height - 20))
                        color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.62)
                        Behavior on height {
                            NumberAnimation { duration: 60 }
                        }
                    }
                }
            }

            // ---- Foreground ----
            RowLayout {
                anchors {
                    fill: parent
                    margins: 14
                }
                spacing: 18

                ColumnLayout { // Collapse + pin
                    Layout.alignment: Qt.AlignTop
                    spacing: 8
                    Repeater {
                        model: [
                            { icon: "keyboard_double_arrow_down", active: false, run: () => { GlobalStates.mediaControlsOpen = false } },
                            { icon: "push_pin", active: root.pinned, run: () => { root.pinned = !root.pinned } },
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            implicitWidth: 34
                            implicitHeight: 34
                            radius: 9
                            color: modelData.active ? Appearance.colors.colPrimary
                                : ctlMouse.containsMouse ? Appearance.colors.colLayer1Hover
                                : ColorUtils.transparentize(Appearance.colors.colLayer1, 0.3)
                            MaterialSymbol {
                                anchors.centerIn: parent
                                fill: 1
                                text: modelData.icon
                                iconSize: 18
                                color: modelData.active ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer0
                            }
                            MouseArea {
                                id: ctlMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: modelData.run()
                            }
                        }
                    }
                }

                Rectangle { // Big cover
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 200
                    implicitHeight: 200
                    radius: 12
                    color: Appearance.colors.colSecondaryContainer
                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: 200
                            height: 200
                            radius: 12
                        }
                    }
                    Image {
                        anchors.fill: parent
                        visible: status === Image.Ready
                        source: coverSource.source
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: 400
                        sourceSize.height: 400
                    }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        visible: coverSource.status !== Image.Ready
                        fill: 1
                        text: "music_note"
                        iconSize: 64
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                }

                ColumnLayout { // Title, artist, controls
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.topMargin: 14
                    Layout.bottomMargin: 14
                    spacing: 2
                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        font.family: root.nkFont
                        font.pixelSize: 28
                        color: Appearance.colors.colOnLayer0
                        text: root.player ? (StringUtils.cleanMusicTitle(root.player.trackTitle) || "Music") : "Nothing playing"
                    }
                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        font.family: root.nkFont
                        font.pixelSize: 16
                        color: Appearance.colors.colOnLayer0
                        opacity: 0.85
                        text: root.player?.trackArtist ?? ""
                    }
                    Item { Layout.fillHeight: true }
                    RowLayout {
                        spacing: 12
                        Rectangle { // Controls pill
                            implicitWidth: controlsRow.implicitWidth + 16
                            implicitHeight: 40
                            radius: 20
                            color: ColorUtils.transparentize("#000000", 0.35)
                            RowLayout {
                                id: controlsRow
                                anchors.centerIn: parent
                                spacing: 2
                                Repeater {
                                    model: [
                                        { icon: "skip_previous", run: () => root.player?.previous() },
                                        { icon: root.player?.isPlaying ? "pause" : "play_arrow", run: () => root.player?.togglePlaying() },
                                        { icon: "skip_next", run: () => root.player?.next() },
                                    ]
                                    delegate: Rectangle {
                                        required property var modelData
                                        implicitWidth: 32
                                        implicitHeight: 32
                                        radius: 16
                                        color: mMouse.containsMouse ? ColorUtils.transparentize("#ffffff", 0.85) : "transparent"
                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            fill: 1
                                            text: modelData.icon
                                            iconSize: 22
                                            color: "#ffffff"
                                        }
                                        MouseArea {
                                            id: mMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onClicked: modelData.run()
                                        }
                                    }
                                }
                            }
                        }
                        StyledText { // Time
                            visible: !!root.player && (root.player.length ?? 0) > 0
                            font.family: root.nkFont
                            font.pixelSize: 13
                            color: Appearance.colors.colOnLayer0
                            opacity: 0.85
                            function fmt(s) {
                                if (!s || s < 0) return "0:00";
                                const m = Math.floor(s / 60), sec = Math.floor(s % 60);
                                return `${m}:${sec < 10 ? "0" : ""}${sec}`;
                            }
                            text: `${fmt(root.player?.position)} / ${fmt(root.player?.length)}`
                        }
                    }
                }

                ListView { // Per-app volume mixer
                    id: mixer
                    Layout.preferredWidth: Math.min(500, sheet.width * 0.32)
                    Layout.fillHeight: true
                    spacing: 6
                    clip: true
                    model: Audio.outputAppNodes
                    delegate: Rectangle {
                        id: appRow
                        required property var modelData
                        width: mixer.width
                        height: 42
                        radius: 12
                        color: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.35)
                        readonly property real volume: modelData?.audio?.volume ?? 0
                        readonly property bool muted: modelData?.audio?.muted ?? false
                        readonly property string iconName: modelData?.properties?.["application.icon-name"]
                            ?? modelData?.properties?.["application.process.binary"] ?? "audio-x-generic"

                        RowLayout {
                            anchors {
                                fill: parent
                                leftMargin: 6
                                rightMargin: 6
                            }
                            spacing: 8
                            IconImage {
                                implicitSize: 28
                                source: Quickshell.iconPath(appRow.iconName, "audio-x-generic")
                            }
                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                font.family: root.nkFont
                                font.pixelSize: 13
                                color: Appearance.colors.colOnLayer0
                                text: `#${appRow.modelData?.id ?? ""}  ${Audio.appNodeDisplayName(appRow.modelData)}`
                            }
                            Item { // Volume ring, scroll to change, click to mute
                                implicitWidth: 34
                                implicitHeight: 34
                                CircularProgress {
                                    anchors.centerIn: parent
                                    implicitSize: 32
                                    lineWidth: 2
                                    value: Math.min(1, appRow.volume)
                                    colPrimary: appRow.muted ? Appearance.colors.colOutline : Appearance.colors.colOnLayer0
                                    colSecondary: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.8)
                                    enableAnimation: false
                                }
                                StyledText {
                                    anchors.centerIn: parent
                                    text: appRow.muted ? "M" : Math.round(appRow.volume * 100)
                                    font.family: root.nkFont
                                    font.pixelSize: 11
                                    color: Appearance.colors.colOnLayer0
                                }
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                if (appRow.modelData?.audio) appRow.modelData.audio.muted = !appRow.modelData.audio.muted;
                            }
                            onWheel: event => {
                                const a = appRow.modelData?.audio;
                                if (!a) return;
                                const step = event.angleDelta.y > 0 ? 0.05 : -0.05;
                                a.volume = Math.max(0, Math.min(1, a.volume + step));
                            }
                        }
                    }

                    StyledText {
                        anchors.centerIn: parent
                        visible: mixer.count === 0
                        text: "No apps playing sound"
                        font.family: root.nkFont
                        font.pixelSize: 13
                        color: Appearance.colors.colOnLayer0
                        opacity: 0.7
                    }
                }
            }
        }
    }

    // Same IPC target and shortcut names as ii's media controls, so Super+M keeps working
    IpcHandler {
        target: "mediaControls"
        function toggle(): void {
            GlobalStates.mediaControlsOpen = !GlobalStates.mediaControlsOpen;
        }
        function close(): void {
            GlobalStates.mediaControlsOpen = false;
        }
        function open(): void {
            GlobalStates.mediaControlsOpen = true;
        }
    }
    GlobalShortcut {
        name: "mediaControlsToggle"
        description: "Toggles media controls on press"
        onPressed: GlobalStates.mediaControlsOpen = !GlobalStates.mediaControlsOpen
    }
    GlobalShortcut {
        name: "mediaControlsOpen"
        description: "Opens media controls on press"
        onPressed: GlobalStates.mediaControlsOpen = true
    }
    GlobalShortcut {
        name: "mediaControlsClose"
        description: "Closes media controls on press"
        onPressed: GlobalStates.mediaControlsOpen = false
    }
}
