// "System" right sidebar, rebuilt from end-4's NovelKnock (EWW) for ii.
// Header, quick toggles + brightness, notifications, then calendar and todo side by side.
// Reuses ii's own notification, calendar and todo widgets so they keep working the same.
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import qs.modules.ii.sidebarRight.bluetoothDevices
import qs.modules.ii.sidebarRight.wifiNetworks

Item {
    id: root
    implicitWidth: Appearance.sizes.sidebarWidth
    implicitHeight: 800

    readonly property string nkFont: "Lexend"
    readonly property color bgColor: ColorUtils.transparentize(ColorUtils.mix(Appearance.colors.colLayer0Base, Appearance.colors.colPrimaryContainer, 0.88), 0.25)
    // ColorUtils.mix(a, b, w): w is the weight of a
    readonly property color cardColor: ColorUtils.transparentize(ColorUtils.mix(Appearance.colors.colLayer0Base, Appearance.colors.colPrimaryContainer, 0.75), 0.3)
    readonly property color sectionColor: ColorUtils.transparentize(ColorUtils.mix(Appearance.colors.colLayer0Base, Appearance.colors.colPrimaryContainer, 0.6), 0.35)
    readonly property color textColor: Appearance.colors.colOnLayer0
    readonly property color accent: Appearance.colors.colPrimary
    property var screen: root.QsWindow.window?.screen
    readonly property var brightnessMonitor: Brightness.getMonitorForScreen(root.screen)

    // Wi-Fi and Bluetooth lists open inside the sidebar (the little arrow on each toggle)
    property bool showWifiDialog: false
    property bool showEthernetDialog: false
    property bool showBluetoothDialog: false
    Connections {
        target: GlobalStates
        function onSidebarRightOpenChanged() {
            if (!GlobalStates.sidebarRightOpen) {
                root.showWifiDialog = false;
                root.showEthernetDialog = false;
                root.showBluetoothDialog = false;
            }
        }
    }

    // "Unhover to close"
    property bool wasHovered: false
    HoverHandler {
        onHoveredChanged: {
            if (hovered) root.wasHovered = true;
            else if (root.wasHovered && GlobalStates.sidebarRightOpen) {
                root.wasHovered = false;
                GlobalStates.sidebarRightOpen = false;
            }
        }
    }
    Connections {
        target: GlobalStates
        function onSidebarRightOpenChanged() {
            if (!GlobalStates.sidebarRightOpen) root.wasHovered = false;
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
        default property alias extra: titleRow.data
        Layout.fillWidth: true
        implicitHeight: 38
        radius: 12
        color: root.sectionColor
        RowLayout {
            id: titleRow
            anchors {
                fill: parent
                leftMargin: 10
                rightMargin: 8
            }
            spacing: 8
            MaterialSymbol {
                text: titleRow.parent.icon
                iconSize: 20
                color: root.textColor
            }
            NkText {
                Layout.fillWidth: true
                text: titleRow.parent.title
                font.pixelSize: 18
            }
            NkText {
                visible: text.length > 0
                text: titleRow.parent.hint
                font.pixelSize: 12
                opacity: 0.85
            }
        }
    }

    // Toggle square + chevron, like NovelKnock's wifi / bluetooth buttons
    component SplitToggle: Row {
        property string icon
        property bool isOn: false
        property var toggle: () => {}
        property var more: () => {}
        spacing: 2
        Rectangle {
            width: 44
            height: 40
            topLeftRadius: 10
            bottomLeftRadius: 10
            topRightRadius: 4
            bottomRightRadius: 4
            color: parent.isOn ? root.accent : root.cardColor
            MaterialSymbol {
                anchors.centerIn: parent
                fill: 1
                text: parent.parent.icon
                iconSize: 20
                color: parent.parent.isOn ? Appearance.colors.colOnPrimary : root.textColor
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: parent.parent.toggle()
            }
        }
        Rectangle {
            width: 24
            height: 40
            topLeftRadius: 4
            bottomLeftRadius: 4
            topRightRadius: 10
            bottomRightRadius: 10
            color: parent.isOn ? ColorUtils.transparentize(root.accent, 0.3) : root.cardColor
            MaterialSymbol {
                anchors.centerIn: parent
                text: "chevron_right"
                iconSize: 18
                color: parent.parent.isOn ? Appearance.colors.colOnPrimary : root.textColor
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: parent.parent.more()
            }
        }
    }

    component IconButton: Rectangle {
        property string icon
        property var action: () => {}
        width: 40
        height: 40
        radius: 10
        color: btnMouse.pressed ? Appearance.colors.colLayer1Active : btnMouse.containsMouse ? Appearance.colors.colLayer1Hover : root.cardColor
        MaterialSymbol {
            anchors.centerIn: parent
            text: parent.icon
            iconSize: 20
            color: root.textColor
        }
        MouseArea {
            id: btnMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.action()
        }
    }

    // NovelKnock style: the header sits up in the bar row, the panel starts below it
    readonly property real headerHeight: Math.min(48, Appearance.sizes.barHeight - 6)
    readonly property color headerColor: ColorUtils.transparentize(ColorUtils.mix(Appearance.colors.colLayer0Base, Appearance.colors.colPrimaryContainer, 0.72), 0.32)
    property string armedAction: "" // power / reboot / logout need a second click
    Timer {
        id: disarmTimer
        interval: 3000
        onTriggered: root.armedAction = ""
    }

    Rectangle { // Header pill
        id: systemHeader
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
                text: "settings"
                iconSize: 22
                color: root.textColor
            }
            NkText {
                Layout.fillWidth: true
                text: "System"
                font.pixelSize: 19
            }
            NkText {
                text: `Up ${DateTime.uptime}  •  Unhover to close`
                font.pixelSize: 12
                opacity: 0.85
            }
        }
    }

    StyledRectangularShadow {
        target: background
    }
    Rectangle {
        id: background
        anchors {
            top: systemHeader.bottom
            topMargin: 8
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        radius: 14
        color: root.bgColor
        border.width: 1
        border.color: ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.6)

        ColumnLayout {
            anchors {
                fill: parent
                margins: 10
            }
            spacing: 8

            // ===== Quick toggles =====
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                SplitToggle {
                    icon: Network.ethernet ? "lan" : Network.wifiEnabled ? "wifi" : "wifi_off"
                    isOn: Network.ethernet || Network.wifiEnabled
                    toggle: () => Network.toggleWifi()
                    more: () => {
                        if (Network.ethernet) root.showEthernetDialog = true;
                        else root.showWifiDialog = true;
                    }
                }
                SplitToggle {
                    visible: BluetoothStatus.available
                    icon: BluetoothStatus.connected ? "bluetooth_connected" : BluetoothStatus.enabled ? "bluetooth" : "bluetooth_disabled"
                    isOn: BluetoothStatus.enabled
                    toggle: () => {
                        if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter.enabled;
                    }
                    more: () => root.showBluetoothDialog = true
                }

                Rectangle { // Brightness, thin slider like NovelKnock
                    Layout.fillWidth: true
                    implicitHeight: 40
                    radius: 10
                    color: root.cardColor
                    RowLayout {
                        anchors {
                            fill: parent
                            leftMargin: 10
                            rightMargin: 12
                        }
                        spacing: 8
                        MaterialSymbol {
                            text: "light_mode"
                            iconSize: 18
                            color: root.textColor
                        }
                        Item {
                            id: briTrack
                            Layout.fillWidth: true
                            implicitHeight: 16
                            readonly property real level: root.brightnessMonitor?.brightness ?? 0.5
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width
                                height: 4
                                radius: 2
                                color: ColorUtils.transparentize(root.textColor, 0.75)
                                Rectangle {
                                    width: parent.width * briTrack.level
                                    height: parent.height
                                    radius: 2
                                    color: root.accent
                                }
                            }
                            Rectangle {
                                x: Math.max(0, Math.min(parent.width - width, parent.width * briTrack.level - width / 2))
                                anchors.verticalCenter: parent.verticalCenter
                                width: 12
                                height: 12
                                radius: 6
                                color: root.accent
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                function setFrom(x) {
                                    root.brightnessMonitor?.setBrightness(Math.max(0.01, Math.min(1, x / width)));
                                }
                                onPressed: mouse => setFrom(mouse.x)
                                onPositionChanged: mouse => { if (pressed) setFrom(mouse.x); }
                                onWheel: event => root.brightnessMonitor?.setBrightness(Math.max(0.01, Math.min(1, briTrack.level + (event.angleDelta.y > 0 ? 0.05 : -0.05))))
                            }
                        }
                    }
                }

                Rectangle { // Session buttons, like NovelKnock
                    implicitWidth: powerRow.implicitWidth + 8
                    implicitHeight: 40
                    radius: 10
                    color: root.cardColor
                    Row {
                        id: powerRow
                        anchors.centerIn: parent
                        spacing: 2
                        Repeater {
                            model: [
                                { id: "lock", icon: "lock", tip: "Lock", confirm: false, run: () => Session.lock() },
                                { id: "sleep", icon: "bedtime", tip: "Sleep", confirm: false, run: () => Session.suspend() },
                                { id: "logout", icon: "logout", tip: "Log out", confirm: true, run: () => Session.logout() },
                                { id: "power", icon: "power_settings_new", tip: "Shut down", confirm: true, run: () => Session.poweroff() },
                                { id: "reboot", icon: "restart_alt", tip: "Restart", confirm: true, run: () => Session.reboot() },
                            ]
                            delegate: Rectangle {
                                id: pBtn
                                required property var modelData
                                readonly property bool armed: root.armedAction === modelData.id
                                width: 32
                                height: 32
                                radius: 8
                                color: armed ? Appearance.colors.colError : pMouse.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: pBtn.modelData.icon
                                    iconSize: 18
                                    color: pBtn.armed ? Appearance.colors.colOnError : root.textColor
                                }
                                MouseArea {
                                    id: pMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (pBtn.modelData.confirm && !pBtn.armed) {
                                            root.armedAction = pBtn.modelData.id; // first click: arm
                                            disarmTimer.restart();
                                            return;
                                        }
                                        root.armedAction = "";
                                        GlobalStates.sidebarRightOpen = false;
                                        pBtn.modelData.run();
                                    }
                                }
                                StyledToolTip {
                                    text: pBtn.armed ? `Click again to ${pBtn.modelData.tip.toLowerCase()}` : pBtn.modelData.tip
                                    extraVisibleCondition: pMouse.containsMouse
                                }
                            }
                        }
                    }
                }

                Rectangle { // ">" opens ii settings
                    implicitWidth: 30
                    implicitHeight: 40
                    radius: 10
                    color: setMouse.containsMouse ? Appearance.colors.colPrimaryHover : root.accent
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "chevron_right"
                        iconSize: 20
                        color: Appearance.colors.colOnPrimary
                    }
                    MouseArea {
                        id: setMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            GlobalStates.sidebarRightOpen = false;
                            Quickshell.execDetached(["qs", "-p", Quickshell.shellPath("settings.qml")]);
                        }
                    }
                    StyledToolTip {
                        text: "Settings"
                        extraVisibleCondition: setMouse.containsMouse
                    }
                }
            }

            // ===== Notifications =====
            SectionTitle {
                icon: "notifications"
                title: "Notifications"
                hint: Notifications.list.length > 0 ? `${Notifications.list.length}` : ""
                Rectangle {
                    visible: Notifications.list.length > 0
                    implicitWidth: 28
                    implicitHeight: 28
                    radius: 8
                    color: clearAllMouse.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "clear_all"
                        iconSize: 18
                        color: root.textColor
                    }
                    MouseArea {
                        id: clearAllMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: Notifications.discardAllNotifications()
                    }
                }
            }

            ListView { // Simple notification list, newest first
                id: notifList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 2
                model: Notifications.list.slice().reverse()
                delegate: Rectangle {
                    id: notifRow
                    required property var modelData
                    width: ListView.view.width
                    height: notifCol.implicitHeight + 14
                    radius: 10
                    color: notifMouse.containsMouse ? ColorUtils.transparentize(root.textColor, 0.93) : "transparent"
                    ColumnLayout {
                        id: notifCol
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: 10
                            rightMargin: 10
                        }
                        spacing: 0
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            NkText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: notifRow.modelData.summary
                                font.pixelSize: 13
                            }
                            NkText {
                                Layout.maximumWidth: 170
                                elide: Text.ElideRight
                                text: `${notifRow.modelData.appName} • ${Qt.formatTime(new Date(notifRow.modelData.time), "hh:mm")}`
                                font.pixelSize: 11
                                opacity: 0.8
                            }
                        }
                        NkText {
                            Layout.fillWidth: true
                            visible: text.length > 0
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            text: notifRow.modelData.body
                            font.pixelSize: 12
                            opacity: 0.8
                        }
                    }
                    MouseArea { // Middle or right click dismisses
                        id: notifMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.MiddleButton | Qt.RightButton
                        onClicked: Notifications.discardNotification(notifRow.modelData.notificationId)
                    }
                }
                NkText {
                    anchors.centerIn: parent
                    visible: notifList.count === 0
                    text: "No notifications"
                    font.pixelSize: 13
                    opacity: 0.6
                }
            }

            // ===== Calendar + Todo =====
            SectionTitle {
                id: calTitle
                property int monthOffset: 0
                readonly property date viewDate: {
                    const now = new Date();
                    return new Date(now.getFullYear(), now.getMonth() + monthOffset, 1);
                }
                icon: "calendar_month"
                title: Qt.formatDate(viewDate, "MMMM yyyy")
                hint: "Scroll to change month"
            }
            Connections { // keep the calendar on this month when the sidebar reopens
                target: GlobalStates
                function onSidebarRightOpenChanged() {
                    if (GlobalStates.sidebarRightOpen) calTitle.monthOffset = 0;
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: 250
                spacing: 8

                Item { // Calendar grid
                    id: calendar
                    Layout.preferredWidth: 7 * 34
                    Layout.fillHeight: true
                    readonly property int firstWeekday: (calTitle.viewDate.getDay() + 6) % 7 // Monday first
                    readonly property date today: new Date()

                    Grid {
                        anchors.top: parent.top
                        columns: 7
                        Repeater {
                            model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
                            delegate: Item {
                                required property string modelData
                                width: 34
                                height: 26
                                NkText {
                                    anchors.centerIn: parent
                                    text: modelData
                                    font.pixelSize: 12
                                    opacity: 0.85
                                }
                            }
                        }
                        Repeater {
                            model: 42
                            delegate: Item {
                                id: dayCell
                                required property int index
                                readonly property date day: new Date(calTitle.viewDate.getFullYear(), calTitle.viewDate.getMonth(), index - calendar.firstWeekday + 1)
                                readonly property bool inMonth: day.getMonth() === calTitle.viewDate.getMonth()
                                readonly property bool isToday: day.toDateString() === calendar.today.toDateString()
                                width: 34
                                height: 36
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 28
                                    height: 28
                                    radius: 8
                                    visible: dayCell.isToday
                                    color: root.accent
                                }
                                NkText {
                                    anchors.centerIn: parent
                                    text: dayCell.day.getDate()
                                    font.pixelSize: 13
                                    opacity: dayCell.inMonth ? 1 : 0.35
                                    color: dayCell.isToday ? Appearance.colors.colOnPrimary : root.textColor
                                }
                            }
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onWheel: event => calTitle.monthOffset += (event.angleDelta.y < 0 ? 1 : -1)
                    }
                }

                Rectangle { // Todo
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 12
                    color: root.cardColor
                    clip: true
                    ColumnLayout {
                        anchors {
                            fill: parent
                            margins: 8
                        }
                        spacing: 4
                        NkText {
                            Layout.alignment: Qt.AlignHCenter
                            text: "Todo"
                            font.pixelSize: 16
                        }
                        ListView {
                            id: todoList
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: 4
                            model: Todo.list.map((item, i) => ({ content: item.content, done: item.done, index: i })).filter(item => !item.done)
                            delegate: RowLayout {
                                id: todoRow
                                required property var modelData
                                width: ListView.view.width
                                spacing: 6
                                NkText {
                                    Layout.alignment: Qt.AlignTop
                                    text: "–"
                                    font.pixelSize: 12
                                }
                                NkText {
                                    Layout.fillWidth: true
                                    wrapMode: Text.Wrap
                                    text: todoRow.modelData.content
                                    font.pixelSize: 12
                                }
                                MaterialSymbol { // Mark done
                                    Layout.alignment: Qt.AlignTop
                                    text: "check"
                                    iconSize: 16
                                    color: root.textColor
                                    opacity: doneMouse.containsMouse ? 1 : 0.45
                                    MouseArea {
                                        id: doneMouse
                                        anchors.fill: parent
                                        anchors.margins: -3
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Todo.markDone(todoRow.modelData.index)
                                    }
                                }
                            }
                            NkText {
                                anchors.centerIn: parent
                                visible: todoList.count === 0
                                text: "Nothing to do"
                                font.pixelSize: 12
                                opacity: 0.6
                            }
                        }
                        Rectangle { // Add a task
                            Layout.fillWidth: true
                            implicitHeight: 30
                            radius: 8
                            color: ColorUtils.transparentize(root.textColor, 0.92)
                            TextField {
                                id: todoField
                                anchors.fill: parent
                                leftPadding: 10
                                placeholderText: "Add a task"
                                placeholderTextColor: ColorUtils.transparentize(root.textColor, 0.45)
                                color: root.textColor
                                font.family: root.nkFont
                                font.pixelSize: 12
                                background: null
                                onAccepted: {
                                    if (text.trim().length > 0) Todo.addTask(text.trim());
                                    text = "";
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ===== Wi-Fi / Bluetooth lists (ii's own dialogs, shown over the sidebar) =====
    ToggleDialog {
        shownPropertyString: "showWifiDialog"
        dialog: WifiDialog {}
        onShownChanged: {
            if (!shown) return;
            Network.enableWifi();
            Network.rescanWifi();
        }
    }

    ToggleDialog {
        shownPropertyString: "showEthernetDialog"
        dialog: EthernetDialog {}
    }

    // Wired connection info, the same details the big settings window shows on its Status tab
    component EthernetDialog: WindowDialog {
        id: ethDialog
        backgroundHeight: 440
        property var rows: []

        Process {
            running: true
            command: ["bash", "-c", `
                dev=$(nmcli -t -f DEVICE,TYPE,STATE dev | awk -F: '$2=="ethernet" && $3=="connected"{print $1; exit}')
                [ -z "$dev" ] && { echo "Status|Not connected"; exit; }
                nmcli -t -e no -f GENERAL.CONNECTION,CAPABILITIES.SPEED,GENERAL.HWADDR,IP4.ADDRESS,IP4.GATEWAY,IP4.DNS dev show "$dev" | while IFS=: read -r k v; do
                    case "$k" in
                        GENERAL.CONNECTION) echo "Connection|$v" ;;
                        CAPABILITIES.SPEED) echo "Speed|$v" ;;
                        GENERAL.HWADDR) echo "MAC address|$v" ;;
                        IP4.ADDRESS*) echo "IPv4 address|\${v%/*}" ;;
                        IP4.GATEWAY) echo "Gateway|$v" ;;
                        IP4.DNS*) echo "DNS|$v" ;;
                    esac
                done
                echo "Device|$dev"`]
            stdout: StdioCollector {
                id: ethOut
                onStreamFinished: ethDialog.rows = ethOut.text.trim().split("\n").filter(l => l.includes("|")).map(l => l.split("|"))
            }
        }

        WindowDialogTitle {
            text: "Ethernet"
        }
        WindowDialogSeparator {}
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 6
            Repeater {
                model: ethDialog.rows
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 10
                    StyledText {
                        text: modelData[0]
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                        Layout.preferredWidth: 110
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: modelData[1]
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer1
                    }
                }
            }
            Item {
                Layout.fillHeight: true
            }
        }
        WindowDialogSeparator {}
        WindowDialogButtonRow {
            DialogButton {
                buttonText: "Details"
                onClicked: {
                    Quickshell.execDetached(["bash", "-c", Config.options.apps.networkEthernet]);
                    GlobalStates.sidebarRightOpen = false;
                }
            }
            DialogButton {
                buttonText: "Wi-Fi"
                onClicked: {
                    root.showEthernetDialog = false;
                    root.showWifiDialog = true;
                }
            }
            Item {
                Layout.fillWidth: true
            }
            DialogButton {
                buttonText: "Done"
                onClicked: ethDialog.dismiss()
            }
        }
    }

    ToggleDialog {
        shownPropertyString: "showBluetoothDialog"
        dialog: BluetoothDialog {}
        onShownChanged: {
            if (!Bluetooth.defaultAdapter) return;
            if (!shown) {
                Bluetooth.defaultAdapter.discovering = false;
            } else {
                Bluetooth.defaultAdapter.enabled = true;
                Bluetooth.defaultAdapter.discovering = true;
            }
        }
    }

    component ToggleDialog: Loader {
        id: toggleDialogLoader
        required property string shownPropertyString
        property alias dialog: toggleDialogLoader.sourceComponent
        readonly property bool shown: root[shownPropertyString]
        anchors.fill: parent
        z: 100

        onShownChanged: if (shown) toggleDialogLoader.active = true;
        active: shown
        onActiveChanged: {
            if (active) {
                item.show = true;
                item.forceActiveFocus();
            }
        }
        Connections {
            target: toggleDialogLoader.item
            function onDismiss() {
                toggleDialogLoader.item.show = false;
                root[toggleDialogLoader.shownPropertyString] = false;
            }
            function onVisibleChanged() {
                if (!toggleDialogLoader.item.visible && !root[toggleDialogLoader.shownPropertyString]) toggleDialogLoader.active = false;
            }
        }
    }
}
