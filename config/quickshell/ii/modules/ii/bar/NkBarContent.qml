// NovelKnock bar for ii, rebuilt from end-4's original EWW NovelKnock config.
// Centered group of three pills: [left pages] [workspaces 1-10] [right pages].
// Scroll on a side pill to flip its pages (slides up/down like the original).
//   Left pages:  Music, Focused window
//   Right pages: System, Tray apps, System info
// Colors come from the wallpaper (Appearance.*). Keybinds are unaffected.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item {
    id: root

    property var screen: root.QsWindow.window?.screen
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(root.screen)
    readonly property MprisPlayer player: MprisController.activePlayer

    // Sizes
    readonly property real screenW: root.screen?.width ?? 1920
    readonly property real sideWidth: screenW >= 1800 ? 420 : screenW >= 1500 ? 380 : screenW >= 1250 ? 330 : 270
    readonly property real pillHeight: Math.min(48, root.height - 6)
    readonly property real pillRadius: 12
    readonly property real wsSize: 26
    readonly property real wsSidePad: 15

    // Look
    readonly property string nkFont: "Lexend"
    // Tinted with the wallpaper accent and see-through so Hyprland blur shows (mix weight = first color)
    readonly property color pillColor: ColorUtils.transparentize(ColorUtils.mix(Appearance.colors.colLayer0Base, Appearance.colors.colPrimaryContainer, 0.72), 0.32)
    readonly property color textColor: Appearance.colors.colOnLayer0
    readonly property color accent: Appearance.colors.colPrimary
    readonly property color trackColor: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.78)
    readonly property color wsOccupied: ColorUtils.transparentize(ColorUtils.mix(Appearance.colors.colOnLayer0, Appearance.colors.colPrimary, 0.8), 0.35)
    readonly property color wsEmpty: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.68)

    // Workspaces shown per monitor (matches your Hyprland workspace rules).
    // Monitors not listed here show 1-10 in groups of ten.
    readonly property var nkMonitorRanges: ({
        "HDMI-A-1": [1, 5],
        "DP-3": [6, 10]
    })

    // Slide the group aside when a sidebar opens, like NovelKnock
    // Slide until the group sits 6px from the open sidebar's header
    readonly property real sidebarHeaderInner: Appearance.sizes.sidebarWidth - Appearance.sizes.elevationMargin
    readonly property real groupOffset: {
        const w = group.width, W = root.width;
        if (GlobalStates.sidebarLeftOpen) return (root.sidebarHeaderInner + 6) - (W - w) / 2;
        if (GlobalStates.sidebarRightOpen) return (W - root.sidebarHeaderInner - 6) - (W + w) / 2;
        return 0;
    }

    // ---------- Building blocks ----------
    component NkText: StyledText {
        font.family: root.nkFont
        color: root.textColor
    }

    // A pill with stacked pages; scroll flips pages with a slide
    component PagedPill: Rectangle {
        id: pill
        property int page: 0
        property int pageCount: 1
        property Component trailing: null
        default property alias pages: pageColumn.data
        signal clicked(int button)
        implicitHeight: root.pillHeight
        radius: root.pillRadius
        color: root.pillColor
        clip: true

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton | Qt.BackButton | Qt.ForwardButton
            onPressed: event => pill.clicked(event.button)
            onWheel: event => {
                if (event.angleDelta.y < 0)
                    pill.page = Math.min(pill.pageCount - 1, pill.page + 1);
                else if (event.angleDelta.y > 0)
                    pill.page = Math.max(0, pill.page - 1);
            }
        }

        Loader {
            id: trailingLoader
            active: pill.trailing !== null
            sourceComponent: pill.trailing
            anchors {
                right: parent.right
                rightMargin: pill.pageCount > 1 ? 14 : 8
                verticalCenter: parent.verticalCenter
            }
        }

        Column {
            id: pageColumn
            width: pill.width - (trailingLoader.active ? trailingLoader.width + 18 : 0)
            y: -pill.page * pill.height
            Behavior on y {
                NumberAnimation {
                    duration: 250
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: [0.05, 0.7, 0.1, 1, 1, 1]
                }
            }
        }

        Row { // Small page dots on the right edge
            visible: pill.pageCount > 1
            anchors {
                right: parent.right
                rightMargin: 4
                verticalCenter: parent.verticalCenter
            }
            rotation: 90
            spacing: 3
            Repeater {
                model: pill.pageCount
                Rectangle {
                    required property int index
                    width: 4
                    height: 4
                    radius: 2
                    color: index === pill.page ? root.textColor : root.trackColor
                }
            }
        }
    }

    component Page: Item {
        width: parent?.width ?? 0
        height: root.pillHeight
    }

    component ResourceRow: RowLayout {
        property string icon
        property real value: 0
        spacing: 6
        implicitHeight: 13
        MaterialSymbol {
            Layout.preferredWidth: 17
            Layout.preferredHeight: 13
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: parent.icon
            iconSize: 16
            color: root.textColor
        }
        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: 52
            implicitHeight: 5
            radius: 3
            color: root.trackColor
            Rectangle {
                width: Math.max(height, parent.width * Math.max(0, Math.min(1, parent.parent.value)))
                height: parent.height
                radius: 3
                color: root.accent
                Behavior on width {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
        }
    }

    // ---------- Data ----------
    Timer {
        running: root.player?.playbackState == MprisPlaybackState.Playing
        interval: 1000
        repeat: true
        onTriggered: root.player.positionChanged()
    }

    property string kernel: ""
    property string packages: ""
    property string diskFree: ""
    Process {
        id: sysInfoProc
        running: true
        command: ["bash", "-c", "uname -r; (pacman -Qq 2>/dev/null || true) | wc -l; df -h --output=avail / | tail -1 | tr -d ' '"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                root.kernel = lines[0] ?? "";
                root.packages = lines[1] ?? "";
                root.diskFree = lines[2] ?? "";
            }
        }
    }
    Timer {
        interval: 600000
        running: true
        repeat: true
        onTriggered: sysInfoProc.running = true
    }

    readonly property var latestNotif: Notifications.list.length > 0 ? Notifications.list[Notifications.list.length - 1] : null

    // ---------- Layout ----------
    RowLayout {
        id: group
        spacing: 6
        anchors.verticalCenter: parent.verticalCenter
        x: Math.round((root.width - width) / 2 + root.groupOffset)
        Behavior on x {
            NumberAnimation {
                duration: 600
                easing.type: Easing.BezierSpline
                easing.bezierCurve: [0.05, 0.7, 0.1, 1, 1, 1]
            }
        }

        // ================= LEFT: Music / Colors =================
        PagedPill {
            id: leftPill
            implicitWidth: root.sideWidth
            Layout.preferredWidth: root.sideWidth
            pageCount: 2
            onClicked: button => {
                if (button === Qt.LeftButton)
                    GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen;
                else if (button === Qt.MiddleButton)
                    root.player?.togglePlaying();
                else if (button === Qt.BackButton)
                    root.player?.previous();
                else if (button === Qt.RightButton || button === Qt.ForwardButton)
                    root.player?.next();
            }

            // Page 1: Music
            Page {
                HoverHandler { id: musicHover }

                RowLayout {
                    anchors {
                        fill: parent
                        leftMargin: 8
                        rightMargin: 14
                    }
                    spacing: 8

                    Item { // Cover with play state ring
                        implicitWidth: 36
                        implicitHeight: 36
                        Layout.alignment: Qt.AlignVCenter
                        MouseArea { // Click the cover to open the bottom music sheet
                            anchors.fill: parent
                            z: 10
                            cursorShape: Qt.PointingHandCursor
                            onClicked: GlobalStates.mediaControlsOpen = !GlobalStates.mediaControlsOpen
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: 8
                            color: Appearance.colors.colSecondaryContainer
                            clip: true
                            Image {
                                anchors.fill: parent
                                source: root.player?.trackArtUrl ?? ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                sourceSize.width: 72
                                sourceSize.height: 72
                                visible: status === Image.Ready
                            }
                        }
                        Rectangle {
                            anchors.centerIn: parent
                            width: 26
                            height: 26
                            radius: 13
                            color: ColorUtils.transparentize("#000000", 0.3)
                            border.width: 2
                            border.color: root.textColor
                            MaterialSymbol {
                                anchors.centerIn: parent
                                fill: 1
                                text: root.player?.isPlaying ? "pause" : "play_arrow"
                                iconSize: 16
                                color: root.textColor
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: -2
                        NkText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            font.pixelSize: 16
                            text: root.player ? (StringUtils.cleanMusicTitle(root.player.trackTitle) || "Music") : "Music"
                        }
                        NkText {
                            Layout.fillWidth: true
                            visible: text.length > 0
                            elide: Text.ElideRight
                            font.pixelSize: 12
                            opacity: 0.85
                            text: root.player?.trackArtist ?? ""
                        }
                    }

                    RowLayout { // Controls appear on hover
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 0
                        visible: opacity > 0
                        opacity: musicHover.hovered ? 1 : 0
                        Behavior on opacity {
                            NumberAnimation { duration: 200 }
                        }
                        Repeater {
                            model: [
                                { icon: "skip_previous", run: () => root.player?.previous() },
                                { icon: root.player?.isPlaying ? "pause" : "play_arrow", run: () => root.player?.togglePlaying() },
                                { icon: "skip_next", run: () => root.player?.next() },
                            ]
                            delegate: Rectangle {
                                required property var modelData
                                implicitWidth: 28
                                implicitHeight: 28
                                radius: 8
                                color: btnMouse.pressed ? Appearance.colors.colLayer1Active : btnMouse.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    fill: 1
                                    text: modelData.icon
                                    iconSize: 18
                                    color: root.accent
                                }
                                MouseArea {
                                    id: btnMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: modelData.run()
                                }
                            }
                        }
                    }
                }

                Rectangle { // Song progress along the bottom edge
                    visible: !!root.player && (root.player.length ?? 0) > 0
                    anchors {
                        left: parent.left
                        bottom: parent.bottom
                        leftMargin: root.pillRadius
                        bottomMargin: 2
                    }
                    height: 2
                    radius: 1
                    width: (parent.width - root.pillRadius * 2) * Math.min(1, (root.player?.position ?? 0) / Math.max(1, root.player?.length ?? 1))
                    color: root.accent
                }
            }

            // Page 2: Focused window (app icon, app name, title)
            Page {
                id: windowPage
                readonly property var activeWindow: ToplevelManager.activeToplevel
                readonly property bool focusingThisMonitor: HyprlandData.activeWorkspace?.monitor == root.monitor?.name
                readonly property var biggestWindow: HyprlandData.biggestWindowForWorkspace(HyprlandData.monitors[root.monitor?.id]?.activeWorkspace.id)
                readonly property bool useActive: focusingThisMonitor && (activeWindow?.activated ?? false) && !!biggestWindow
                readonly property string appClass: useActive ? (activeWindow?.appId ?? "") : (biggestWindow?.class ?? "")
                readonly property string winTitle: useActive ? (activeWindow?.title ?? "") : (biggestWindow?.title ?? "")
                readonly property int windowCount: HyprlandData.windowList.filter(w => w.workspace?.id === root.monitor?.activeWorkspace?.id).length

                RowLayout {
                    anchors {
                        fill: parent
                        leftMargin: 10
                        rightMargin: 18
                    }
                    spacing: 10
                    IconImage {
                        Layout.alignment: Qt.AlignVCenter
                        implicitSize: 28
                        visible: windowPage.appClass !== ""
                        source: Quickshell.iconPath(AppSearch.guessIcon(windowPage.appClass), "image-missing")
                    }
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        visible: windowPage.appClass === ""
                        text: "desktop_windows"
                        iconSize: 24
                        color: root.textColor
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: -2
                        NkText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: windowPage.winTitle || `Workspace ${root.monitor?.activeWorkspace?.id ?? 1}`
                            font.pixelSize: 15
                        }
                        NkText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: windowPage.appClass
                                ? `${windowPage.appClass}  •  ${windowPage.windowCount} window${windowPage.windowCount === 1 ? "" : "s"} here`
                                : "Desktop"
                            font.pixelSize: 12
                            opacity: 0.8
                        }
                    }
                }
            }
        }

        // ================= CENTER: Workspaces =================
        Rectangle {
            id: wsPill
            implicitWidth: root.wsSize * wsPill.count + root.wsSidePad * 2
            implicitHeight: root.pillHeight
            radius: root.pillRadius
            color: root.pillColor
            readonly property int activeId: root.monitor?.activeWorkspace?.id ?? 1
            readonly property var fixedRange: root.nkMonitorRanges[root.monitor?.name ?? ""] ?? null
            readonly property int first: fixedRange ? fixedRange[0] : Math.floor((activeId - 1) / 10) * 10 + 1
            readonly property int last: fixedRange ? fixedRange[1] : first + 9
            readonly property int count: last - first + 1
            readonly property int activeIndex: activeId - first
            readonly property bool activeInRange: activeId >= first && activeId <= last

            // Scroll moves one workspace but never past this monitor's first or last one
            function step(delta) {
                const from = wsPill.activeInRange ? wsPill.activeId : (delta > 0 ? wsPill.first - 1 : wsPill.last + 1);
                const target = Math.max(wsPill.first, Math.min(wsPill.last, from + delta));
                if (target !== wsPill.activeId)
                    Hyprland.dispatch(`hl.dsp.focus({workspace = ${target}})`);
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.RightButton | Qt.MiddleButton
                onPressed: GlobalStates.overviewOpen = !GlobalStates.overviewOpen
                onWheel: event => {
                    if (event.angleDelta.y < 0) wsPill.step(1);
                    else if (event.angleDelta.y > 0) wsPill.step(-1);
                }
            }

            Row {
                id: wsRow
                anchors.centerIn: parent
                Repeater {
                    model: wsPill.count
                    delegate: Item {
                        id: ws
                        required property int index
                        readonly property int wsId: wsPill.first + index
                        readonly property bool active: wsPill.activeId === wsId
                        readonly property bool occupied: HyprlandData.windowList.some(w => w.workspace?.id === wsId)
                        width: root.wsSize
                        height: root.wsSize
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 2
                            radius: width / 2
                            color: (ws.occupied || ws.active) ? root.wsOccupied : root.wsEmpty
                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                            }
                        }
                        NkText {
                            anchors.centerIn: parent
                            text: ws.wsId
                            font.pixelSize: 14
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Hyprland.dispatch(`hl.dsp.focus({workspace = ${ws.wsId}})`)
                        }
                    }
                }
            }

            Rectangle { // Sliding active marker above the buttons
                visible: wsPill.activeInRange
                y: Math.max(2, wsRow.y - 6)
                height: 4
                width: root.wsSize - 8
                radius: 2
                color: root.textColor
                x: wsRow.x + wsPill.activeIndex * root.wsSize + 4
                Behavior on x {
                    NumberAnimation {
                        duration: 400
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: [0.05, 0.7, 0.1, 1, 1, 1]
                    }
                }
            }
        }

        // ================= RIGHT: System / Notifications / Info =================
        PagedPill {
            id: rightPill
            implicitWidth: root.sideWidth
            Layout.preferredWidth: root.sideWidth
            pageCount: 3
            onClicked: button => {
                if (button === Qt.LeftButton)
                    GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
                else if (button === Qt.MiddleButton)
                    root.player?.togglePlaying();
                else if (button === Qt.RightButton)
                    root.player?.next();
            }

            // Page 1: System
            Page {
                RowLayout {
                    anchors {
                        fill: parent
                        leftMargin: 14
                        rightMargin: 16
                    }
                    spacing: 10

                    ColumnLayout { // Clock
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: -3
                        NkText {
                            text: DateTime.time
                            font.pixelSize: 17
                            color: root.accent
                        }
                        NkText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: DateTime.longDate
                            font.pixelSize: 12
                            color: root.accent
                        }
                    }

                    ColumnLayout { // Keyboard + layout
                        Layout.alignment: Qt.AlignVCenter
                        visible: root.sideWidth >= 330
                        spacing: -4
                        MaterialSymbol {
                            Layout.alignment: Qt.AlignHCenter
                            text: "keyboard"
                            iconSize: 19
                            color: root.textColor
                        }
                        NkText {
                            Layout.alignment: Qt.AlignHCenter
                            text: (HyprlandXkb.currentLayoutCode || "en").split(":")[0].split("-")[0].slice(0, 3).toUpperCase()
                            font.pixelSize: 10
                            font.weight: Font.Medium
                        }
                    }

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        text: Network.materialSymbol
                        iconSize: 20
                        color: root.textColor
                    }
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        visible: BluetoothStatus.available
                        text: BluetoothStatus.connected ? "bluetooth_connected" : BluetoothStatus.enabled ? "bluetooth" : "bluetooth_disabled"
                        iconSize: 20
                        color: root.textColor
                    }

                    ColumnLayout { // CPU / RAM / swap
                        Layout.alignment: Qt.AlignVCenter
                        visible: root.sideWidth >= 380
                        spacing: 1
                        ResourceRow { icon: "memory"; value: ResourceUsage.cpuUsage }
                        ResourceRow { icon: "memory_alt"; value: ResourceUsage.memoryUsedPercentage }
                        ResourceRow { icon: "swap_horiz"; value: ResourceUsage.swapUsedPercentage }
                    }

                    Item { // Battery ring, or volume ring on desktops
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 34
                        implicitHeight: 34
                        readonly property real level: Battery.available ? Battery.percentage : (Audio.sink?.audio?.volume ?? 0)
                        CircularProgress {
                            anchors.centerIn: parent
                            implicitSize: 32
                            lineWidth: 3
                            value: Math.min(1, parent.level)
                            colPrimary: (Battery.available && Battery.isLowAndNotCharging) ? Appearance.colors.colError : root.accent
                            colSecondary: root.trackColor
                            enableAnimation: false
                        }
                        NkText {
                            anchors.centerIn: parent
                            visible: !(Battery.available && Battery.isCharging)
                            text: Math.round(parent.level * 100)
                            font.pixelSize: 11
                        }
                        MaterialSymbol {
                            anchors.centerIn: parent
                            visible: Battery.available && Battery.isCharging
                            fill: 1
                            text: "bolt"
                            iconSize: 16
                            color: root.accent
                        }
                    }
                }
            }

            // Page 2: Tray apps (replaces NovelKnock's notifications page)
            Page {
                RowLayout {
                    anchors {
                        fill: parent
                        leftMargin: 14
                        rightMargin: 18
                    }
                    spacing: 12
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        text: "apps"
                        iconSize: 22
                        color: root.accent
                    }
                    NkText {
                        Layout.alignment: Qt.AlignVCenter
                        text: "Apps"
                        font.pixelSize: 15
                        color: root.accent
                    }
                    Item { Layout.fillWidth: true }
                    SysTray {
                        Layout.alignment: Qt.AlignVCenter
                        invertSide: Config?.options.bar.bottom
                        showSeparator: false
                    }
                }
            }

            // Page 3: System info
            Page {
                RowLayout {
                    anchors {
                        fill: parent
                        leftMargin: 14
                        rightMargin: 16
                    }
                    spacing: 12

                    CustomIcon {
                        Layout.alignment: Qt.AlignVCenter
                        width: 28
                        height: 28
                        source: SystemInfo.distroIcon
                        colorize: true
                        color: root.accent
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: -2
                        NkText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: root.kernel || SystemInfo.distroName
                            font.pixelSize: 14
                            color: root.accent
                        }
                        NkText {
                            text: root.packages ? `${root.packages} packages` : SystemInfo.distroName
                            font.pixelSize: 12
                            color: root.accent
                        }
                    }
                    NkText {
                        visible: root.diskFree.length > 0
                        text: `${root.diskFree} free disk space`
                        font.pixelSize: 13
                    }
                }
            }
        }
    }
}
