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
    // Mixer rows: streams with the same app name are grouped into one row
    readonly property var appGroups: {
        const groups = {};
        const order = [];
        for (const n of Audio.outputAppNodes) {
            const key = Audio.appNodeDisplayName(n);
            if (!groups[key]) {
                groups[key] = [];
                order.push(key);
            }
            groups[key].push(n);
        }
        return order.map(k => ({ key: k, nodes: groups[k] }));
    }

    // Keep app stream volumes readable
    PwObjectTracker {
        objects: Audio.outputAppNodes
    }

    // ===== Visualizer =====
    // cava stays running while music plays. Starting it opens an audio capture stream, and doing that
    // every time the sheet opened is what made the sound hiccup for a moment.
    readonly property bool visualizerShown: GlobalStates.mediaControlsOpen || root.fullscreen
    readonly property bool cavaWanted: visualizerShown || root.player?.playbackState == MprisPlaybackState.Playing
    onCavaWantedChanged: {
        if (cavaWanted) {
            cavaStopTimer.stop();
            cavaProc.running = true;
        } else {
            cavaStopTimer.restart();
        }
    }
    onVisualizerShownChanged: {
        if (!visualizerShown) root.visualizerPoints = [];
    }
    Component.onCompleted: {
        if (root.cavaWanted) cavaProc.running = true;
    }
    Timer { // stop cava 2 minutes after the music stops
        id: cavaStopTimer
        interval: 120000
        onTriggered: {
            if (!root.cavaWanted) cavaProc.running = false;
        }
    }
    Timer { // cava quit on its own (audio restarted): start it again if it is still wanted
        id: cavaRestartTimer
        interval: 3000
        onTriggered: {
            if (root.cavaWanted) cavaProc.running = true;
        }
    }

    Process { // Audio visualizer (same cava setup ii uses)
        id: cavaProc
        onRunningChanged: {
            if (!running) {
                root.visualizerPoints = [];
                if (root.cavaWanted) cavaRestartTimer.restart();
            }
        }
        command: ["cava", "-p", `${FileUtils.trimFileProtocol(Directories.scriptPath)}/cava/raw_output_config.txt`]
        stdout: SplitParser {
            onRead: data => {
                if (!root.visualizerShown) return; // nothing is showing the bars, skip the work
                root.visualizerPoints = data.split(";").map(p => parseFloat(p.trim())).filter(p => !isNaN(p));
            }
        }
    }

    // ===== Fullscreen view with synced lyrics (Super+Alt+X, or the fullscreen button on the sheet) =====
    property bool fullscreen: false
    readonly property bool sheetOpen: GlobalStates.mediaControlsOpen && !root.fullscreen
    property var fsScreen: null
    property var lyricLines: []        // [{ t: seconds, text }]
    property string lyricPlain: ""
    property string lyricState: "idle" // idle, loading, synced, plain, none
    property int lyricIndex: -1
    property string lyricFor: ""
    readonly property string trackKey: `${root.player?.trackTitle ?? ""}|${root.player?.trackArtist ?? ""}`
    readonly property string lyricsScript: `${FileUtils.trimFileProtocol(Directories.config)}/hypr/custom/scripts/lyrics.py`

    function setFullscreen(on) {
        if (on) {
            const name = Hyprland.focusedMonitor?.name ?? "";
            let found = null;
            for (let i = 0; i < Quickshell.screens.length; i++) {
                if (Quickshell.screens[i].name === name) found = Quickshell.screens[i];
            }
            root.fsScreen = found ?? Quickshell.screens[0];
            GlobalStates.mediaControlsOpen = false;
            root.fullscreen = true;
            root.loadLyrics();
        } else {
            // close on the next tick: hiding the window while it is still handling the key press or
            // click that closed it crashed Quickshell
            Qt.callLater(() => {
                root.fullscreen = false;
            });
        }
    }
    function loadLyrics() {
        if (!root.player || root.trackKey === "|") {
            root.lyricState = "none";
            root.lyricLines = [];
            root.lyricPlain = "";
            return;
        }
        if (root.lyricFor === root.trackKey && root.lyricState !== "idle") return;
        root.lyricFor = root.trackKey;
        root.lyricState = "loading";
        root.lyricLines = [];
        root.lyricPlain = "";
        root.lyricIndex = -1;
        lyricsProc.running = false;
        lyricsProc.command = ["python3", root.lyricsScript, StringUtils.cleanMusicTitle(root.player.trackTitle) || root.player.trackTitle, root.player.trackArtist ?? "", `${Math.round(root.player.length ?? 0)}`];
        lyricsProc.running = true;
    }
    function updateLyricIndex() {
        const t = (root.player?.position ?? 0) + 0.2;
        let i = -1;
        for (let k = 0; k < root.lyricLines.length; k++) {
            if (root.lyricLines[k].t <= t) i = k;
            else break;
        }
        if (i !== root.lyricIndex) root.lyricIndex = i;
    }
    function fmtTime(s) {
        if (!s || s < 0) return "0:00";
        const m = Math.floor(s / 60), sec = Math.floor(s % 60);
        return `${m}:${sec < 10 ? "0" : ""}${sec}`;
    }
    onTrackKeyChanged: {
        if (root.fullscreen) lyricDebounce.restart();
    }
    // While the fullscreen view is open the small sheet never shows. Anything that tries to open it
    // (Super+X, the bar's music pill, the bottom line) closes the fullscreen view instead.
    Connections {
        target: GlobalStates
        function onMediaControlsOpenChanged() {
            if (GlobalStates.mediaControlsOpen && root.fullscreen) {
                Qt.callLater(() => {
                    GlobalStates.mediaControlsOpen = false;
                    root.fullscreen = false;
                });
            }
        }
    }
    Timer { // the title and artist arrive one after the other when the song changes
        id: lyricDebounce
        interval: 600
        onTriggered: root.loadLyrics()
    }
    Timer { // follow the song position closely while the lyrics are on screen
        running: root.fullscreen && root.player?.playbackState == MprisPlaybackState.Playing
        interval: 200
        repeat: true
        onTriggered: {
            root.player.positionChanged();
            root.updateLyricIndex();
        }
    }
    Process {
        id: lyricsProc
        stdout: StdioCollector {
            id: lyricsOut
            onStreamFinished: {
                let r = {};
                try {
                    r = JSON.parse(lyricsOut.text);
                } catch (e) {}
                if (r.found && (r.synced ?? []).length > 0) {
                    root.lyricLines = r.synced.map(l => ({ t: l[0], text: l[1] }));
                    root.lyricState = "synced";
                    root.updateLyricIndex();
                } else if (r.found && (r.plain ?? "").length > 0) {
                    root.lyricPlain = r.plain;
                    root.lyricState = "plain";
                } else {
                    root.lyricState = "none";
                }
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
        visible: root.sheetOpen || sheet.y < sheetWindow.height
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
            y: root.sheetOpen ? Appearance.sizes.hyprlandGapsOut : sheetWindow.height + 10
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
                    model: GlobalStates.mediaControlsOpen ? root.visualizerPoints.length : 0
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
                            { icon: "fullscreen", active: false, run: () => { root.setFullscreen(true) } },
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
                    model: root.appGroups
                    delegate: Rectangle {
                        id: appRow
                        required property var modelData
                        readonly property var nodes: modelData.nodes
                        readonly property var node: modelData.nodes[0]
                        width: mixer.width
                        height: 42
                        radius: 12
                        color: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.35)
                        readonly property real volume: node?.audio?.volume ?? 0
                        readonly property bool muted: node?.audio?.muted ?? false
                        readonly property string iconName: node?.properties?.["application.icon-name"]
                            ?? node?.properties?.["application.process.binary"] ?? "audio-x-generic"
                        function setMuted(m) {
                            for (const n of appRow.nodes) if (n?.audio) n.audio.muted = m;
                        }
                        function setVolume(v) {
                            for (const n of appRow.nodes) if (n?.audio) n.audio.volume = v;
                        }

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
                                text: appRow.nodes.length > 1
                                    ? `${appRow.modelData.key}  •  ${appRow.nodes.length} streams`
                                    : `#${appRow.node?.id ?? ""}  ${appRow.modelData.key}`
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
                            onClicked: appRow.setMuted(!appRow.muted)
                            onWheel: event => {
                                const step = event.angleDelta.y > 0 ? 0.05 : -0.05;
                                appRow.setVolume(Math.max(0, Math.min(1, appRow.volume + step)));
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

    PanelWindow { // fullscreen music view with lyrics
        id: fsWindow
        visible: root.fullscreen
        screen: root.fsScreen ?? Quickshell.screens[0]
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        color: "transparent"
        WlrLayershell.namespace: "quickshell:mediaFullscreen"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        Rectangle {
            id: fsRoot
            anchors.fill: parent
            color: ColorUtils.mix(Appearance.colors.colLayer0Base, "#000000", 0.5)
            focus: true
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    root.setFullscreen(false);
                } else if (event.key === Qt.Key_Space) {
                    root.player?.togglePlaying();
                } else if (event.key === Qt.Key_Right) {
                    root.player?.next();
                } else if (event.key === Qt.Key_Left) {
                    root.player?.previous();
                }
                event.accepted = true;
            }
            Connections {
                target: root
                function onFullscreenChanged() {
                    if (root.fullscreen) fsRoot.forceActiveFocus();
                }
            }

            // ---- background: blurred cover + dark tint ----
            Image {
                id: fsCover
                anchors.fill: parent
                visible: false
                source: root.player?.trackArtUrl ?? ""
                asynchronous: true
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: 480
                sourceSize.height: 480
            }
            FastBlur {
                anchors.fill: parent
                visible: fsCover.status === Image.Ready
                source: fsCover
                radius: 96
            }
            Rectangle {
                anchors.fill: parent
                color: ColorUtils.transparentize(ColorUtils.mix(Appearance.colors.colLayer0Base, "#000000", 0.45), fsCover.status === Image.Ready ? 0.42 : 0.05)
            }

            // ---- visualizer along the bottom ----
            Row {
                id: fsBars
                anchors {
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                    leftMargin: 40
                    rightMargin: 40
                }
                height: parent.height * 0.28
                readonly property real barWidth: 10
                spacing: root.visualizerPoints.length > 0 ? (width - barWidth * root.visualizerPoints.length) / Math.max(1, root.visualizerPoints.length - 1) : 0
                Repeater {
                    model: root.visualizerPoints.length
                    delegate: Rectangle {
                        required property int index
                        anchors.bottom: parent.bottom
                        width: fsBars.barWidth
                        radius: 4
                        height: Math.min(fsBars.height, (root.visualizerPoints[index] ?? 0) / 1000 * fsBars.height)
                        color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.72)
                        Behavior on height {
                            NumberAnimation { duration: 60 }
                        }
                    }
                }
            }

            // ---- close ----
            Rectangle {
                anchors {
                    top: parent.top
                    right: parent.right
                    margins: 24
                }
                z: 5
                width: 44
                height: 44
                radius: 22
                color: fsCloseMouse.containsMouse ? ColorUtils.transparentize("#ffffff", 0.75) : ColorUtils.transparentize("#000000", 0.55)
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "close_fullscreen"
                    iconSize: 22
                    color: "#ffffff"
                }
                MouseArea {
                    id: fsCloseMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.setFullscreen(false)
                }
            }

            RowLayout {
                anchors {
                    fill: parent
                    leftMargin: parent.width * 0.07
                    rightMargin: parent.width * 0.07
                    topMargin: parent.height * 0.1
                    bottomMargin: parent.height * 0.12
                }
                spacing: parent.width * 0.05

                // ---- left: cover, title, progress, controls ----
                ColumnLayout {
                    Layout.preferredWidth: Math.min(460, fsRoot.width * 0.3)
                    Layout.maximumWidth: Math.min(460, fsRoot.width * 0.3)
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 14

                    Rectangle {
                        id: fsArt
                        Layout.preferredWidth: Math.min(460, fsRoot.width * 0.3)
                        Layout.preferredHeight: width
                        radius: 18
                        color: Appearance.colors.colSecondaryContainer
                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: fsArt.width
                                height: fsArt.height
                                radius: fsArt.radius
                            }
                        }
                        Image {
                            anchors.fill: parent
                            visible: status === Image.Ready
                            source: fsCover.source
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize.width: 920
                            sourceSize.height: 920
                        }
                        MaterialSymbol {
                            anchors.centerIn: parent
                            visible: fsCover.status !== Image.Ready
                            fill: 1
                            text: "music_note"
                            iconSize: 120
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.topMargin: 8
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        font.family: root.nkFont
                        font.pixelSize: 34
                        font.weight: Font.DemiBold
                        color: "#ffffff"
                        text: root.player ? (StringUtils.cleanMusicTitle(root.player.trackTitle) || "Music") : "Nothing playing"
                    }
                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        font.family: root.nkFont
                        font.pixelSize: 20
                        color: "#ffffff"
                        opacity: 0.8
                        text: root.player?.trackArtist ?? ""
                    }

                    // progress bar, click to seek
                    Item {
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        implicitHeight: 18
                        readonly property real frac: (root.player?.length ?? 0) > 0 ? Math.max(0, Math.min(1, (root.player?.position ?? 0) / root.player.length)) : 0
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            height: 6
                            radius: 3
                            color: ColorUtils.transparentize("#ffffff", 0.75)
                            Rectangle {
                                width: parent.width * parent.parent.frac
                                height: parent.height
                                radius: 3
                                color: Appearance.colors.colPrimary
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: mouse => {
                                if (root.player?.canSeek && (root.player.length ?? 0) > 0) {
                                    root.player.position = mouse.x / width * root.player.length;
                                    root.updateLyricIndex();
                                }
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        StyledText {
                            font.family: root.nkFont
                            font.pixelSize: 13
                            color: "#ffffff"
                            opacity: 0.8
                            text: root.fmtTime(root.player?.position)
                        }
                        Item {
                            Layout.fillWidth: true
                        }
                        StyledText {
                            font.family: root.nkFont
                            font.pixelSize: 13
                            color: "#ffffff"
                            opacity: 0.8
                            text: root.fmtTime(root.player?.length)
                        }
                    }

                    // controls
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 10
                        Repeater {
                            model: [
                                { icon: "skip_previous", big: false, run: () => root.player?.previous() },
                                { icon: root.player?.isPlaying ? "pause" : "play_arrow", big: true, run: () => root.player?.togglePlaying() },
                                { icon: "skip_next", big: false, run: () => root.player?.next() },
                            ]
                            delegate: Rectangle {
                                id: fsCtl
                                required property var modelData
                                implicitWidth: modelData.big ? 64 : 48
                                implicitHeight: implicitWidth
                                radius: implicitWidth / 2
                                color: modelData.big ? (fsCtlMouse.containsMouse ? Appearance.colors.colPrimaryHover : Appearance.colors.colPrimary)
                                    : fsCtlMouse.containsMouse ? ColorUtils.transparentize("#ffffff", 0.8) : "transparent"
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    fill: 1
                                    text: fsCtl.modelData.icon
                                    iconSize: fsCtl.modelData.big ? 34 : 28
                                    color: fsCtl.modelData.big ? Appearance.colors.colOnPrimary : "#ffffff"
                                }
                                MouseArea {
                                    id: fsCtlMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: fsCtl.modelData.run()
                                }
                            }
                        }
                    }
                }

                // ---- right: lyrics ----
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    ListView { // synced lyrics: the current line stays in the middle
                        id: lyricList
                        anchors.fill: parent
                        visible: root.lyricState === "synced"
                        clip: true
                        spacing: 14
                        model: root.lyricLines
                        currentIndex: Math.max(0, root.lyricIndex)
                        highlightRangeMode: ListView.ApplyRange
                        preferredHighlightBegin: height / 2 - 40
                        preferredHighlightEnd: height / 2 + 40
                        highlightMoveDuration: 450
                        highlightFollowsCurrentItem: true
                        boundsBehavior: Flickable.StopAtBounds
                        header: Item {
                            width: 1
                            height: lyricList.height / 2 - 40
                        }
                        footer: Item {
                            width: 1
                            height: lyricList.height / 2
                        }
                        delegate: StyledText {
                            id: lyricLine
                            required property var modelData
                            required property int index
                            readonly property bool current: index === root.lyricIndex
                            width: lyricList.width
                            wrapMode: Text.Wrap
                            font.family: root.nkFont
                            font.pixelSize: current ? 38 : 30
                            font.weight: current ? Font.DemiBold : Font.Normal
                            color: "#ffffff"
                            opacity: current ? 1 : index < root.lyricIndex ? 0.32 : 0.5
                            text: modelData.text.length > 0 ? modelData.text : "♪"
                            Behavior on opacity {
                                NumberAnimation { duration: 250 }
                            }
                            Behavior on font.pixelSize {
                                NumberAnimation { duration: 200 }
                            }
                            MouseArea { // click a line to jump there
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.player?.canSeek) {
                                        root.player.position = lyricLine.modelData.t;
                                        root.updateLyricIndex();
                                    }
                                }
                            }
                        }
                    }

                    Flickable { // lyrics without timing
                        anchors.fill: parent
                        visible: root.lyricState === "plain"
                        clip: true
                        contentHeight: plainLyrics.implicitHeight + 40
                        boundsBehavior: Flickable.StopAtBounds
                        StyledText {
                            id: plainLyrics
                            width: parent.width
                            wrapMode: Text.Wrap
                            font.family: root.nkFont
                            font.pixelSize: 26
                            lineHeight: 1.35
                            color: "#ffffff"
                            opacity: 0.9
                            text: root.lyricPlain
                        }
                    }

                    ColumnLayout { // loading or nothing found
                        anchors.centerIn: parent
                        visible: root.lyricState === "loading" || root.lyricState === "none" || root.lyricState === "idle"
                        spacing: 10
                        MaterialSymbol {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.lyricState === "loading" ? "hourglass_top" : "lyrics"
                            iconSize: 56
                            color: "#ffffff"
                            opacity: 0.6
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            font.family: root.nkFont
                            font.pixelSize: 20
                            color: "#ffffff"
                            opacity: 0.7
                            text: root.lyricState === "loading" ? "Looking for lyrics..." : !root.player ? "Nothing is playing" : "No lyrics found for this song"
                        }
                    }

                    StyledText { // credit and hint
                        anchors {
                            right: parent.right
                            bottom: parent.bottom
                        }
                        font.family: root.nkFont
                        font.pixelSize: 12
                        color: "#ffffff"
                        opacity: 0.45
                        text: root.lyricState === "plain" ? "These lyrics have no timing, scroll to read  •  LRCLIB" : root.lyricState === "synced" ? "Click a line to jump  •  Esc to close  •  Lyrics from LRCLIB" : "Esc to close"
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
        function fullscreen(): void {
            root.setFullscreen(!root.fullscreen);
        }
    }
    GlobalShortcut {
        name: "mediaFullscreenToggle"
        description: "Toggles the fullscreen music view with lyrics"
        onPressed: root.setFullscreen(!root.fullscreen)
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
