// "Knock" left sidebar, rebuilt from end-4's NovelKnock (EWW) for ii.
// Sections: header, music card, Favourite settings / Culture (scroll the title), Resources, Quote.
// Colors come from the wallpaper. Opens and closes with the same keybinds as before.
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.models.hyprland
import qs.modules.common.models.quickToggles
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

Item {
    id: root
    required property var scopeRoot
    anchors.fill: parent

    readonly property string nkFont: "Lexend"
    readonly property color cardColor: ColorUtils.transparentize(ColorUtils.mix(Appearance.colors.colLayer0Base, Appearance.colors.colPrimaryContainer, 0.82), 0.3)
    readonly property color sectionColor: ColorUtils.transparentize(ColorUtils.mix(Appearance.colors.colLayer0Base, Appearance.colors.colPrimaryContainer, 0.6), 0.35)
    readonly property color textColor: Appearance.colors.colOnLayer0
    readonly property color accent: Appearance.colors.colPrimary
    readonly property color trackColor: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.78)
    readonly property MprisPlayer player: MprisController.activePlayer
    property int favouritePage: 0 // 0: Favourite settings, 1: Culture

    function focusActiveItem() {}

    // "Unhover to close": closes when the mouse leaves after having been inside
    property bool wasHovered: false
    HoverHandler {
        id: sidebarHover
        onHoveredChanged: {
            if (hovered) root.wasHovered = true;
            else if (root.wasHovered && GlobalStates.sidebarLeftOpen && !root.scopeRoot.pin && !root.scopeRoot.detach) {
                root.wasHovered = false;
                GlobalStates.sidebarLeftOpen = false;
            }
        }
    }
    Connections {
        target: GlobalStates
        function onSidebarLeftOpenChanged() {
            if (!GlobalStates.sidebarLeftOpen) root.wasHovered = false;
        }
    }

    component NkText: StyledText {
        font.family: root.nkFont
        color: root.textColor
    }

    component SectionTitle: Rectangle {
        property string icon
        property string title
        property string hint
        Layout.fillWidth: true
        implicitHeight: 38
        radius: 12
        color: root.sectionColor
        RowLayout {
            anchors {
                fill: parent
                leftMargin: 10
                rightMargin: 12
            }
            spacing: 8
            MaterialSymbol {
                text: parent.parent.icon
                iconSize: 20
                color: root.textColor
            }
            NkText {
                Layout.fillWidth: true
                text: parent.parent.title
                font.pixelSize: 18
            }
            NkText {
                text: parent.parent.hint
                font.pixelSize: 12
                opacity: 0.8
            }
        }
    }

    component Card: Rectangle {
        radius: 13
        color: root.cardColor
    }

    component Ring: Item {
        property real value: 0
        property string icon
        property real size: 55
        property real thickness: 4
        implicitWidth: size
        implicitHeight: size
        CircularProgress {
            anchors.centerIn: parent
            implicitSize: parent.size
            lineWidth: parent.thickness
            value: Math.max(0, Math.min(1, parent.value))
            colPrimary: root.accent
            colSecondary: root.trackColor
            enableAnimation: false
        }
        MaterialSymbol {
            anchors.centerIn: parent
            text: parent.icon
            iconSize: parent.size * 0.38
            color: root.textColor
        }
    }

    component Chip: Rectangle {
        property alias text: chipText.text
        implicitWidth: chipText.implicitWidth + 16
        implicitHeight: chipText.implicitHeight + 4
        radius: 7
        color: ColorUtils.transparentize(root.accent, 0.75)
        NkText {
            id: chipText
            anchors.centerIn: parent
            font.family: Appearance.font.family.monospace
            font.pixelSize: 12
        }
    }

    // A toggle row bound to a Hyprland option
    component HyprToggle: Card {
        id: toggle
        property string icon
        property string label
        property string optionKey
        Layout.fillWidth: true
        implicitHeight: 46
        HyprlandConfigOption {
            id: option
            key: toggle.optionKey
        }
        readonly property bool isOn: Number(option.value) === 1 || option.value === true
        RowLayout {
            anchors {
                fill: parent
                leftMargin: 12
                rightMargin: 10
            }
            spacing: 8
            MaterialSymbol {
                text: toggle.icon
                iconSize: 18
                color: root.textColor
            }
            NkText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: toggle.label
                font.pixelSize: 13
            }
            StyledSwitch {
                checked: toggle.isOn
                onClicked: {
                    const newValue = checked ? 1 : 0;
                    option.value = newValue;
                    option.setValue(newValue);
                    checked = Qt.binding(() => toggle.isOn); // keep following the real Hyprland value
                }
            }
        }
    }

    // A toggle row driven by one of ii's quick toggle models (game mode, night light, ...)
    component ModelToggle: Card {
        id: mt
        property var model
        property string iconOverride: ""
        Layout.fillWidth: true
        implicitHeight: 46
        RowLayout {
            anchors {
                fill: parent
                leftMargin: 12
                rightMargin: 10
            }
            spacing: 8
            MaterialSymbol {
                text: mt.iconOverride || (mt.model?.icon ?? "")
                iconSize: 18
                color: root.textColor
            }
            NkText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: mt.model?.name ?? ""
                font.pixelSize: 13
            }
            StyledSwitch {
                checked: mt.model?.toggled ?? false
                onClicked: {
                    mt.model?.mainAction();
                    checked = Qt.binding(() => mt.model?.toggled ?? false);
                }
            }
        }
    }

    GameModeToggle { id: gameModeModel }

    // ---------- Data ----------
    Timer {
        running: GlobalStates.sidebarLeftOpen && root.player?.playbackState == MprisPlaybackState.Playing
        interval: 1000
        repeat: true
        onTriggered: root.player.positionChanged()
    }

    property string diskFree: ""
    property string diskSize: ""
    property real diskFreeFraction: 0
    Process {
        id: diskProc
        running: GlobalStates.sidebarLeftOpen
        command: ["bash", "-c", "df -h --output=avail,size / | tail -1; df --output=avail,size / | tail -1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                const human = (lines[0] ?? "").trim().split(/\s+/);
                const raw = (lines[1] ?? "").trim().split(/\s+/);
                root.diskFree = human[0] ?? "";
                root.diskSize = human[1] ?? "";
                root.diskFreeFraction = (raw.length > 1 && Number(raw[1]) > 0) ? Number(raw[0]) / Number(raw[1]) : 0;
            }
        }
    }

    function formatGb(kb) {
        return `${(kb / 1024 / 1024).toFixed(1)}G`;
    }

    // ---------- Layout ----------
    // NovelKnock style: the header sits up in the bar row, the panel starts below it
    readonly property real headerHeight: Math.min(48, Appearance.sizes.barHeight - 6)
    readonly property color headerColor: ColorUtils.transparentize(ColorUtils.mix(Appearance.colors.colLayer0Base, Appearance.colors.colPrimaryContainer, 0.72), 0.32)

    Rectangle { // Header pill
        id: knockHeader
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }
        height: root.headerHeight
        radius: 12
        color: root.headerColor
        RowLayout {
            anchors {
                fill: parent
                leftMargin: 14
                rightMargin: 16
            }
            spacing: 10
            MaterialSymbol {
                text: "graphic_eq"
                iconSize: 22
                color: root.textColor
            }
            NkText {
                Layout.fillWidth: true
                text: "Knock"
                font.pixelSize: 19
            }
            NkText {
                text: "Unhover to close"
                font.pixelSize: 12
                opacity: 0.85
            }
        }
    }

    StyledRectangularShadow {
        target: knockBody
    }
    Rectangle { // Panel body
        id: knockBody
        anchors {
            top: knockHeader.bottom
            topMargin: 8
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        radius: 14
        color: Appearance.colors.colLayer0
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

    Flickable {
        anchors.fill: parent
        anchors.margins: 10
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: column
            width: parent.width
            spacing: 8

            // ===== Music card =====
            Rectangle {
                id: musicCard
                Layout.fillWidth: true
                implicitHeight: 190
                radius: 13
                color: root.cardColor
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: musicCard.width
                        height: musicCard.height
                        radius: musicCard.radius
                    }
                }
                readonly property bool hasArt: coverArt.status === Image.Ready

                Image {
                    id: coverArt
                    visible: false
                    source: root.player?.trackArtUrl ?? ""
                    asynchronous: true
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: 400
                    sourceSize.height: 400
                }
                FastBlur {
                    anchors.fill: parent
                    visible: musicCard.hasArt
                    source: coverArt
                    radius: 40
                }
                Rectangle { // Accent tint so text stays readable
                    anchors.fill: parent
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: ColorUtils.transparentize(ColorUtils.mix(Appearance.colors.colPrimaryContainer, "#000000", 0.55), musicCard.hasArt ? 0.1 : 0) }
                        GradientStop { position: 1.0; color: ColorUtils.transparentize(ColorUtils.mix(Appearance.colors.colPrimaryContainer, "#000000", 0.75), musicCard.hasArt ? 0.35 : 0) }
                    }
                }
                Image { // Sharp cover in the middle, like the video
                    anchors.centerIn: parent
                    width: 120
                    height: 120
                    visible: musicCard.hasArt
                    source: coverArt.source
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    opacity: 0.35
                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: 120
                            height: 120
                            radius: 60
                        }
                    }
                }

                ColumnLayout {
                    anchors {
                        fill: parent
                        margins: 14
                    }
                    spacing: 4

                    RowLayout { // Source app + output chip
                        Layout.fillWidth: true
                        MaterialSymbol {
                            text: (root.player?.identity ?? "").toLowerCase().includes("spotify") ? "library_music"
                                : (root.player?.identity ?? "").toLowerCase().match(/firefox|chrom|zen|brave/) ? "smart_display" : "music_note"
                            iconSize: 24
                            color: Appearance.colors.colOnPrimaryContainer
                        }
                        Item { Layout.fillWidth: true }
                        Rectangle {
                            implicitWidth: outputRow.implicitWidth + 18
                            implicitHeight: 26
                            radius: 13
                            color: root.accent
                            RowLayout {
                                id: outputRow
                                anchors.centerIn: parent
                                spacing: 4
                                MaterialSymbol {
                                    text: (Audio.sink?.description ?? "").toLowerCase().match(/head|ear|bluez|buds/) ? "headphones" : "speaker"
                                    iconSize: 16
                                    color: Appearance.colors.colOnPrimary
                                }
                                NkText {
                                    Layout.maximumWidth: 150
                                    elide: Text.ElideRight
                                    text: (Audio.sink?.description ?? "").toLowerCase().match(/head|ear|bluez|buds/) ? "Headphones" : "Speakers"
                                    font.pixelSize: 12
                                    color: Appearance.colors.colOnPrimary
                                }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }

                    RowLayout { // Title + big play button
                        Layout.fillWidth: true
                        spacing: 10
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: -2
                            NkText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: root.player ? (StringUtils.cleanMusicTitle(root.player.trackTitle) || "Music") : "Music"
                                font.pixelSize: 17
                                color: Appearance.colors.colOnPrimaryContainer
                            }
                            NkText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                visible: text.length > 0
                                text: root.player?.trackArtist ?? ""
                                font.pixelSize: 13
                                color: Appearance.colors.colOnPrimaryContainer
                            }
                        }
                        Rectangle {
                            implicitWidth: 46
                            implicitHeight: 46
                            radius: 12
                            color: playMouse.pressed ? Appearance.colors.colPrimaryActive : playMouse.containsMouse ? Appearance.colors.colPrimaryHover : root.accent
                            MaterialSymbol {
                                anchors.centerIn: parent
                                fill: 1
                                text: root.player?.isPlaying ? "pause" : "play_arrow"
                                iconSize: 26
                                color: Appearance.colors.colOnPrimary
                            }
                            MouseArea {
                                id: playMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: root.player?.togglePlaying()
                            }
                        }
                    }

                    RowLayout { // prev | seek | next
                        Layout.fillWidth: true
                        spacing: 8
                        MaterialSymbol {
                            text: "skip_previous"
                            fill: 1
                            iconSize: 20
                            color: Appearance.colors.colOnPrimaryContainer
                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.player?.previous()
                            }
                        }
                        Item {
                            Layout.fillWidth: true
                            implicitHeight: 14
                            readonly property real progress: (root.player && root.player.length > 0) ? Math.min(1, root.player.position / root.player.length) : 0
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width
                                height: 4
                                radius: 2
                                color: ColorUtils.transparentize("#c8c8c8", 0.4)
                                Rectangle {
                                    width: parent.width * parent.parent.progress
                                    height: parent.height
                                    radius: 2
                                    color: Appearance.colors.colOnPrimaryContainer
                                }
                            }
                            Rectangle {
                                x: Math.max(0, parent.width * parent.progress - width / 2)
                                anchors.verticalCenter: parent.verticalCenter
                                width: 12
                                height: 12
                                radius: 6
                                color: Appearance.colors.colOnPrimaryContainer
                            }
                            MouseArea {
                                anchors.fill: parent
                                enabled: root.player?.canSeek ?? false
                                onPressed: mouse => root.player.position = root.player.length * Math.max(0, Math.min(1, mouse.x / width))
                            }
                        }
                        MaterialSymbol {
                            text: "skip_next"
                            fill: 1
                            iconSize: 20
                            color: Appearance.colors.colOnPrimaryContainer
                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.player?.next()
                            }
                        }
                    }
                }
            }

            // ===== Favourite settings / Culture =====
            SectionTitle {
                icon: root.favouritePage === 0 ? "favorite" : "palette"
                title: root.favouritePage === 0 ? "Favourite settings" : "Culture"
                hint: root.favouritePage === 0 ? ">>" : "<<  safe for work"
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.favouritePage = 1 - root.favouritePage
                    onWheel: event => {
                        if (event.angleDelta.y < 0) root.favouritePage = 1;
                        else if (event.angleDelta.y > 0) root.favouritePage = 0;
                    }
                }
            }

            // Page 1: Favourite settings
            ColumnLayout {
                visible: root.favouritePage === 0
                Layout.fillWidth: true
                spacing: 6

                Card { // Mouse sensitivity
                    Layout.fillWidth: true
                    implicitHeight: 56
                    HyprlandConfigOption {
                        id: sensOption
                        key: "input:sensitivity"
                    }
                    RowLayout {
                        anchors {
                            fill: parent
                            leftMargin: 12
                            rightMargin: 12
                        }
                        spacing: 10
                        ColumnLayout {
                            spacing: -2
                            MaterialSymbol {
                                text: "arrow_selector_tool"
                                iconSize: 20
                                color: root.textColor
                            }
                            NkText {
                                text: `Accel: ${Number(sensOption.value ?? 0).toFixed(1)}`
                                font.pixelSize: 11
                            }
                        }
                        StyledSlider {
                            Layout.fillWidth: true
                            from: -1
                            to: 1
                            value: Number(sensOption.value ?? 0)
                            usePercentTooltip: false
                            tooltipContent: value.toFixed(2)
                            onMoved: sensOption.setValue(value.toFixed(2))
                        }
                    }
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: 6
                    rowSpacing: 6
                    HyprToggle { icon: "blur_on"; label: "Enable blur"; optionKey: "decoration:blur:enabled" }
                    HyprToggle { icon: "preview"; label: "Blur xray"; optionKey: "decoration:blur:xray" }
                    HyprToggle { icon: "animation"; label: "Animations"; optionKey: "animations:enabled" }
                    HyprToggle { icon: "shadow"; label: "Shadows"; optionKey: "decoration:shadow:enabled" }
                    ModelToggle { model: gameModeModel }
                    Card { // Do not disturb
                        Layout.fillWidth: true
                        implicitHeight: 46
                        RowLayout {
                            anchors {
                                fill: parent
                                leftMargin: 12
                                rightMargin: 10
                            }
                            spacing: 8
                            MaterialSymbol {
                                text: "do_not_disturb_on"
                                iconSize: 18
                                color: root.textColor
                            }
                            NkText {
                                Layout.fillWidth: true
                                text: "Do not disturb"
                                font.pixelSize: 13
                            }
                            StyledSwitch {
                                checked: Notifications.silent
                                onClicked: {
                                    Notifications.silent = !Notifications.silent;
                                    checked = Qt.binding(() => Notifications.silent);
                                }
                            }
                        }
                    }
                }

                Card { // Wallpaper position dropdown (needs the patched linux-wallpaperengine)
                    id: wallCard
                    Layout.fillWidth: true
                    implicitHeight: wallColumn.implicitHeight + 16
                    property bool expanded: false
                    property string screenName: Quickshell.screens.length > 0 ? Quickshell.screens[0].name : ""
                    property var tweaks: ({}) // { "DP-3": { zoom, x, y }, ... }
                    readonly property var current: tweaks[screenName] ?? { zoom: 1, x: 0, y: 0 }

                    function setValue(key, value) {
                        const all = Object.assign({}, wallCard.tweaks);
                        const t = Object.assign({ zoom: 1, x: 0, y: 0 }, all[wallCard.screenName] ?? {});
                        t[key] = Math.round(value * 1000) / 1000;
                        all[wallCard.screenName] = t;
                        wallCard.tweaks = all;
                        saveTimer.restart();
                    }
                    function resetScreen() {
                        const all = Object.assign({}, wallCard.tweaks);
                        all[wallCard.screenName] = { zoom: 1, x: 0, y: 0 };
                        wallCard.tweaks = all;
                        saveTimer.restart();
                    }

                    FileView {
                        id: viewFile
                        path: FileUtils.trimFileProtocol(`${Directories.config}/linux-wallpaperengine/view.json`)
                        onLoaded: {
                            try {
                                wallCard.tweaks = JSON.parse(viewFile.text());
                            } catch (e) {
                                wallCard.tweaks = {};
                            }
                        }
                    }
                    Timer { // write at most ~12 times a second while dragging
                        id: saveTimer
                        interval: 80
                        onTriggered: {
                            Quickshell.execDetached(["mkdir", "-p", FileUtils.trimFileProtocol(`${Directories.config}/linux-wallpaperengine`)]);
                            viewFile.setText(JSON.stringify(wallCard.tweaks, null, 2));
                        }
                    }

                    component WallSlider: RowLayout {
                        id: ws
                        property string label
                        property real from: 0
                        property real to: 1
                        property real value: 0
                        property real defaultValue: 0
                        property string suffix: ""
                        signal moved(real v)
                        Layout.fillWidth: true
                        spacing: 10
                        NkText {
                            Layout.preferredWidth: 42
                            text: ws.label
                            font.pixelSize: 12
                        }
                        Item {
                            id: wsTrack
                            Layout.fillWidth: true
                            implicitHeight: 18
                            readonly property real frac: (ws.value - ws.from) / (ws.to - ws.from)
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width
                                height: 4
                                radius: 2
                                color: root.trackColor
                                Rectangle {
                                    width: parent.width * Math.max(0, Math.min(1, wsTrack.frac))
                                    height: parent.height
                                    radius: 2
                                    color: root.accent
                                }
                            }
                            Rectangle {
                                x: Math.max(0, Math.min(parent.width - width, parent.width * wsTrack.frac - width / 2))
                                anchors.verticalCenter: parent.verticalCenter
                                width: 12
                                height: 12
                                radius: 6
                                color: root.accent
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                function setFrom(px) {
                                    const f = Math.max(0, Math.min(1, px / width));
                                    ws.moved(ws.from + f * (ws.to - ws.from));
                                }
                                onPressed: mouse => setFrom(mouse.x)
                                onPositionChanged: mouse => { if (pressed) setFrom(mouse.x); }
                                onDoubleClicked: ws.moved(ws.defaultValue)
                                onWheel: event => {
                                    const step = (ws.to - ws.from) / 100;
                                    ws.moved(Math.max(ws.from, Math.min(ws.to, ws.value + (event.angleDelta.y > 0 ? step : -step))));
                                }
                            }
                        }
                        NkText {
                            Layout.preferredWidth: 44
                            horizontalAlignment: Text.AlignRight
                            text: `${ws.value.toFixed(2)}${ws.suffix}`
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: 11
                            opacity: 0.85
                        }
                    }

                    ColumnLayout {
                        id: wallColumn
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                            margins: 8
                            leftMargin: 12
                            rightMargin: 12
                        }
                        spacing: 8

                        RowLayout { // Dropdown header
                            Layout.fillWidth: true
                            spacing: 8
                            MaterialSymbol {
                                text: "wallpaper"
                                iconSize: 18
                                color: root.textColor
                            }
                            NkText {
                                Layout.fillWidth: true
                                text: "Wallpaper position"
                                font.pixelSize: 13
                            }
                            MaterialSymbol {
                                text: wallCard.expanded ? "expand_less" : "expand_more"
                                iconSize: 20
                                color: root.textColor
                            }
                            TapHandler {
                                onTapped: wallCard.expanded = !wallCard.expanded
                            }
                        }

                        ColumnLayout {
                            visible: wallCard.expanded
                            Layout.fillWidth: true
                            spacing: 6

                            Flow { // Monitor picker
                                Layout.fillWidth: true
                                spacing: 4
                                Repeater {
                                    model: Quickshell.screens
                                    delegate: Rectangle {
                                        required property var modelData
                                        readonly property bool selected: wallCard.screenName === modelData.name
                                        width: monText.implicitWidth + 16
                                        height: 24
                                        radius: 8
                                        color: selected ? root.accent : monMouse.containsMouse ? Appearance.colors.colLayer1Hover : root.cardColor
                                        NkText {
                                            id: monText
                                            anchors.centerIn: parent
                                            text: modelData.name
                                            font.pixelSize: 11
                                            color: parent.selected ? Appearance.colors.colOnPrimary : root.textColor
                                        }
                                        MouseArea {
                                            id: monMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: wallCard.screenName = modelData.name
                                        }
                                    }
                                }
                            }

                            WallSlider {
                                label: "Zoom"
                                from: 1
                                to: 3
                                defaultValue: 1
                                suffix: "x"
                                value: Number(wallCard.current.zoom ?? 1)
                                onMoved: v => wallCard.setValue("zoom", v)
                            }
                            WallSlider {
                                label: "X"
                                from: -1
                                to: 1
                                defaultValue: 0
                                value: Number(wallCard.current.x ?? 0)
                                onMoved: v => wallCard.setValue("x", v)
                            }
                            WallSlider {
                                label: "Y"
                                from: -1
                                to: 1
                                defaultValue: 0
                                value: Number(wallCard.current.y ?? 0)
                                onMoved: v => wallCard.setValue("y", v)
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                NkText {
                                    Layout.fillWidth: true
                                    text: "Double-click a slider to reset it"
                                    font.pixelSize: 11
                                    opacity: 0.65
                                }
                                Rectangle {
                                    implicitWidth: resetText.implicitWidth + 20
                                    implicitHeight: 26
                                    radius: 8
                                    color: resetWallMouse.containsMouse ? Appearance.colors.colLayer1Hover : root.sectionColor
                                    NkText {
                                        id: resetText
                                        anchors.centerIn: parent
                                        text: `Reset ${wallCard.screenName}`
                                        font.pixelSize: 12
                                    }
                                    MouseArea {
                                        id: resetWallMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: wallCard.resetScreen()
                                    }
                                }
                            }
                        }
                    }
                }

                Card { // Reload config
                    Layout.fillWidth: true
                    implicitHeight: 40
                    color: reloadMouse.containsMouse ? Appearance.colors.colLayer1Hover : root.cardColor
                    NkText {
                        anchors.centerIn: parent
                        text: "Reload config"
                        font.pixelSize: 13
                    }
                    MouseArea {
                        id: reloadMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: Quickshell.execDetached(["hyprctl", "reload"])
                    }
                }
            }

            // Page 2: Culture (safe-for-work anime images, source is changeable)
            ColumnLayout {
                id: culture
                visible: root.favouritePage === 1
                Layout.fillWidth: true
                Layout.preferredHeight: 470
                spacing: 6

                property string imageUrl: ""
                property string webUrl: ""
                property string category: ""
                property string status: ""
                property string usedSource: ""
                property bool loading: false
                property int requestId: 0
                property string source: "auto"
                readonly property var defaultTags: ["waifu", "neko", "shinobu", "megumin", "smile", "happy", "wink", "wave", "pat", "hug", "dance", "blush", "cuddle", "highfive"]
                // Your tag buttons, saved in ~/.config/illogical-impulse/knock-tags.json
                property var tagList: defaultTags
                function cleanTag(t) {
                    return (t ?? "").trim().toLowerCase().replace(/\s+/g, "_").replace(/[^a-z0-9_().:-]/g, "");
                }
                function saveTags() {
                    tagsFile.setText(JSON.stringify(culture.tagList, null, 2));
                }
                function addTag(t) {
                    const tag = culture.cleanTag(t);
                    if (!tag || culture.tagList.includes(tag)) return;
                    culture.tagList = culture.tagList.concat([tag]);
                    culture.saveTags();
                }
                function removeTag(tag) {
                    culture.tagList = culture.tagList.filter(t => t !== tag);
                    culture.saveTags();
                }
                function resetTags() {
                    culture.tagList = culture.defaultTags;
                    culture.saveTags();
                }
                function openTag(tag) {
                    // Built-in names use their mapped tags; anything else is searched as typed
                    if (culture.danbooruMap[tag] !== undefined) culture.fetch(tag);
                    else culture.fetch("custom", tag);
                }
                FileView {
                    id: tagsFile
                    path: FileUtils.trimFileProtocol(`${Directories.config}/illogical-impulse/knock-tags.json`)
                    onLoaded: {
                        try {
                            const saved = JSON.parse(tagsFile.text());
                            if (Array.isArray(saved) && saved.length > 0)
                                culture.tagList = saved.map(t => culture.cleanTag(String(t))).filter(t => t !== "");
                        } catch (e) {
                            console.log("[Knock] could not read knock-tags.json: " + e);
                        }
                    }
                }
                readonly property var sources: [
                    { id: "auto", label: "Auto" },
                    { id: "danbooru", label: "Danbooru" },
                    { id: "safebooru", label: "Safebooru" },
                    { id: "konachan", label: "Konachan" },
                    { id: "yandere", label: "yande.re" },
                    { id: "waifupics", label: "waifu.pics" },
                    { id: "nekosbest", label: "nekos.best" },
                ]
                // Tags per site family (all searches are limited to safe-for-work ratings)
                readonly property var danbooruMap: ({
                    "waifu": "1girl", "neko": "cat_ears", "shinobu": "oshino_shinobu", "megumin": "megumin",
                    "smile": "smile", "happy": "happy", "wink": "one_eye_closed", "wave": "waving", "pat": "headpat",
                    "hug": "hug", "dance": "dancing", "blush": "blush", "cuddle": "cuddling", "highfive": "high_five"
                })
                readonly property var moebooruMap: ({
                    "waifu": "", "neko": "animal_ears", "shinobu": "oshino_shinobu", "megumin": "megumin",
                    "smile": "smile", "happy": "", "wink": "wink", "wave": "", "pat": "",
                    "hug": "hug", "dance": "", "blush": "blush", "cuddle": "", "highfive": ""
                })
                readonly property var nekosMap: ({
                    "waifu": "waifu", "neko": "neko", "shinobu": "waifu", "megumin": "waifu",
                    "smile": "smile", "happy": "happy", "wink": "wink", "wave": "wave", "pat": "pat",
                    "hug": "hug", "dance": "dance", "blush": "blush", "cuddle": "cuddle", "highfive": "highfive"
                })

                Component {
                    id: cultureProcComp
                    Process {
                        id: proc
                        property var onDone: null
                        stdout: StdioCollector {
                            onStreamFinished: {
                                if (proc.onDone) proc.onDone(text);
                                proc.destroy();
                            }
                        }
                    }
                }

                // cat: one of the buttons, or a custom search when customTag is given
                function fetch(cat, customTag) {
                    if (!cat) return;
                    const custom = culture.cleanTag(customTag);
                    if (customTag !== undefined && custom === "") return;
                    culture.category = custom ? `#${custom}` : cat;
                    culture.loading = true;
                    culture.status = "";
                    culture.imageUrl = "";
                    culture.webUrl = "";
                    culture.usedSource = "";
                    const myId = ++culture.requestId;
                    const DB = encodeURIComponent(custom || (culture.danbooruMap[cat] ?? "1girl"));
                    const KB = encodeURIComponent(custom || (culture.moebooruMap[cat] ?? ""));
                    const NB = custom ? "waifu" : (culture.nekosMap[cat] ?? "waifu");
                    // waifu.pics and nekos.best only have fixed categories, so they are skipped for custom searches
                    const allSources = custom ? "danbooru safebooru konachan yandere" : "danbooru safebooru konachan yandere waifupics nekosbest";
                    const SOURCES = culture.source === "auto" ? allSources : culture.source;
                    const script = `DB='${DB}'; KB='${KB}'; CAT='${custom ? "waifu" : cat}'; NB='${NB}'; SOURCES='${SOURCES}'; CUSTOM='${custom ? 1 : 0}'; TAG='${custom}'
UA="Mozilla/5.0 (X11; Linux x86_64) Quickshell-Knock"
get() { curl -g -sS -L -m 8 -A "$UA" -w "\\n%{http_code}" "$1" 2>/dev/null; }
code() { printf '%s' "$1" | tail -n1; }
pick() { printf '%s' "$1" | grep -o "\\"$2\\" *: *\\"[^\\"]*\\"" | head -n1 | sed 's/.*"\\(http[^"]*\\)"/\\1/'; }
field() { printf '%s' "$1" | grep -o "\\"$2\\" *: *\\"[^\\"]*\\"" | head -n1 | sed 's/.*: *"\\([^"]*\\)"$/\\1/'; }
enc() { printf '%s' "$1" | sed 's/%/%25/g; s/(/%28/g; s/)/%29/g; s/:/%3A/g; s/ /_/g'; }
report() { c=$(code "$2"); if [ "$c" = 200 ] || [ "$c" = 404 ]; then echo "code:$1 no results"; else echo "code:$1 $c"; fi; }
show() {
  rm -f "\${XDG_RUNTIME_DIR:-/tmp}"/knock-culture-*
  f="\${XDG_RUNTIME_DIR:-/tmp}/knock-culture-$(date +%s%N)"
  if ! curl -sS -L -m 20 -A "$UA" -e "$3" -o "$f" "$1" 2>/dev/null; then echo "bad:$2 download failed"; return 1; fi
  mt=$(file -b --mime-type "$f" 2>/dev/null)
  case "$mt" in
    image/jpeg) ext=jpg ;; image/png) ext=png ;; image/gif) ext=gif ;; image/webp) ext=webp ;;
    *) echo "bad:$2 sent $mt"; rm -f "$f"; return 1 ;;
  esac
  mv "$f" "$f.$ext"
  echo "file:$f.$ext"; echo "src:$2"; [ -n "$4" ] && echo "tag:$4"; echo "$1"; exit 0
}
src_danbooru() {
  t2=""; t="$DB"; b=$(get "https://danbooru.donmai.us/posts/random.json?tags=rating:general+$t"); u=$(pick "$b" large_file_url)
  if [ -z "$u" ] && [ "$CUSTOM" = 1 ]; then
    t2=$(field "$(get "https://danbooru.donmai.us/autocomplete.json?search[query]=$DB&search[type]=tag_query&limit=1")" value)
    if [ -n "$t2" ] && [ "$t2" != "$TAG" ]; then t=$(enc "$t2"); b=$(get "https://danbooru.donmai.us/posts/random.json?tags=rating:general+$t"); u=$(pick "$b" large_file_url); fi
  fi
  [ -n "$u" ] && show "$u" Danbooru "https://danbooru.donmai.us/" "$t2"; report Danbooru "$b"
}
src_safebooru() {
  q() {
    b=$(get "https://safebooru.org/index.php?page=dapi&s=post&q=index&json=1&limit=1&tags=sort:random+$1")
    u=$(pick "$b" file_url)
    if [ -z "$u" ]; then
      d=$(printf '%s' "$b" | grep -o '"directory" *: *"\\?[^",}]*' | head -n1 | sed 's/.*: *"\\?//')
      i=$(field "$b" image)
      [ -n "$d" ] && [ -n "$i" ] && u="https://safebooru.org/images/$d/$i"
    fi
  }
  t2=""; q "$DB"
  if [ -z "$u" ] && [ "$CUSTOM" = 1 ]; then
    t2=$(field "$(get "https://safebooru.org/autocomplete.php?q=$DB")" value)
    [ -n "$t2" ] && [ "$t2" != "$TAG" ] && q "$(enc "$t2")"
  fi
  [ -n "$u" ] && show "$u" Safebooru "https://safebooru.org/" "$t2"; report Safebooru "$b"
}
moe() { # $1 site name, $2 base url, $3 safe rating tag
  t2=""; b=$(get "$2/post.json?limit=1&tags=order:random+$3+$KB"); u=$(pick "$b" sample_url)
  if [ -z "$u" ] && [ "$CUSTOM" = 1 ]; then
    t2=$(field "$(get "$2/tag.json?name_pattern=$KB&order=count&limit=1")" name)
    if [ -n "$t2" ] && [ "$t2" != "$TAG" ]; then b=$(get "$2/post.json?limit=1&tags=order:random+$3+$(enc "$t2")"); u=$(pick "$b" sample_url); fi
  fi
  [ -n "$u" ] && show "$u" "$1" "$2/" "$t2"; report "$1" "$b"
}
src_konachan() { moe Konachan "https://konachan.net" rating:safe; }
src_yandere() { moe yande.re "https://yande.re" rating:s; }
src_waifupics() { b=$(get "https://api.waifu.pics/sfw/$CAT"); u=$(pick "$b" url); [ -n "$u" ] && show "$u" waifu.pics "https://waifu.pics/"; report waifu.pics "$b"; }
src_nekosbest() { b=$(get "https://nekos.best/api/v2/$NB"); u=$(pick "$b" url); [ -n "$u" ] && show "$u" nekos.best "https://nekos.best/"; report nekos.best "$b"; }
for s in $SOURCES; do "src_$s"; done
`;
                    const p = cultureProcComp.createObject(culture, { command: ["bash", "-c", script] });
                    p.onDone = text => {
                        if (myId !== culture.requestId) return; // a newer click already started
                        const lines = text.trim().split("\n");
                        const url = lines.find(l => l.startsWith("http")) ?? "";
                        const file = lines.find(l => l.startsWith("file:")) ?? "";
                        const src = lines.find(l => l.startsWith("src:")) ?? "";
                        const resolved = lines.find(l => l.startsWith("tag:")) ?? "";
                        culture.loading = false;
                        if (url && file) {
                            culture.webUrl = url;
                            culture.usedSource = resolved ? `${src.slice(4)} · ${resolved.slice(4)}` : src.slice(4);
                            culture.imageUrl = `file://${file.slice(5)}`;
                        } else {
                            const codes = lines.filter(l => l.startsWith("code:") || l.startsWith("bad:")).map(l => l.slice(l.indexOf(":") + 1)).join(", ");
                            culture.status = codes.includes("no results")
                                ? `No pictures found (${codes}). Try the full tag name, e.g. elaina_(majo_no_tabitabi).`
                                : `Couldn't load an image (${codes || "no response"}). Try another source.`;
                            console.log(`[Knock] image fetch failed: ${text}`);
                        }
                    };
                    p.running = true;
                }

                Flow { // Source picker
                    Layout.fillWidth: true
                    spacing: 4
                    Repeater {
                        model: culture.sources
                        delegate: Rectangle {
                            required property var modelData
                            width: srcText.implicitWidth + 16
                            height: 24
                            radius: 8
                            color: culture.source === modelData.id ? root.accent : srcMouse.containsMouse ? Appearance.colors.colLayer1Hover : root.cardColor
                            NkText {
                                id: srcText
                                anchors.centerIn: parent
                                text: modelData.label
                                font.pixelSize: 11
                                color: culture.source === modelData.id ? Appearance.colors.colOnPrimary : root.textColor
                            }
                            MouseArea {
                                id: srcMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    culture.source = modelData.id;
                                    if (culture.category.startsWith("#")) culture.fetch("custom", culture.category.slice(1));
                                    else if (culture.category) culture.fetch(culture.category);
                                }
                            }
                        }
                    }
                }

                Rectangle { // Search your own tags
                    Layout.fillWidth: true
                    implicitHeight: 34
                    radius: 10
                    color: root.cardColor
                    border.width: tagField.activeFocus ? 1 : 0
                    border.color: root.accent
                    RowLayout {
                        anchors {
                            fill: parent
                            leftMargin: 10
                            rightMargin: 4
                        }
                        spacing: 6
                        MaterialSymbol {
                            text: "search"
                            iconSize: 18
                            color: root.textColor
                        }
                        TextField {
                            id: tagField
                            Layout.fillWidth: true
                            placeholderText: "Search tags, e.g. hatsune_miku or blue_hair"
                            placeholderTextColor: ColorUtils.transparentize(root.textColor, 0.45)
                            color: root.textColor
                            font.family: root.nkFont
                            font.pixelSize: 13
                            background: null
                            selectByMouse: true
                            onAccepted: culture.fetch("custom", text)
                        }
                        Rectangle { // Add the typed tag to your buttons
                            implicitWidth: 28
                            implicitHeight: 28
                            radius: 8
                            color: pinMouse.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "bookmark_add"
                                iconSize: 18
                                color: root.textColor
                            }
                            MouseArea {
                                id: pinMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    culture.addTag(tagField.text);
                                    tagField.text = "";
                                }
                            }
                            StyledToolTip {
                                text: "Add to tag buttons"
                                extraVisibleCondition: pinMouse.containsMouse
                            }
                        }
                        Rectangle {
                            implicitWidth: 28
                            implicitHeight: 28
                            radius: 8
                            color: goMouse.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "arrow_forward"
                                iconSize: 18
                                color: root.textColor
                            }
                            MouseArea {
                                id: goMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: culture.fetch("custom", tagField.text)
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 8

                    ColumnLayout {
                        Layout.preferredWidth: 120
                        Layout.minimumWidth: 120
                        Layout.maximumWidth: 120
                        Layout.fillWidth: false
                        Layout.fillHeight: true
                        spacing: 4

                        ListView {
                            id: tagListView
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: 4
                            model: culture.tagList
                            delegate: Rectangle {
                                id: tagButton
                                required property string modelData
                                readonly property bool selected: culture.category === modelData || culture.category === `#${modelData}`
                                width: ListView.view.width
                                height: 28
                                radius: 9
                                color: selected ? root.accent : tagMouse.containsMouse ? Appearance.colors.colLayer1Hover : root.cardColor
                                NkText {
                                    anchors {
                                        left: parent.left
                                        right: parent.right
                                        leftMargin: 8
                                        rightMargin: 22
                                        verticalCenter: parent.verticalCenter
                                    }
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                    text: tagButton.modelData
                                    font.pixelSize: 12
                                    color: tagButton.selected ? Appearance.colors.colOnPrimary : root.textColor
                                }
                                MouseArea {
                                    id: tagMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: event => {
                                        if (event.button === Qt.RightButton) culture.removeTag(tagButton.modelData);
                                        else culture.openTag(tagButton.modelData);
                                    }
                                }
                                MaterialSymbol { // Remove button, shows on hover
                                    anchors {
                                        right: parent.right
                                        rightMargin: 5
                                        verticalCenter: parent.verticalCenter
                                    }
                                    visible: tagMouse.containsMouse || removeMouse.containsMouse
                                    text: "close"
                                    iconSize: 14
                                    color: tagButton.selected ? Appearance.colors.colOnPrimary : root.textColor
                                    MouseArea {
                                        id: removeMouse
                                        anchors.fill: parent
                                        anchors.margins: -4
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: culture.removeTag(tagButton.modelData)
                                    }
                                }
                            }
                        }

                        Rectangle { // Reset to the default buttons
                            Layout.fillWidth: true
                            implicitHeight: 24
                            radius: 8
                            color: resetMouse.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"
                            NkText {
                                anchors.centerIn: parent
                                text: "Reset tags"
                                font.pixelSize: 11
                                opacity: 0.8
                            }
                            MouseArea {
                                id: resetMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: culture.resetTags()
                            }
                        }
                    }

                    Card {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        AnimatedImage {
                            id: waifuImage
                            anchors.fill: parent
                            anchors.margins: 6
                            source: culture.imageUrl
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            playing: visible
                        }
                        NkText {
                            anchors.centerIn: parent
                            width: parent.width - 30
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
                            visible: culture.imageUrl === "" || waifuImage.status !== Image.Ready
                            text: culture.status !== "" ? culture.status
                                : (culture.loading || waifuImage.status === Image.Loading) ? "Loading..."
                                : waifuImage.status === Image.Error ? `The ${culture.usedSource} image downloaded but couldn't be shown. Try another source.`
                                : "Pick a tag"
                            font.pixelSize: 14
                            opacity: 0.8
                        }
                        Rectangle { // Which site the picture came from
                            visible: culture.usedSource !== "" && waifuImage.status === Image.Ready
                            anchors {
                                right: parent.right
                                bottom: parent.bottom
                                margins: 10
                            }
                            width: usedText.implicitWidth + 14
                            height: 22
                            radius: 8
                            color: ColorUtils.transparentize("#000000", 0.4)
                            NkText {
                                id: usedText
                                anchors.centerIn: parent
                                text: culture.usedSource
                                font.pixelSize: 11
                                color: "#ffffff"
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: culture.webUrl !== ""
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Qt.openUrlExternally(culture.webUrl)
                        }
                    }
                }
            }

            // ===== Resources (shown with Favourite settings, like the original) =====
            SectionTitle {
                visible: root.favouritePage === 0
                icon: "monitoring"
                title: "Resources"
            }
            RowLayout {
                visible: root.favouritePage === 0
                Layout.fillWidth: true
                spacing: 8

                Card { // CPU
                    implicitWidth: 120
                    implicitHeight: 170
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 12
                        Ring {
                            Layout.alignment: Qt.AlignHCenter
                            size: 76
                            thickness: 5
                            icon: "settings_slow_motion"
                            value: ResourceUsage.cpuUsage
                        }
                        Chip {
                            Layout.alignment: Qt.AlignHCenter
                            text: `${Math.round(ResourceUsage.cpuUsage * 100)}%`
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Repeater {
                            model: [
                                { icon: "memory", value: ResourceUsage.memoryUsedPercentage, label: `${root.formatGb(ResourceUsage.memoryUsed)}/${root.formatGb(ResourceUsage.memoryTotal)}` },
                                { icon: "swap_horiz", value: ResourceUsage.swapUsedPercentage, label: `${root.formatGb(ResourceUsage.swapUsed)}/${root.formatGb(ResourceUsage.swapTotal)}` },
                                Battery.available
                                    ? { icon: "bolt", value: Battery.percentage, label: `${Math.round(Battery.percentage * 100)}%` }
                                    : { icon: "volume_up", value: Audio.sink?.audio?.volume ?? 0, label: `${Math.round((Audio.sink?.audio?.volume ?? 0) * 100)}%` },
                            ]
                            delegate: Card {
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 112
                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: 10
                                    Ring {
                                        Layout.alignment: Qt.AlignHCenter
                                        icon: modelData.icon
                                        value: modelData.value
                                    }
                                    Chip {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: modelData.label
                                    }
                                }
                            }
                        }
                    }
                    Card { // Disk
                        Layout.fillWidth: true
                        implicitHeight: 50
                        RowLayout {
                            anchors {
                                fill: parent
                                leftMargin: 12
                                rightMargin: 10
                            }
                            spacing: 10
                            MaterialSymbol {
                                text: "hard_drive"
                                iconSize: 18
                                color: root.textColor
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 5
                                radius: 3
                                color: root.trackColor
                                Rectangle {
                                    width: parent.width * root.diskFreeFraction
                                    height: parent.height
                                    radius: 3
                                    color: root.accent
                                }
                            }
                            Chip {
                                text: root.diskFree ? `${root.diskFree}/${root.diskSize} free` : "..."
                            }
                        }
                    }
                }
            }

            // ===== Quote =====
            SectionTitle {
                id: quoteTitle
                icon: "format_quote"
                title: "Quote!"
                hint: `${quoteBox.index + 1}/${quoteBox.quotes.length}`
            }
            Card {
                id: quoteBox
                Layout.fillWidth: true
                implicitHeight: Math.max(110, quoteColumn.implicitHeight + 24)
                // Edit these to add your own quotes
                property list<var> quotes: [
                    { text: "Keep it simple, then make it pretty.", by: "your desktop" },
                    { text: "It works on my machine, and my machine is beautiful.", by: "every ricer" },
                    { text: "One more tweak, then I'll sleep.", by: "you, 3 AM" },
                    { text: "Backups first, regrets never.", by: "past you" },
                    { text: "A clean config is a happy config.", by: "the dotfiles" },
                    { text: "Small steps still move you forward.", by: "unknown" },
                    { text: "Done is better than perfect.", by: "unknown" },
                    { text: "Rest is part of the work.", by: "unknown" },
                    { text: "Stay curious.", by: "unknown" },
                ]
                property int index: 0
                ColumnLayout {
                    id: quoteColumn
                    anchors {
                        fill: parent
                        margins: 12
                    }
                    spacing: 6
                    NkText {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        wrapMode: Text.Wrap
                        verticalAlignment: Text.AlignTop
                        text: quoteBox.quotes[quoteBox.index]?.text ?? ""
                        font.pixelSize: 13
                    }
                    NkText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignRight
                        text: `- ${quoteBox.quotes[quoteBox.index]?.by ?? ""}`
                        font.pixelSize: 12
                        opacity: 0.85
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onPressed: event => {
                        const n = quoteBox.quotes.length;
                        quoteBox.index = event.button === Qt.RightButton ? (quoteBox.index - 1 + n) % n : (quoteBox.index + 1) % n;
                    }
                    onWheel: event => {
                        const n = quoteBox.quotes.length;
                        quoteBox.index = event.angleDelta.y < 0 ? (quoteBox.index + 1) % n : (quoteBox.index - 1 + n) % n;
                    }
                }
            }
        }
    }
    }
}
