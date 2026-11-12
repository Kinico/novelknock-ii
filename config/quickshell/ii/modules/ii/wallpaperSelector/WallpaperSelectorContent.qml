import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io

MouseArea {
    id: root
    property int columns: 4
    property real previewCellAspectRatio: 4 / 3
    property bool useDarkMode: Appearance.m3colors.darkmode

    // ===== NovelKnock: Wallpaper Engine library + Steam Workshop in this picker =====
    component HeaderChip: RippleButton {
        id: chip
        property string chipLabel
        property string chipIcon
        implicitHeight: 32
        implicitWidth: chipRow.implicitWidth + 22
        buttonRadius: 16
        colBackgroundToggled: Appearance.colors.colSecondaryContainer
        colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
        colRippleToggled: Appearance.colors.colSecondaryContainerActive
        contentItem: Item {
            RowLayout {
                id: chipRow
                anchors.centerIn: parent
                spacing: 4
                MaterialSymbol {
                    visible: chip.chipIcon.length > 0
                    text: chip.chipIcon
                    iconSize: Appearance.font.pixelSize.normal
                    color: chip.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                }
                StyledText {
                    text: chip.chipLabel
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: chip.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                }
            }
        }
    }

    readonly property string weScript: FileUtils.trimFileProtocol(`${Directories.config}/hypr/custom/scripts/wallpaper-apply.sh`)
    readonly property string wsScript: FileUtils.trimFileProtocol(`${Directories.config}/hypr/custom/scripts/workshop.mjs`)
    readonly property string weStateDir: FileUtils.trimFileProtocol(`${Directories.config}/linux-wallpaperengine`)
    property bool weMode: true          // Super+Z opens on your Wallpaper Engine library
    property string weTab: "library"    // "library" or "workshop"
    property var weItems: []
    property string weFilter: ""
    property string weCurrent: ""
    property bool weLoading: false

    // filters, remembered between openings
    property var prefs: ({ libType: "all", libRating: "all", libSort: "newest", wsSort: "trend", wsType: "all", wsRating: "all" })
    function setPref(key, value) {
        const p = Object.assign({}, root.prefs);
        p[key] = value;
        root.prefs = p;
        prefsFile.setText(JSON.stringify(p));
        if (key.startsWith("ws")) root.wsQuery(1);
    }
    function cycle(list, current) {
        const i = list.indexOf(current);
        return list[(i + 1) % list.length];
    }
    readonly property var typeNames: ({ all: "All types", scene: "Scene", video: "Video", web: "Web", Scene: "Scene", Video: "Video", Web: "Web" })
    readonly property var ratingNames: ({ all: "All ratings", Everyone: "Everyone", Questionable: "Questionable", Mature: "Mature" })
    readonly property var libSortNames: ({ newest: "Newest", title: "A to Z" })
    readonly property var wsSortNames: ({ trend: "Trending", votes: "Most popular", subscriptions: "Most subscribed", date: "Newest", updated: "Recently updated" })

    readonly property var weFiltered: {
        const q = root.weFilter.toLowerCase().trim();
        let list = root.weItems.filter(i => (root.prefs.libType === "all" || i.type === root.prefs.libType)
            && (root.prefs.libRating === "all" || (i.rating ?? "Everyone") === root.prefs.libRating)
            && (q.length === 0 || i.title.toLowerCase().includes(q) || i.id.includes(q)));
        if (root.prefs.libSort === "title") list = list.slice().sort((a, b) => a.title.localeCompare(b.title));
        return list;
    }
    function setWeMode(on) {
        root.weMode = on;
        if (!on) Wallpapers.searchQuery = filterField.text;
        if (on && root.weItems.length === 0) root.weRefresh();
    }
    function weRefresh() {
        root.weLoading = true;
        weListProc.running = false;
        weListProc.running = true;
    }
    function activeGrid() {
        if (!root.weMode) return grid;
        return root.weTab === "workshop" ? wsGrid : weGrid;
    }
    function applyWe(dir) {
        if (!dir) return;
        Quickshell.execDetached(["bash", root.weScript, "apply", dir]);
        filterField.text = "";
        GlobalStates.wallpaperSelectorOpen = false;
    }
    Process {
        id: weListProc
        command: ["bash", root.weScript, "list"]
        stdout: StdioCollector {
            id: weListCollector
            onStreamFinished: {
                try {
                    root.weItems = JSON.parse(weListCollector.text);
                } catch (e) {
                    root.weItems = [];
                }
                root.weLoading = false;
                if (!root.weSel) {
                    const playing = Object.values(root.weScreens);
                    const found = root.weItems.find(i => playing.includes(i.id));
                    if (found) root.weSelect(found);
                }
            }
        }
    }
    FileView {
        id: prefsFile
        path: `${root.weStateDir}/picker.json`
        onLoaded: {
            try {
                root.prefs = Object.assign({}, root.prefs, JSON.parse(prefsFile.text()));
            } catch (e) {}
        }
    }
    FileView { // which Wallpaper Engine wallpaper is playing (written by the watchdog)
        id: weCurrentFile
        path: `${root.weStateDir}/current-wallpaper.json`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const info = JSON.parse(weCurrentFile.text());
                root.weCurrent = info.key ?? "";
                root.weScreens = info.screens ?? ({});
            } catch (e) {
                root.weCurrent = "";
                root.weScreens = ({});
            }
        }
    }
    Component.onCompleted: root.weRefresh()

    // ----- details panel: selection, info, per-display apply, per-wallpaper settings -----
    property var weSel: null          // selected library wallpaper
    property var wsSel: null          // selected Workshop wallpaper
    property var weScreens: ({})      // display name -> wallpaper id playing there
    property var weSettings: ({})     // id -> { scaling, volume, audio, mouse, parallax, particles }
    property var weInfo: ({})         // size / resolution of the selected wallpaper
    property bool weDisplayMenu: false
    property bool weDeleteArmed: false
    property string weMessage: ""
    readonly property var weDefaults: ({ scaling: "fill", volume: 0, audio: true, mouse: true, parallax: true, particles: true })

    function weSelect(item) {
        root.weSel = item;
        root.weDisplayMenu = false;
        root.weDeleteArmed = false;
        root.weMessage = "";
        root.weInfo = ({});
        if (item) {
            weInfoProc.running = false;
            weInfoProc.command = ["bash", root.weScript, "info", item.dir];
            weInfoProc.running = true;
        }
    }
    function weShowingOn(id) {
        return Object.keys(root.weScreens).filter(s => root.weScreens[s] === id);
    }
    function weApplyTo(dir, screen) {
        if (!dir) return;
        Quickshell.execDetached(["bash", root.weScript, "apply", dir].concat(screen ? [screen] : []));
        filterField.text = "";
        GlobalStates.wallpaperSelectorOpen = false;
    }
    function weSetting(id, key) {
        const s = root.weSettings[id] ?? {};
        return s[key] !== undefined ? s[key] : root.g(key);   // unset uses the Settings page default
    }
    function weSetSetting(id, key, value) {
        const all = Object.assign({}, root.weSettings);
        const s = Object.assign({}, all[id] ?? {});
        if (key === null) {
            delete all[id];               // reset to defaults
        } else {
            s[key] = value;
            all[id] = s;
        }
        root.weSettings = all;
        settingsFile.setText(JSON.stringify(all, null, 2));
        if (root.weShowingOn(id).length > 0) reapplyTimer.restart();   // playing now: apply the change
    }
    function weDelete(item) {
        if (!item) return;
        if (!root.weDeleteArmed) {
            root.weDeleteArmed = true;
            disarmTimer.restart();
            return;
        }
        root.weDeleteArmed = false;
        root.weMessage = "Removing...";
        weDeleteProc.command = ["node", root.wsScript, "unsubscribe", item.id];
        weDeleteProc.running = true;
    }
    function formatSize(bytes) {
        if (!bytes) return "";
        if (bytes >= 1073741824) return `${(bytes / 1073741824).toFixed(2)} GB`;
        if (bytes >= 1048576) return `${(bytes / 1048576).toFixed(1)} MB`;
        return `${Math.round(bytes / 1024)} KB`;
    }

    // ----- global settings (Settings tab) and the wallpaper's own options -----
    readonly property var weGlobalDefaults: ({ fps: 30, pauseFullscreen: false, scaling: "fill", volume: 100, mute: true, noautomute: false, audio: true, mouse: true, parallax: true, particles: true, autoRestart: true, translate: true })
    property var weGlobal: weGlobalDefaults
    property var weProps: []
    property bool wePropsLoading: false
    property bool weColorsOn: true
    property string wsStatus: ""
    function g(key) {
        return root.weGlobal[key] !== undefined ? root.weGlobal[key] : root.weGlobalDefaults[key];
    }
    function setGlobal(key, value) {
        const all = Object.assign({}, root.weGlobal);
        if (key === null) {
            Object.keys(all).forEach(k => delete all[k]);
            Object.assign(all, root.weGlobalDefaults);
        } else {
            all[key] = value;
        }
        root.weGlobal = all;
        globalFile.setText(JSON.stringify(all, null, 2));
        if (key === "autoRestart" || key === null)
            Quickshell.execDetached(["bash", root.weScript, "autorestart", root.g("autoRestart") ? "on" : "off"]);
        if (key === "translate") root.loadProps(root.weSel);
        else if (key !== "autoRestart") reapplyTimer.restart();
    }
    function setColorsOn(on) {
        root.weColorsOn = on;
        Quickshell.execDetached(["bash", FileUtils.trimFileProtocol(`${Directories.config}/hypr/custom/scripts/wallpaper-colors.sh`), on ? "on" : "off"]);
    }
    function weSetProp(id, name, value) {
        const all = Object.assign({}, root.weSettings);
        const s = Object.assign({}, all[id] ?? {});
        const p = Object.assign({}, s.props ?? {});
        p[name] = value;
        s.props = p;
        all[id] = s;
        root.weSettings = all;
        settingsFile.setText(JSON.stringify(all, null, 2));
        if (root.weShowingOn(id).length > 0) reapplyTimer.restart();
    }
    function weProp(id, prop) {
        const v = ((root.weSettings[id] ?? {}).props ?? {})[prop.name];
        return v !== undefined ? v : prop.value;
    }
    function loadProps(item) {
        root.weProps = [];
        if (!item) return;
        root.wePropsLoading = true;
        wePropsProc.running = false;
        wePropsProc.command = ["bash", root.weScript, "props", item.dir];
        wePropsProc.running = true;
    }
    onWeSelChanged: root.loadProps(root.weSel)
    onWeTabChanged: {
        if (root.weTab === "settings") {
            wsStatusProc.running = false;
            root.wsStatus = "Checking Steam...";
            wsStatusProc.running = true;
        }
    }
    Process {
        id: wePropsProc
        stdout: StdioCollector {
            id: wePropsCollector
            onStreamFinished: {
                try {
                    root.weProps = JSON.parse(wePropsCollector.text);
                } catch (e) {
                    root.weProps = [];
                }
                root.wePropsLoading = false;
            }
        }
    }
    Process {
        id: wsStatusProc
        command: ["node", root.wsScript, "status"]
        stdout: StdioCollector {
            id: wsStatusCollector
            onStreamFinished: {
                try {
                    const lines = wsStatusCollector.text.trim().split("\n");
                    const r = JSON.parse(lines[lines.length - 1]);
                    root.wsStatus = r.ok ? "Connected to Steam" : (r.message ?? "Not connected");
                } catch (e) {
                    root.wsStatus = "Node.js is missing. Run workshop-setup.sh once.";
                }
            }
        }
    }
    FileView {
        id: globalFile
        path: `${root.weStateDir}/global-settings.json`
        onLoaded: {
            try {
                root.weGlobal = Object.assign({}, root.weGlobalDefaults, JSON.parse(globalFile.text()));
            } catch (e) {}
        }
    }
    FileView {
        id: colorsStateFile
        path: `${root.weStateDir}/colors.json`
        onLoaded: {
            try {
                root.weColorsOn = JSON.parse(colorsStateFile.text()).enabled !== false;
            } catch (e) {}
        }
    }

    component SettingsCard: Rectangle {
        id: settingsCard
        property string cardIcon
        property string cardTitle
        property string cardSubtitle
        default property alias content: settingsCardRows.data
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        implicitHeight: settingsCardColumn.implicitHeight + 8
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1
        ColumnLayout {
            id: settingsCardColumn
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
            }
            spacing: 0
            RowLayout {
                Layout.fillWidth: true
                Layout.margins: 14
                spacing: 12
                Rectangle {
                    implicitWidth: 36
                    implicitHeight: 36
                    radius: 10
                    color: Appearance.colors.colLayer2
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: settingsCard.cardIcon
                        iconSize: 20
                        color: Appearance.colors.colOnLayer2
                    }
                }
                ColumnLayout {
                    spacing: 0
                    StyledText {
                        text: settingsCard.cardTitle
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        text: settingsCard.cardSubtitle
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }
            }
            ColumnLayout {
                id: settingsCardRows
                Layout.fillWidth: true
                Layout.leftMargin: 14
                Layout.rightMargin: 14
                Layout.bottomMargin: 8
                spacing: 2
            }
        }
    }
    component SettingsRow: RowLayout {
        id: settingsRow
        property string rowText
        property string rowHint
        default property alias control: settingsRowControl.data
        Layout.fillWidth: true
        Layout.minimumHeight: 44
        spacing: 10
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            StyledText {
                Layout.fillWidth: true
                text: settingsRow.rowText
                color: Appearance.colors.colOnLayer1
                wrapMode: Text.Wrap
            }
            StyledText {
                Layout.fillWidth: true
                visible: settingsRow.rowHint.length > 0
                text: settingsRow.rowHint
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                wrapMode: Text.Wrap
            }
        }
        RowLayout {
            id: settingsRowControl
            spacing: 4
        }
    }
    Process {
        id: weInfoProc
        stdout: StdioCollector {
            id: weInfoCollector
            onStreamFinished: {
                try {
                    root.weInfo = JSON.parse(weInfoCollector.text);
                } catch (e) {
                    root.weInfo = ({});
                }
            }
        }
    }
    Process {
        id: weDeleteProc
        stdout: StdioCollector {
            id: weDeleteCollector
            onStreamFinished: {
                let r = {};
                try {
                    const lines = weDeleteCollector.text.trim().split("\n");
                    r = JSON.parse(lines[lines.length - 1]);
                } catch (e) {}
                if (r.removed) {
                    root.weMessage = "Removed. Steam deletes the files in a moment.";
                    root.weItems = root.weItems.filter(i => i.id !== r.id);
                    root.weSelect(null);
                    refreshLaterTimer.restart();
                } else {
                    root.weMessage = r.message ?? "Could not remove it. Is Steam open and workshop-setup.sh done?";
                }
            }
        }
    }
    Timer {
        id: reapplyTimer
        interval: 900
        onTriggered: Quickshell.execDetached(["bash", root.weScript, "reapply"])
    }
    Timer {
        id: disarmTimer
        interval: 3000
        onTriggered: root.weDeleteArmed = false
    }
    Timer {
        id: refreshLaterTimer
        interval: 3000
        onTriggered: root.weRefresh()
    }
    FileView {
        id: settingsFile
        path: `${root.weStateDir}/wallpaper-settings.json`
        onLoaded: {
            try {
                root.weSettings = JSON.parse(settingsFile.text());
            } catch (e) {
                root.weSettings = ({});
            }
        }
    }

    // ----- Steam Workshop (workshop.mjs, through your running Steam client) -----
    property var wsItems: []
    property int wsPage: 1
    property bool wsHasNext: false
    property int wsTotal: 0
    property bool wsLoading: false
    property bool wsQueued: false
    property string wsError: ""
    property var wsDownloads: ({})   // id -> 0..1 while downloading, "error" when it failed
    property var wsInstalled: ({})   // id -> folder, for wallpapers downloaded while the picker is open
    function setWeTab(tab) {
        root.weTab = tab;
        if (tab === "workshop" && root.wsItems.length === 0 && !root.wsLoading) root.wsQuery(1);
    }
    function wsQuery(page) {
        root.wsPage = Math.max(1, page);
        if (wsQueryProc.running) {
            root.wsQueued = true;
            return;
        }
        root.wsLoading = true;
        root.wsError = "";
        wsQueryProc.command = ["node", root.wsScript, "query", root.prefs.wsSort, `${root.wsPage}`, root.prefs.wsType, root.prefs.wsRating].concat(root.weFilter.trim().length > 0 ? [root.weFilter.trim()] : []);
        wsQueryProc.running = true;
    }
    Process {
        id: wsQueryProc
        stdout: StdioCollector {
            id: wsQueryCollector
            onStreamFinished: {
                root.wsLoading = false;
                try {
                    const lines = wsQueryCollector.text.trim().split("\n");
                    const r = JSON.parse(lines[lines.length - 1]);
                    if (r.error) {
                        root.wsError = r.message ?? "Workshop is not available right now.";
                        root.wsItems = [];
                    } else {
                        root.wsItems = r.items;
                        root.wsHasNext = r.hasNext;
                        root.wsTotal = r.total;
                        wsGrid.positionViewAtBeginning();
                    }
                } catch (e) {
                    root.wsError = "Could not reach the Workshop. Is Node.js installed? Run workshop-setup.sh.";
                    root.wsItems = [];
                }
                if (root.wsQueued) {
                    root.wsQueued = false;
                    root.wsQuery(root.wsPage);
                }
            }
        }
    }
    Timer { // apply the search box to the library shortly after you stop typing
        id: weFilterTimer
        interval: 220
        onTriggered: {
            root.weFilter = filterField.text;
            if (root.weTab === "workshop") wsSearchTimer.restart();
        }
    }
    Timer { // search the Workshop shortly after you stop typing
        id: wsSearchTimer
        interval: 400
        onTriggered: root.wsQuery(1)
    }
    function wsFolder(item) {
        return root.wsInstalled[item.id] ?? item.installed ?? "";
    }
    function wsActivate(item) {
        if (!item) return;
        const folder = root.wsFolder(item);
        if (folder.length > 0) {
            root.applyWe(folder);
        } else if (root.wsDownloads[item.id] === undefined || root.wsDownloads[item.id] === "error") {
            root.wsSubscribe(item.id);
        }
    }
    function wsSubscribe(id) {
        const d = Object.assign({}, root.wsDownloads);
        d[id] = 0;
        root.wsDownloads = d;
        wsSubscribeComp.createObject(root, { itemId: id });
    }
    function wsOnLine(line) {
        let r;
        try {
            r = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (!r.id) return;
        const d = Object.assign({}, root.wsDownloads);
        if (r.done) {
            delete d[r.id];
            const inst = Object.assign({}, root.wsInstalled);
            inst[r.id] = r.folder;
            root.wsInstalled = inst;
            root.weRefresh();
        } else if (r.error) {
            d[r.id] = "error";
        } else if (r.progress !== undefined) {
            d[r.id] = r.progress;
        }
        root.wsDownloads = d;
    }
    Component {
        id: wsSubscribeComp
        Process {
            id: subProc
            property string itemId
            command: ["node", root.wsScript, "subscribe", itemId]
            running: true
            stdout: SplitParser {
                onRead: line => root.wsOnLine(line)
            }
            onExited: (exitCode, exitStatus) => {
                if (root.wsDownloads[subProc.itemId] !== undefined && typeof root.wsDownloads[subProc.itemId] === "number") {
                    // finished without a "done" line, Steam will keep downloading in the background
                    const d = Object.assign({}, root.wsDownloads);
                    delete d[subProc.itemId];
                    root.wsDownloads = d;
                    root.weRefresh();
                }
                subProc.destroy();
            }
        }
    }

    function updateThumbnails() {
        const totalImageMargin = (Appearance.sizes.wallpaperSelectorItemMargins + Appearance.sizes.wallpaperSelectorItemPadding) * 2;
        const thumbnailSizeName = Images.thumbnailSizeNameForDimensions(grid.cellWidth - totalImageMargin, grid.cellHeight - totalImageMargin);
        Wallpapers.generateThumbnail(thumbnailSizeName);
    }

    Connections {
        target: Wallpapers
        function onDirectoryChanged() {
            root.updateThumbnails();
        }
    }

    function handleFilePasting(event) {
        const currentClipboardEntry = Cliphist.entries[0];
        if (/^\d+\tfile:\/\/\S+/.test(currentClipboardEntry)) {
            const url = StringUtils.cleanCliphistEntry(currentClipboardEntry);
            Wallpapers.setDirectory(FileUtils.trimFileProtocol(decodeURIComponent(url)));
            event.accepted = true;
        } else {
            event.accepted = false; // No image, let text pasting proceed
        }
    }

    function selectWallpaperPath(filePath) {
        if (filePath && filePath.length > 0) {
            Wallpapers.select(filePath, root.useDarkMode);
            filterField.text = "";
        }
    }

    acceptedButtons: Qt.BackButton | Qt.ForwardButton
    onPressed: event => {
        if (event.button === Qt.BackButton) {
            Wallpapers.navigateBack();
        } else if (event.button === Qt.ForwardButton) {
            Wallpapers.navigateForward();
        }
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            GlobalStates.wallpaperSelectorOpen = false;
            event.accepted = true;
        } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V) { // Intercept Ctrl+V to handle "paste to go to" in pickers
            root.handleFilePasting(event);
        } else if (event.modifiers & Qt.AltModifier && event.key === Qt.Key_Up) {
            Wallpapers.navigateUp();
            event.accepted = true;
        } else if (event.modifiers & Qt.AltModifier && event.key === Qt.Key_Left) {
            Wallpapers.navigateBack();
            event.accepted = true;
        } else if (event.modifiers & Qt.AltModifier && event.key === Qt.Key_Right) {
            Wallpapers.navigateForward();
            event.accepted = true;
        } else if (event.key === Qt.Key_Left) {
            root.activeGrid().moveSelection(-1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Right) {
            root.activeGrid().moveSelection(1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Up) {
            root.activeGrid().moveSelection(-grid.columns);
            event.accepted = true;
        } else if (event.key === Qt.Key_Down) {
            root.activeGrid().moveSelection(grid.columns);
            event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.activeGrid().activateCurrent();
            event.accepted = true;
        } else if (event.key === Qt.Key_Backspace) {
            if (filterField.text.length > 0) {
                filterField.text = filterField.text.substring(0, filterField.text.length - 1);
            }
            filterField.forceActiveFocus();
            event.accepted = true;
        } else if (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_L) {
            addressBar.focusBreadcrumb();
            event.accepted = true;
        } else if (event.key === Qt.Key_Slash) {
            filterField.forceActiveFocus();
            event.accepted = true;
        } else {
            if (event.text.length > 0) {
                filterField.text += event.text;
                filterField.cursorPosition = filterField.text.length;
                filterField.forceActiveFocus();
            }
            event.accepted = true;
        }
    }

    implicitHeight: mainLayout.implicitHeight
    implicitWidth: mainLayout.implicitWidth

    StyledRectangularShadow {
        target: wallpaperGridBackground
    }
    Rectangle {
        id: wallpaperGridBackground
        anchors {
            fill: parent
            margins: Appearance.sizes.elevationMargin
        }
        focus: true
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        color: Appearance.colors.colLayer0
        radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1

        property int calculatedRows: Math.ceil(grid.count / grid.columns)

        implicitWidth: gridColumnLayout.implicitWidth
        implicitHeight: gridColumnLayout.implicitHeight

        RowLayout {
            id: mainLayout
            anchors.fill: parent
            spacing: -4

            Rectangle {
                Layout.fillHeight: true
                Layout.margins: 4
                implicitWidth: quickDirColumnLayout.implicitWidth
                implicitHeight: quickDirColumnLayout.implicitHeight
                color: Appearance.colors.colLayer1
                radius: wallpaperGridBackground.radius - Layout.margins

                ColumnLayout {
                    id: quickDirColumnLayout
                    anchors.fill: parent
                    spacing: 0

                    StyledText {
                        Layout.margins: 12
                        font {
                            pixelSize: Appearance.font.pixelSize.normal
                            weight: Font.Medium
                        }
                        text: Translation.tr("Pick a wallpaper")
                    }
                    ListView {
                        // Quick dirs
                        Layout.fillHeight: true
                        Layout.margins: 4
                        implicitWidth: 172
                        clip: true
                        model: [
                            {
                                icon: "home",
                                name: "Home",
                                path: Directories.home
                            },
                            {
                                icon: "docs",
                                name: "Documents",
                                path: Directories.documents
                            },
                            {
                                icon: "download",
                                name: "Downloads",
                                path: Directories.downloads
                            },
                            {
                                icon: "image",
                                name: "Pictures",
                                path: Directories.pictures
                            },
                            {
                                icon: "movie",
                                name: "Videos",
                                path: Directories.videos
                            },
                            {
                                icon: "",
                                name: "---",
                                path: "INTENTIONALLY_INVALID_DIR"
                            },
                            {
                                icon: "wallpaper",
                                name: "Wallpapers",
                                path: `${Directories.pictures}/Wallpapers`
                            },
                            {
                                icon: "animation",
                                name: "Wallpaper Engine",
                                path: "WALLPAPER_ENGINE"
                            },
                            ...(Config.options.policies.weeb === 1 ? [
                                    {
                                        icon: "favorite",
                                        name: "Homework",
                                        path: `${Directories.pictures}/homework`
                                    }
                                ] : []),]
                        delegate: RippleButton {
                            id: quickDirButton
                            required property var modelData
                            anchors {
                                left: parent.left
                                right: parent.right
                            }
                            onClicked: {
                                if (quickDirButton.modelData.path === "WALLPAPER_ENGINE") {
                                    root.setWeMode(true);
                                } else {
                                    root.setWeMode(false);
                                    Wallpapers.setDirectory(quickDirButton.modelData.path);
                                }
                            }
                            enabled: modelData.icon.length > 0
                            toggled: modelData.path === "WALLPAPER_ENGINE" ? root.weMode : (!root.weMode && Wallpapers.directory === Qt.resolvedUrl(modelData.path))
                            colBackgroundToggled: Appearance.colors.colSecondaryContainer
                            colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                            colRippleToggled: Appearance.colors.colSecondaryContainerActive
                            buttonRadius: height / 2
                            implicitHeight: 38

                            contentItem: RowLayout {
                                MaterialSymbol {
                                    color: quickDirButton.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                                    iconSize: Appearance.font.pixelSize.larger
                                    text: quickDirButton.modelData.icon
                                    fill: quickDirButton.toggled ? 1 : 0
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignLeft
                                    color: quickDirButton.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                                    text: quickDirButton.modelData.name
                                }
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                id: gridColumnLayout
                Layout.fillWidth: true
                Layout.fillHeight: true

                Rectangle { // Wallpaper Engine header: Library / Workshop tabs, filters
                    visible: root.weMode
                    Layout.margins: 4
                    Layout.fillWidth: true
                    implicitHeight: addressBar.implicitHeight
                    radius: wallpaperGridBackground.radius - Layout.margins
                    color: Appearance.colors.colLayer1

                    RowLayout {
                        anchors {
                            fill: parent
                            leftMargin: 8
                            rightMargin: 8
                        }
                        spacing: 4

                        HeaderChip {
                            chipIcon: "photo_library"
                            chipLabel: root.weLoading ? "Library" : `Library ${root.weItems.length}`
                            toggled: root.weTab === "library"
                            onClicked: root.setWeTab("library")
                        }
                        HeaderChip {
                            chipIcon: "storefront"
                            chipLabel: "Workshop"
                            toggled: root.weTab === "workshop"
                            onClicked: root.setWeTab("workshop")
                        }
                        HeaderChip {
                            chipIcon: "settings"
                            chipLabel: "Settings"
                            toggled: root.weTab === "settings"
                            onClicked: root.setWeTab("settings")
                        }
                        Item {
                            Layout.fillWidth: true
                        }

                        // Library filters (click to switch)
                        HeaderChip {
                            visible: root.weTab === "library"
                            chipIcon: "category"
                            chipLabel: root.typeNames[root.prefs.libType]
                            toggled: root.prefs.libType !== "all"
                            onClicked: root.setPref("libType", root.cycle(["all", "scene", "video", "web"], root.prefs.libType))
                        }
                        HeaderChip {
                            visible: root.weTab === "library"
                            chipIcon: "shield"
                            chipLabel: root.ratingNames[root.prefs.libRating]
                            toggled: root.prefs.libRating !== "all"
                            onClicked: root.setPref("libRating", root.cycle(["all", "Everyone", "Questionable", "Mature"], root.prefs.libRating))
                        }
                        HeaderChip {
                            visible: root.weTab === "library"
                            chipIcon: "sort"
                            chipLabel: root.libSortNames[root.prefs.libSort]
                            onClicked: root.setPref("libSort", root.cycle(["newest", "title"], root.prefs.libSort))
                        }

                        // Workshop filters
                        HeaderChip {
                            visible: root.weTab === "workshop"
                            chipIcon: "trending_up"
                            chipLabel: root.weFilter.trim().length > 0 ? "Best match" : root.wsSortNames[root.prefs.wsSort]
                            onClicked: root.setPref("wsSort", root.cycle(["trend", "votes", "subscriptions", "date", "updated"], root.prefs.wsSort))
                        }
                        HeaderChip {
                            visible: root.weTab === "workshop"
                            chipIcon: "category"
                            chipLabel: root.typeNames[root.prefs.wsType]
                            toggled: root.prefs.wsType !== "all"
                            onClicked: root.setPref("wsType", root.cycle(["all", "Scene", "Video", "Web"], root.prefs.wsType))
                        }
                        HeaderChip {
                            visible: root.weTab === "workshop"
                            chipIcon: "shield"
                            chipLabel: root.ratingNames[root.prefs.wsRating]
                            toggled: root.prefs.wsRating !== "all"
                            onClicked: root.setPref("wsRating", root.cycle(["all", "Everyone", "Questionable", "Mature"], root.prefs.wsRating))
                        }
                        HeaderChip {
                            visible: root.weTab === "workshop"
                            chipIcon: "chevron_left"
                            chipLabel: ""
                            implicitWidth: 32
                            enabled: root.wsPage > 1 && !root.wsLoading
                            opacity: enabled ? 1 : 0.4
                            onClicked: root.wsQuery(root.wsPage - 1)
                        }
                        StyledText {
                            visible: root.weTab === "workshop"
                            text: `${root.wsPage}`
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer1
                        }
                        HeaderChip {
                            visible: root.weTab === "workshop"
                            chipIcon: "chevron_right"
                            chipLabel: ""
                            implicitWidth: 32
                            enabled: root.wsHasNext && !root.wsLoading
                            opacity: enabled ? 1 : 0.4
                            onClicked: root.wsQuery(root.wsPage + 1)
                        }

                        HeaderChip {
                            visible: root.weTab !== "settings"
                            chipIcon: "refresh"
                            chipLabel: ""
                            implicitWidth: 32
                            onClicked: root.weTab === "workshop" ? root.wsQuery(root.wsPage) : root.weRefresh()
                            StyledToolTip {
                                text: root.weTab === "workshop" ? "Reload this page" : "Reload your library (after new downloads)"
                            }
                        }
                    }
                }

                AddressBar {
                    id: addressBar
                    visible: !root.weMode
                    Layout.margins: 4
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    directory: Wallpapers.effectiveDirectory
                    onNavigateToDirectory: path => {
                        Wallpapers.setDirectory(path.length == 0 ? "/" : path);
                    }
                    radius: wallpaperGridBackground.radius - Layout.margins
                }

                Item {
                    id: gridDisplayRegion
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    StyledIndeterminateProgressBar {
                        id: indeterminateProgressBar
                        visible: Wallpapers.thumbnailGenerationRunning && value == 0
                        anchors {
                            bottom: parent.top
                            left: parent.left
                            right: parent.right
                            leftMargin: 4
                            rightMargin: 4
                        }
                    }

                    StyledProgressBar {
                        visible: Wallpapers.thumbnailGenerationRunning && value > 0
                        value: Wallpapers.thumbnailGenerationProgress
                        anchors.fill: indeterminateProgressBar
                    }

                    GridView {
                        id: grid
                        visible: !root.weMode && Wallpapers.folderModel.count > 0

                        readonly property int columns: root.columns
                        readonly property int rows: Math.max(1, Math.ceil(count / columns))
                        property int currentIndex: 0

                        anchors.fill: parent
                        cellWidth: width / root.columns
                        cellHeight: cellWidth / root.previewCellAspectRatio
                        interactive: true
                        clip: true
                        keyNavigationWraps: true
                        boundsBehavior: Flickable.StopAtBounds
                        bottomMargin: extraOptions.implicitHeight
                        ScrollBar.vertical: StyledScrollBar {}

                        Component.onCompleted: {
                            root.updateThumbnails();
                        }

                        function moveSelection(delta) {
                            currentIndex = Math.max(0, Math.min(grid.model.count - 1, currentIndex + delta));
                            positionViewAtIndex(currentIndex, GridView.Contain);
                        }

                        function activateCurrent() {
                            const filePath = grid.model.get(currentIndex, "filePath");
                            root.selectWallpaperPath(filePath);
                        }

                        model: Wallpapers.folderModel
                        onModelChanged: currentIndex = 0
                        delegate: WallpaperDirectoryItem {
                            required property var modelData
                            required property int index
                            fileModelData: modelData
                            width: grid.cellWidth
                            height: grid.cellHeight
                            colBackground: (index === grid?.currentIndex || containsMouse) ? Appearance.colors.colPrimary : (fileModelData.filePath === Config.options.background.wallpaperPath) ? Appearance.colors.colSecondaryContainer : ColorUtils.transparentize(Appearance.colors.colPrimaryContainer)
                            colText: (index === grid.currentIndex || containsMouse) ? Appearance.colors.colOnPrimary : (fileModelData.filePath === Config.options.background.wallpaperPath) ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer0

                            onEntered: {
                                grid.currentIndex = index;
                            }

                            onActivated: {
                                root.selectWallpaperPath(fileModelData.filePath);
                            }
                        }

                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: gridDisplayRegion.width
                                height: gridDisplayRegion.height
                                radius: wallpaperGridBackground.radius
                            }
                        }
                    }

                    GridView { // Wallpaper Engine wallpapers
                        id: weGrid
                        visible: root.weMode && root.weTab === "library"
                        property int currentIndex: 0
                        anchors.fill: parent
                        cellWidth: width / root.columns
                        cellHeight: cellWidth / root.previewCellAspectRatio
                        interactive: true
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        bottomMargin: extraOptions.implicitHeight
                        ScrollBar.vertical: StyledScrollBar {}
                        model: root.weFiltered
                        onModelChanged: currentIndex = 0

                        function moveSelection(delta) {
                            currentIndex = Math.max(0, Math.min(count - 1, currentIndex + delta));
                            positionViewAtIndex(currentIndex, GridView.Contain);
                        }
                        function activateCurrent() {
                            root.applyWe(root.weFiltered[currentIndex]?.dir);
                        }

                        delegate: MouseArea {
                            id: weItem
                            required property var modelData
                            required property int index
                            readonly property bool isCurrent: Object.values(root.weScreens).includes(modelData.id) || modelData.id === root.weCurrent
                            readonly property bool highlighted: root.weSel?.id === modelData.id || containsMouse
                            width: weGrid.cellWidth
                            height: weGrid.cellHeight
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: weGrid.currentIndex = index
                            onClicked: root.weSelect(modelData)
                            onDoubleClicked: root.weApplyTo(modelData.dir, "")

                            Rectangle {
                                anchors {
                                    fill: parent
                                    margins: Appearance.sizes.wallpaperSelectorItemMargins
                                }
                                radius: Appearance.rounding.normal
                                color: weItem.highlighted ? Appearance.colors.colPrimary : weItem.isCurrent ? Appearance.colors.colSecondaryContainer : ColorUtils.transparentize(Appearance.colors.colPrimaryContainer)
                                Behavior on color {
                                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                                }

                                ColumnLayout {
                                    anchors {
                                        fill: parent
                                        margins: Appearance.sizes.wallpaperSelectorItemPadding
                                    }
                                    spacing: 4

                                    Item {
                                        id: wePreviewBox
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        Image {
                                            anchors.fill: parent
                                            source: weItem.modelData.preview.length > 0 ? `file://${weItem.modelData.preview}` : ""
                                            sourceSize.width: weGrid.cellWidth
                                            sourceSize.height: weGrid.cellHeight
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                            cache: true
                                            layer.enabled: true
                                            layer.effect: OpacityMask {
                                                maskSource: Rectangle {
                                                    width: wePreviewBox.width
                                                    height: wePreviewBox.height
                                                    radius: Appearance.rounding.small
                                                }
                                            }
                                        }
                                        Rectangle { // type chip
                                            anchors {
                                                left: parent.left
                                                bottom: parent.bottom
                                                margins: 6
                                            }
                                            implicitWidth: weTypeText.implicitWidth + 12
                                            implicitHeight: 18
                                            radius: 6
                                            color: ColorUtils.transparentize("#000000", 0.45)
                                            StyledText {
                                                id: weTypeText
                                                anchors.centerIn: parent
                                                text: weItem.modelData.type.toUpperCase()
                                                font.pixelSize: 10
                                                color: "#ffffff"
                                            }
                                        }
                                        MaterialSymbol { // playing now
                                            visible: weItem.isCurrent
                                            anchors {
                                                right: parent.right
                                                top: parent.top
                                                margins: 6
                                            }
                                            text: "check_circle"
                                            fill: 1
                                            iconSize: 20
                                            color: Appearance.colors.colPrimary
                                        }
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        Layout.leftMargin: 10
                                        Layout.rightMargin: 10
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: weItem.highlighted ? Appearance.colors.colOnPrimary : weItem.isCurrent ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer0
                                        text: weItem.modelData.title
                                    }
                                }
                            }
                        }

                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: gridDisplayRegion.width
                                height: gridDisplayRegion.height
                                radius: wallpaperGridBackground.radius
                            }
                        }
                    }

                    GridView { // Steam Workshop
                        id: wsGrid
                        visible: root.weMode && root.weTab === "workshop"
                        property int currentIndex: 0
                        anchors.fill: parent
                        cellWidth: width / root.columns
                        cellHeight: cellWidth / root.previewCellAspectRatio
                        interactive: true
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        bottomMargin: extraOptions.implicitHeight
                        ScrollBar.vertical: StyledScrollBar {}
                        model: root.wsItems
                        onModelChanged: currentIndex = 0

                        function moveSelection(delta) {
                            currentIndex = Math.max(0, Math.min(count - 1, currentIndex + delta));
                            positionViewAtIndex(currentIndex, GridView.Contain);
                        }
                        function activateCurrent() {
                            root.wsActivate(root.wsItems[currentIndex]);
                        }

                        delegate: MouseArea {
                            id: wsItem
                            required property var modelData
                            required property int index
                            readonly property string folder: root.wsFolder(modelData)
                            readonly property var dl: root.wsDownloads[modelData.id]
                            readonly property bool downloading: typeof dl === "number"
                            readonly property bool isCurrent: modelData.id === root.weCurrent
                            readonly property bool highlighted: root.wsSel?.id === modelData.id || containsMouse
                            width: wsGrid.cellWidth
                            height: wsGrid.cellHeight
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: wsGrid.currentIndex = index
                            onClicked: root.wsSel = modelData
                            onDoubleClicked: root.wsActivate(modelData)

                            Rectangle {
                                anchors {
                                    fill: parent
                                    margins: Appearance.sizes.wallpaperSelectorItemMargins
                                }
                                radius: Appearance.rounding.normal
                                color: wsItem.highlighted ? Appearance.colors.colPrimary : wsItem.isCurrent ? Appearance.colors.colSecondaryContainer : ColorUtils.transparentize(Appearance.colors.colPrimaryContainer)
                                Behavior on color {
                                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                                }

                                ColumnLayout {
                                    anchors {
                                        fill: parent
                                        margins: Appearance.sizes.wallpaperSelectorItemPadding
                                    }
                                    spacing: 4

                                    Item {
                                        id: wsPreviewBox
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        Image {
                                            anchors.fill: parent
                                            source: wsItem.modelData.preview
                                            sourceSize.width: wsGrid.cellWidth
                                            sourceSize.height: wsGrid.cellHeight
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                            cache: true
                                            layer.enabled: true
                                            layer.effect: OpacityMask {
                                                maskSource: Rectangle {
                                                    width: wsPreviewBox.width
                                                    height: wsPreviewBox.height
                                                    radius: Appearance.rounding.small
                                                }
                                            }
                                        }
                                        Row { // type and rating chips
                                            anchors {
                                                left: parent.left
                                                bottom: parent.bottom
                                                margins: 6
                                            }
                                            spacing: 4
                                            Repeater {
                                                model: [wsItem.modelData.type, wsItem.modelData.rating].filter(t => t && t.length > 0 && t !== "Everyone")
                                                delegate: Rectangle {
                                                    required property string modelData
                                                    implicitWidth: wsChipText.implicitWidth + 12
                                                    implicitHeight: 18
                                                    radius: 6
                                                    color: modelData === "Mature" ? ColorUtils.transparentize("#b3261e", 0.2) : ColorUtils.transparentize("#000000", 0.45)
                                                    StyledText {
                                                        id: wsChipText
                                                        anchors.centerIn: parent
                                                        text: parent.modelData.toUpperCase()
                                                        font.pixelSize: 10
                                                        color: "#ffffff"
                                                    }
                                                }
                                            }
                                        }
                                        Rectangle { // Subscribe / Downloading / Apply
                                            anchors {
                                                right: parent.right
                                                bottom: parent.bottom
                                                margins: 6
                                            }
                                            implicitWidth: wsActionRow.implicitWidth + 14
                                            implicitHeight: 24
                                            radius: 12
                                            color: wsItem.folder.length > 0 ? Appearance.colors.colPrimary : ColorUtils.transparentize("#000000", 0.35)
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.wsActivate(wsItem.modelData)
                                            }
                                            RowLayout {
                                                id: wsActionRow
                                                anchors.centerIn: parent
                                                spacing: 3
                                                MaterialSymbol {
                                                    text: wsItem.folder.length > 0 ? (wsItem.isCurrent ? "check_circle" : "play_arrow") : wsItem.downloading ? "downloading" : wsItem.dl === "error" ? "error" : "add"
                                                    iconSize: 15
                                                    fill: 1
                                                    color: wsItem.folder.length > 0 ? Appearance.colors.colOnPrimary : "#ffffff"
                                                }
                                                StyledText {
                                                    text: wsItem.folder.length > 0 ? (wsItem.isCurrent ? "Playing" : "Apply") : wsItem.downloading ? `${Math.round(wsItem.dl * 100)}%` : wsItem.dl === "error" ? "Retry" : "Subscribe"
                                                    font.pixelSize: 11
                                                    color: wsItem.folder.length > 0 ? Appearance.colors.colOnPrimary : "#ffffff"
                                                }
                                            }
                                        }
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        Layout.leftMargin: 10
                                        Layout.rightMargin: 10
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: wsItem.highlighted ? Appearance.colors.colOnPrimary : wsItem.isCurrent ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer0
                                        text: wsItem.modelData.title
                                    }
                                }
                            }
                        }

                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: gridDisplayRegion.width
                                height: gridDisplayRegion.height
                                radius: wallpaperGridBackground.radius
                            }
                        }
                    }

                    ColumnLayout { // loading / Steam not open / nothing found
                        anchors.centerIn: parent
                        visible: root.weMode && ((root.weTab === "workshop" && (root.wsLoading || root.wsError.length > 0 || root.wsItems.length === 0))
                            || (root.weTab === "library" && (root.weLoading || root.weFiltered.length === 0)))
                        spacing: 8
                        MaterialSymbol {
                            Layout.alignment: Qt.AlignHCenter
                            text: (root.weTab === "workshop" ? root.wsLoading : root.weLoading) ? "hourglass_top" : root.wsError.length > 0 && root.weTab === "workshop" ? "cloud_off" : "search_off"
                            iconSize: 40
                            color: Appearance.colors.colSubtext
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.maximumWidth: 420
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
                            color: Appearance.colors.colSubtext
                            text: root.weTab === "workshop"
                                ? (root.wsLoading ? "Loading the Workshop..." : root.wsError.length > 0 ? root.wsError : "Nothing found")
                                : (root.weLoading ? "Loading your library..." : "No wallpapers match these filters")
                        }
                    }

                    Flickable { // Settings tab
                        id: weSettingsPage
                        visible: root.weMode && root.weTab === "settings"
                        anchors.fill: parent
                        contentHeight: weSettingsColumn.implicitHeight + extraOptions.implicitHeight + 24
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: StyledScrollBar {}

                        ColumnLayout {
                            id: weSettingsColumn
                            anchors {
                                left: parent.left
                                right: parent.right
                                top: parent.top
                                margins: 8
                            }
                            spacing: 10

                            RowLayout {
                                Layout.fillWidth: true
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    StyledText {
                                        text: "Settings"
                                        font.pixelSize: Appearance.font.pixelSize.huge
                                        font.weight: Font.DemiBold
                                        color: Appearance.colors.colOnLayer0
                                    }
                                    StyledText {
                                        text: "Defaults for every wallpaper. A wallpaper's own settings in its details panel win over these."
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: Appearance.colors.colSubtext
                                    }
                                }
                                HeaderChip {
                                    chipIcon: "restart_alt"
                                    chipLabel: "Reset to defaults"
                                    onClicked: root.setGlobal(null, null)
                                }
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: 2
                                columnSpacing: 10
                                rowSpacing: 10

                                SettingsCard {
                                    cardIcon: "settings"
                                    cardTitle: "General"
                                    cardSubtitle: "Behavior"
                                    SettingsRow {
                                        rowText: "Pause on fullscreen apps"
                                        rowHint: "Frees the GPU while you game or watch fullscreen"
                                        StyledSwitch {
                                            checked: root.g("pauseFullscreen")
                                            onClicked: {
                                                root.setGlobal("pauseFullscreen", checked);
                                                checked = Qt.binding(() => root.g("pauseFullscreen"));
                                            }
                                        }
                                    }
                                    SettingsRow {
                                        rowText: "Restart the wallpaper if it stops"
                                        rowHint: "Also brings it back when a monitor comes back"
                                        StyledSwitch {
                                            checked: root.g("autoRestart")
                                            onClicked: {
                                                root.setGlobal("autoRestart", checked);
                                                checked = Qt.binding(() => root.g("autoRestart"));
                                            }
                                        }
                                    }
                                    SettingsRow {
                                        rowText: "Translate wallpaper options to English"
                                        rowHint: "Uses Google Translate once per label, then works offline"
                                        StyledSwitch {
                                            checked: root.g("translate")
                                            onClicked: {
                                                root.setGlobal("translate", checked);
                                                checked = Qt.binding(() => root.g("translate"));
                                            }
                                        }
                                    }
                                    SettingsRow {
                                        rowText: "Match theme colors to the wallpaper"
                                        rowHint: "Bar, sidebars and apps follow the wallpaper"
                                        StyledSwitch {
                                            checked: root.weColorsOn
                                            onClicked: {
                                                root.setColorsOn(checked);
                                                checked = Qt.binding(() => root.weColorsOn);
                                            }
                                        }
                                    }
                                }

                                SettingsCard {
                                    cardIcon: "desktop_windows"
                                    cardTitle: "Display"
                                    cardSubtitle: "Default display behavior"
                                    SettingsRow {
                                        rowText: "Maximum FPS"
                                        Repeater {
                                            model: [15, 30, 60, 120, 144]
                                            delegate: HeaderChip {
                                                required property int modelData
                                                chipLabel: `${modelData}`
                                                implicitWidth: 44
                                                toggled: Number(root.g("fps")) === modelData
                                                onClicked: root.setGlobal("fps", modelData)
                                            }
                                        }
                                    }
                                    SettingsRow {
                                        rowText: "Default scaling"
                                        Repeater {
                                            model: [["fill", "Fill"], ["fit", "Fit"], ["stretch", "Stretch"], ["default", "Original"]]
                                            delegate: HeaderChip {
                                                required property var modelData
                                                chipLabel: modelData[1]
                                                toggled: root.g("scaling") === modelData[0]
                                                onClicked: root.setGlobal("scaling", modelData[0])
                                            }
                                        }
                                    }
                                    Repeater {
                                        model: [["mouse", "Mouse interaction"], ["parallax", "Parallax effect"], ["particles", "Particle effects"]]
                                        delegate: SettingsRow {
                                            required property var modelData
                                            rowText: modelData[1]
                                            StyledSwitch {
                                                checked: !!root.g(modelData[0])
                                                onClicked: {
                                                    root.setGlobal(modelData[0], checked);
                                                    checked = Qt.binding(() => !!root.g(modelData[0]));
                                                }
                                            }
                                        }
                                    }
                                }

                                SettingsCard {
                                    cardIcon: "volume_up"
                                    cardTitle: "Audio"
                                    cardSubtitle: "Volume and audio processing"
                                    SettingsRow {
                                        rowText: "Volume"
                                        StyledSlider {
                                            id: globalVol
                                            implicitWidth: 180
                                            from: 0
                                            to: 100
                                            stepSize: 5
                                            value: Number(root.g("volume"))
                                            usePercentTooltip: false
                                            tooltipContent: `${Math.round(value)}%`
                                            onMoved: root.setGlobal("volume", Math.round(value))
                                        }
                                        StyledText {
                                            Layout.preferredWidth: 40
                                            horizontalAlignment: Text.AlignRight
                                            text: `${Math.round(globalVol.value)}%`
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            color: Appearance.colors.colSubtext
                                        }
                                    }
                                    SettingsRow {
                                        rowText: "Mute all wallpapers"
                                        StyledSwitch {
                                            checked: root.g("mute")
                                            onClicked: {
                                                root.setGlobal("mute", checked);
                                                checked = Qt.binding(() => root.g("mute"));
                                            }
                                        }
                                    }
                                    SettingsRow {
                                        rowText: "Don't mute when other apps play audio"
                                        StyledSwitch {
                                            checked: root.g("noautomute")
                                            onClicked: {
                                                root.setGlobal("noautomute", checked);
                                                checked = Qt.binding(() => root.g("noautomute"));
                                            }
                                        }
                                    }
                                    SettingsRow {
                                        rowText: "Audio reactive effects"
                                        StyledSwitch {
                                            checked: root.g("audio")
                                            onClicked: {
                                                root.setGlobal("audio", checked);
                                                checked = Qt.binding(() => root.g("audio"));
                                            }
                                        }
                                    }
                                }

                                SettingsCard {
                                    cardIcon: "storefront"
                                    cardTitle: "Workshop"
                                    cardSubtitle: "Steam connection"
                                    SettingsRow {
                                        rowText: root.wsStatus.length > 0 ? root.wsStatus : "Not checked yet"
                                        rowHint: "Steam must be open. If Node.js is missing, run workshop-setup.sh once."
                                        HeaderChip {
                                            chipIcon: "refresh"
                                            chipLabel: "Check"
                                            onClicked: {
                                                root.wsStatus = "Checking Steam...";
                                                wsStatusProc.running = false;
                                                wsStatusProc.running = true;
                                            }
                                        }
                                    }
                                    SettingsRow {
                                        rowText: "Library"
                                        rowHint: `${root.weItems.length} wallpapers installed`
                                        HeaderChip {
                                            chipIcon: "refresh"
                                            chipLabel: "Rescan"
                                            onClicked: root.weRefresh()
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Row {
                        id: extraOptions
                        anchors {
                            bottom: parent.bottom
                            horizontalCenter: parent.horizontalCenter
                            bottomMargin: 8
                        }
                        spacing: 6
                        Toolbar {

                            IconToolbarButton {
                                implicitWidth: height
                                onClicked: {
                                    Wallpapers.openFallbackPicker(root.useDarkMode);
                                    GlobalStates.wallpaperSelectorOpen = false;
                                }
                                altAction: () => {
                                    Wallpapers.openFallbackPicker(root.useDarkMode);
                                    GlobalStates.wallpaperSelectorOpen = false;
                                    Config.options.wallpaperSelector.useSystemFileDialog = true;
                                }
                                text: "open_in_new"
                                StyledToolTip {
                                    text: Translation.tr("Use the system file picker instead\nRight-click to make this the default behavior")
                                }
                            }

                            IconToolbarButton {
                                implicitWidth: height
                                onClicked: {
                                    if (root.weMode) {
                                        if (root.weFiltered.length > 0)
                                            root.applyWe(root.weFiltered[Math.floor(Math.random() * root.weFiltered.length)].dir);
                                    } else {
                                        Wallpapers.randomFromCurrentFolder();
                                    }
                                }
                                text: "ifl"
                                StyledToolTip {
                                    text: Translation.tr("Pick random from this folder")
                                }
                            }

                            IconToolbarButton {
                                implicitWidth: height
                                onClicked: root.useDarkMode = !root.useDarkMode
                                text: root.useDarkMode ? "dark_mode" : "light_mode"
                                StyledToolTip {
                                    text: Translation.tr("Click to toggle light/dark mode\n(applied when wallpaper is chosen)")
                                }
                            }

                            ToolbarTextField {
                                id: filterField
                                placeholderText: focus ? Translation.tr("Search wallpapers") : Translation.tr("Hit \"/\" to search")

                                // Style
                                clip: true
                                font.pixelSize: Appearance.font.pixelSize.small

                                // Search
                                onTextChanged: {
                                    // NovelKnock: wait until you stop typing, so the grid isn't rebuilt on every key
                                    if (root.weMode) weFilterTimer.restart();
                                    else Wallpapers.searchQuery = text;
                                }

                                Keys.onPressed: event => {
                                    if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V) { // Intercept Ctrl+V to handle "paste to go to" in pickers
                                        root.handleFilePasting(event);
                                        return;
                                    } else if (text.length !== 0) {
                                        // No filtering, just navigate grid
                                        if (event.key === Qt.Key_Down) {
                                            root.activeGrid().moveSelection(grid.columns);
                                            event.accepted = true;
                                            return;
                                        }
                                        if (event.key === Qt.Key_Up) {
                                            root.activeGrid().moveSelection(-grid.columns);
                                            event.accepted = true;
                                            return;
                                        }
                                    }
                                    event.accepted = false;
                                }
                            }
                        }

                        ToolbarPairedFab {
                            iconText: "close"
                            onClicked: GlobalStates.wallpaperSelectorOpen = false;
                            StyledToolTip {
                                text: Translation.tr("Cancel wallpaper selection")
                            }
                        }
                    }
                }
            }

            Rectangle { // details panel (Wallpaper Engine)
                id: weDetails
                visible: root.weMode && root.weTab !== "settings"
                readonly property bool workshop: root.weTab === "workshop"
                readonly property var item: workshop ? root.wsSel : root.weSel
                Layout.fillHeight: true
                Layout.margins: 4
                Layout.preferredWidth: 340
                color: Appearance.colors.colLayer1
                radius: wallpaperGridBackground.radius - Layout.margins
                clip: true

                StyledText { // nothing selected
                    anchors.centerIn: parent
                    visible: !weDetails.item
                    width: parent.width - 40
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    color: Appearance.colors.colSubtext
                    text: root.weMessage.length > 0 ? root.weMessage : "Click a wallpaper to see its details and settings.\nDouble-click to apply it right away."
                }

                Flickable {
                    id: weDetailsFlick
                    visible: !!weDetails.item
                    anchors.fill: parent
                    contentHeight: weDetailsColumn.implicitHeight + 24
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: StyledScrollBar {}

                    ColumnLayout {
                        id: weDetailsColumn
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                            margins: 12
                        }
                        spacing: 10

                        // preview
                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: width * 9 / 16
                            Image {
                                id: weDetailsPreview
                                anchors.fill: parent
                                source: !weDetails.item ? "" : weDetails.workshop ? weDetails.item.preview : (weDetails.item.preview.length > 0 ? `file://${weDetails.item.preview}` : "")
                                sourceSize.width: 640
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                layer.enabled: true
                                layer.effect: OpacityMask {
                                    maskSource: Rectangle {
                                        width: weDetailsPreview.width
                                        height: weDetailsPreview.height
                                        radius: Appearance.rounding.small
                                    }
                                }
                            }
                            RippleButton { // close
                                anchors {
                                    top: parent.top
                                    right: parent.right
                                    margins: 6
                                }
                                implicitWidth: 30
                                implicitHeight: 30
                                buttonRadius: 15
                                colBackground: ColorUtils.transparentize("#000000", 0.4)
                                onClicked: weDetails.workshop ? (root.wsSel = null) : root.weSelect(null)
                                contentItem: MaterialSymbol {
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    text: "close"
                                    iconSize: 18
                                    color: "#ffffff"
                                }
                            }
                        }

                        // title
                        StyledText {
                            Layout.fillWidth: true
                            text: weDetails.item?.title ?? ""
                            wrapMode: Text.Wrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.large
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            Layout.fillWidth: true
                            visible: !weDetails.workshop && root.weShowingOn(weDetails.item?.id ?? "").length > 0
                            text: `Playing on ${root.weShowingOn(weDetails.item?.id ?? "").join(" and ")}`
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colPrimary
                        }

                        // ===== Library: Apply (all / one display) + delete =====
                        RowLayout {
                            visible: !weDetails.workshop
                            Layout.fillWidth: true
                            spacing: 6
                            RippleButton {
                                Layout.fillWidth: true
                                implicitHeight: 40
                                buttonRadius: 12
                                colBackground: Appearance.colors.colPrimary
                                colBackgroundHover: Appearance.colors.colPrimaryHover
                                onClicked: root.weApplyTo(weDetails.item?.dir, "")
                                contentItem: RowLayout {
                                    spacing: 6
                                    Item { Layout.fillWidth: true }
                                    MaterialSymbol {
                                        text: "desktop_windows"
                                        iconSize: 18
                                        color: Appearance.colors.colOnPrimary
                                    }
                                    StyledText {
                                        text: "Apply to all displays"
                                        color: Appearance.colors.colOnPrimary
                                    }
                                    Item { Layout.fillWidth: true }
                                }
                            }
                            RippleButton { // choose a display
                                implicitWidth: 40
                                implicitHeight: 40
                                buttonRadius: 12
                                toggled: root.weDisplayMenu
                                colBackground: Appearance.colors.colPrimary
                                colBackgroundHover: Appearance.colors.colPrimaryHover
                                colBackgroundToggled: Appearance.colors.colPrimaryActive
                                onClicked: root.weDisplayMenu = !root.weDisplayMenu
                                contentItem: MaterialSymbol {
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    text: root.weDisplayMenu ? "expand_less" : "expand_more"
                                    iconSize: 20
                                    color: Appearance.colors.colOnPrimary
                                }
                                StyledToolTip {
                                    text: "Apply to one display"
                                }
                            }
                            RippleButton { // delete (unsubscribe)
                                implicitWidth: root.weDeleteArmed ? 120 : 40
                                implicitHeight: 40
                                buttonRadius: 12
                                colBackground: root.weDeleteArmed ? "#b3261e" : Appearance.colors.colLayer2
                                onClicked: root.weDelete(weDetails.item)
                                contentItem: RowLayout {
                                    spacing: 4
                                    Item { Layout.fillWidth: true }
                                    MaterialSymbol {
                                        text: "delete"
                                        iconSize: 18
                                        color: root.weDeleteArmed ? "#ffffff" : Appearance.colors.colOnLayer2
                                    }
                                    StyledText {
                                        visible: root.weDeleteArmed
                                        text: "Sure?"
                                        color: "#ffffff"
                                    }
                                    Item { Layout.fillWidth: true }
                                }
                                StyledToolTip {
                                    text: "Unsubscribe and delete from your library"
                                }
                            }
                        }
                        ColumnLayout { // display list
                            visible: !weDetails.workshop && root.weDisplayMenu
                            Layout.fillWidth: true
                            spacing: 4
                            Repeater {
                                model: Quickshell.screens
                                delegate: RippleButton {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: 38
                                    buttonRadius: 10
                                    colBackground: Appearance.colors.colLayer2
                                    horizontalPadding: 12
                                    onClicked: root.weApplyTo(weDetails.item?.dir, modelData.name)
                                    contentItem: RowLayout {
                                        spacing: 8
                                        MaterialSymbol {
                                            text: "monitor"
                                            iconSize: 18
                                            color: Appearance.colors.colOnLayer2
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: `Apply to ${modelData.name}`
                                            color: Appearance.colors.colOnLayer2
                                            elide: Text.ElideRight
                                        }
                                        StyledText {
                                            text: modelData.model ?? ""
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            color: Appearance.colors.colSubtext
                                        }
                                    }
                                }
                            }
                        }
                        StyledText {
                            Layout.fillWidth: true
                            visible: root.weMessage.length > 0
                            text: root.weMessage
                            wrapMode: Text.Wrap
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                        }

                        // ===== Workshop: Subscribe / Apply =====
                        RippleButton {
                            visible: weDetails.workshop
                            Layout.fillWidth: true
                            implicitHeight: 40
                            buttonRadius: 12
                            readonly property string folder: weDetails.workshop && weDetails.item ? root.wsFolder(weDetails.item) : ""
                            readonly property var dl: weDetails.item ? root.wsDownloads[weDetails.item.id] : undefined
                            colBackground: Appearance.colors.colPrimary
                            colBackgroundHover: Appearance.colors.colPrimaryHover
                            onClicked: root.wsActivate(weDetails.item)
                            contentItem: RowLayout {
                                spacing: 6
                                Item { Layout.fillWidth: true }
                                MaterialSymbol {
                                    text: parent.parent.folder.length > 0 ? "play_arrow" : typeof parent.parent.dl === "number" ? "downloading" : "add"
                                    iconSize: 18
                                    color: Appearance.colors.colOnPrimary
                                }
                                StyledText {
                                    text: parent.parent.folder.length > 0 ? "Apply to all displays" : typeof parent.parent.dl === "number" ? `Downloading ${Math.round(parent.parent.dl * 100)}%` : "Subscribe"
                                    color: Appearance.colors.colOnPrimary
                                }
                                Item { Layout.fillWidth: true }
                            }
                        }

                        // ===== info rows =====
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 1
                            color: Appearance.colors.colOutlineVariant
                        }
                        Repeater {
                            model: {
                                const it = weDetails.item;
                                if (!it) return [];
                                const rows = [["category", "Type", root.typeNames[it.type] ?? it.type], ["shield", "Rating", it.rating || "Everyone"]];
                                if (weDetails.workshop) {
                                    rows.push(["thumb_up", "Likes", `${it.votes ?? 0}`]);
                                } else {
                                    if (root.weInfo.resolution) rows.push(["aspect_ratio", "Resolution", root.weInfo.resolution]);
                                    if (root.weInfo.size) rows.push(["hard_drive", "Size", root.formatSize(root.weInfo.size)]);
                                    rows.push(["tag", "Workshop ID", it.id]);
                                }
                                return rows;
                            }
                            delegate: RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 8
                                MaterialSymbol {
                                    text: modelData[0]
                                    iconSize: 18
                                    color: Appearance.colors.colSubtext
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: modelData[1]
                                    color: Appearance.colors.colSubtext
                                }
                                StyledText {
                                    text: modelData[2]
                                    color: Appearance.colors.colOnLayer1
                                }
                            }
                        }

                        // tags
                        Flow {
                            Layout.fillWidth: true
                            visible: !weDetails.workshop && (weDetails.item?.tags ?? []).length > 0
                            spacing: 6
                            Repeater {
                                model: weDetails.workshop ? [] : (weDetails.item?.tags ?? [])
                                delegate: Rectangle {
                                    required property string modelData
                                    implicitWidth: tagText.implicitWidth + 16
                                    implicitHeight: 24
                                    radius: 12
                                    color: Appearance.colors.colLayer2
                                    StyledText {
                                        id: tagText
                                        anchors.centerIn: parent
                                        text: parent.modelData
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colOnLayer2
                                    }
                                }
                            }
                        }

                        // ===== settings for this wallpaper =====
                        ColumnLayout {
                            visible: !weDetails.workshop
                            Layout.fillWidth: true
                            spacing: 8
                            readonly property string wid: weDetails.item?.id ?? ""

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 1
                                color: Appearance.colors.colOutlineVariant
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                MaterialSymbol {
                                    text: "tune"
                                    iconSize: 18
                                    color: Appearance.colors.colOnLayer1
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: "Settings for this wallpaper"
                                    color: Appearance.colors.colOnLayer1
                                    font.weight: Font.Medium
                                }
                                RippleButton {
                                    implicitHeight: 28
                                    implicitWidth: resetText.implicitWidth + 18
                                    buttonRadius: 8
                                    onClicked: root.weSetSetting(parent.parent.wid, null, null)
                                    contentItem: StyledText {
                                        id: resetText
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        text: "Reset"
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: Appearance.colors.colPrimary
                                    }
                                }
                            }

                            // scaling (per display)
                            StyledText {
                                text: "Scaling"
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.small
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Repeater {
                                    model: [["fill", "Fill"], ["fit", "Fit"], ["stretch", "Stretch"], ["default", "Original"]]
                                    delegate: HeaderChip {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        chipLabel: modelData[1]
                                        toggled: root.weSetting(weDetails.item?.id ?? "", "scaling") === modelData[0]
                                        onClicked: root.weSetSetting(weDetails.item?.id ?? "", "scaling", modelData[0])
                                    }
                                }
                            }

                            // volume
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                MaterialSymbol {
                                    text: volSlider.value <= 0 ? "volume_off" : "volume_up"
                                    iconSize: 18
                                    color: Appearance.colors.colOnLayer1
                                }
                                StyledText {
                                    text: "Volume"
                                    color: Appearance.colors.colOnLayer1
                                }
                                StyledSlider {
                                    id: volSlider
                                    Layout.fillWidth: true
                                    from: 0
                                    to: 100
                                    stepSize: 5
                                    value: Number(root.weSetting(weDetails.item?.id ?? "", "volume"))
                                    usePercentTooltip: false
                                    tooltipContent: `${Math.round(value)}%`
                                    onMoved: root.weSetSetting(weDetails.item?.id ?? "", "volume", Math.round(value))
                                }
                                StyledText {
                                    Layout.preferredWidth: 40
                                    horizontalAlignment: Text.AlignRight
                                    text: volSlider.value <= 0 ? "Muted" : `${Math.round(volSlider.value)}%`
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colSubtext
                                }
                            }

                            // switches
                            Repeater {
                                model: [["audio", "graphic_eq", "Audio reactive effects"], ["mouse", "mouse", "Mouse interaction"], ["parallax", "3d_rotation", "Parallax effect"], ["particles", "grain", "Particles"]]
                                delegate: RowLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: 8
                                    MaterialSymbol {
                                        text: modelData[1]
                                        iconSize: 18
                                        color: Appearance.colors.colOnLayer1
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: modelData[2]
                                        color: Appearance.colors.colOnLayer1
                                    }
                                    StyledSwitch {
                                        checked: !!root.weSetting(weDetails.item?.id ?? "", modelData[0])
                                        onClicked: {
                                            root.weSetSetting(weDetails.item?.id ?? "", modelData[0], checked);
                                            checked = Qt.binding(() => !!root.weSetting(weDetails.item?.id ?? "", modelData[0]));
                                        }
                                    }
                                }
                            }
                            StyledText {
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                                text: "Changes apply right away if it is playing. Scaling is per display. With two different wallpapers showing, volume uses the louder one, and mouse, parallax, particles and audio effects turn off only if both have them off."
                            }
                            StyledText {
                                Layout.fillWidth: true
                                visible: root.g("mute")
                                wrapMode: Text.Wrap
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colPrimary
                                text: "All wallpapers are muted in Settings, turn that off to hear this one."
                            }

                            StyledText {
                                visible: root.wePropsLoading
                                Layout.fillWidth: true
                                text: "Loading wallpaper options..."
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                            }

                            // ===== the wallpaper's own options =====
                            Rectangle {
                                visible: root.weProps.length > 0
                                Layout.fillWidth: true
                                Layout.topMargin: 4
                                implicitHeight: 1
                                color: Appearance.colors.colOutlineVariant
                            }
                            RowLayout {
                                visible: root.weProps.length > 0
                                Layout.fillWidth: true
                                MaterialSymbol {
                                    text: "palette"
                                    iconSize: 18
                                    color: Appearance.colors.colOnLayer1
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: "Wallpaper options"
                                    color: Appearance.colors.colOnLayer1
                                    font.weight: Font.Medium
                                }
                            }
                            Repeater {
                                model: root.weProps
                                delegate: ColumnLayout {
                                    id: propRow
                                    required property var modelData
                                    readonly property string wid: weDetails.item?.id ?? ""
                                    readonly property var current: root.weProp(wid, modelData)
                                    Layout.fillWidth: true
                                    spacing: 4

                                    // text label only
                                    StyledText {
                                        visible: propRow.modelData.type === "text"
                                        Layout.fillWidth: true
                                        wrapMode: Text.Wrap
                                        text: propRow.modelData.label
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: Appearance.colors.colSubtext
                                    }

                                    // on / off
                                    RowLayout {
                                        visible: propRow.modelData.type === "bool"
                                        Layout.fillWidth: true
                                        StyledText {
                                            Layout.fillWidth: true
                                            wrapMode: Text.Wrap
                                            text: propRow.modelData.label
                                            color: Appearance.colors.colOnLayer1
                                        }
                                        StyledSwitch {
                                            checked: !!propRow.current
                                            onClicked: {
                                                root.weSetProp(propRow.wid, propRow.modelData.name, checked);
                                                checked = Qt.binding(() => !!propRow.current);
                                            }
                                        }
                                    }

                                    // slider
                                    StyledText {
                                        visible: propRow.modelData.type === "slider"
                                        Layout.fillWidth: true
                                        wrapMode: Text.Wrap
                                        text: `${propRow.modelData.label}: ${Number(propRow.current).toFixed(propRow.modelData.step > 0 && propRow.modelData.step < 1 ? 2 : 0)}`
                                        color: Appearance.colors.colOnLayer1
                                    }
                                    StyledSlider {
                                        visible: propRow.modelData.type === "slider"
                                        Layout.fillWidth: true
                                        from: propRow.modelData.min ?? 0
                                        to: propRow.modelData.max ?? 100
                                        stepSize: propRow.modelData.step ?? 0
                                        value: Number(propRow.current ?? 0)
                                        usePercentTooltip: false
                                        tooltipContent: `${Number(value).toFixed(2)}`
                                        onMoved: root.weSetProp(propRow.wid, propRow.modelData.name, Math.round(value * 1000) / 1000)
                                    }

                                    // dropdown
                                    StyledText {
                                        visible: propRow.modelData.type === "combo"
                                        Layout.fillWidth: true
                                        wrapMode: Text.Wrap
                                        text: propRow.modelData.label
                                        color: Appearance.colors.colOnLayer1
                                    }
                                    StyledComboBox {
                                        visible: propRow.modelData.type === "combo"
                                        Layout.fillWidth: true
                                        model: propRow.modelData.options ?? []
                                        textRole: "label"
                                        currentIndex: Math.max(0, (propRow.modelData.options ?? []).findIndex(o => o.value === String(propRow.current)))
                                        onActivated: index => root.weSetProp(propRow.wid, propRow.modelData.name, propRow.modelData.options[index].value)
                                    }

                                    // color
                                    RowLayout {
                                        visible: propRow.modelData.type === "color"
                                        Layout.fillWidth: true
                                        spacing: 6
                                        StyledText {
                                            Layout.fillWidth: true
                                            wrapMode: Text.Wrap
                                            text: propRow.modelData.label
                                            color: Appearance.colors.colOnLayer1
                                        }
                                        Rectangle {
                                            implicitWidth: 28
                                            implicitHeight: 28
                                            radius: 8
                                            color: /^#[0-9a-fA-F]{6}$/.test(String(propRow.current)) ? propRow.current : "transparent"
                                            border.width: 1
                                            border.color: Appearance.colors.colOutlineVariant
                                        }
                                        MaterialTextField {
                                            implicitWidth: 96
                                            text: String(propRow.current)
                                            onEditingFinished: {
                                                let t = text.trim();
                                                if (!t.startsWith("#")) t = "#" + t;
                                                if (/^#[0-9a-fA-F]{6}$/.test(t)) root.weSetProp(propRow.wid, propRow.modelData.name, t.toUpperCase());
                                            }
                                        }
                                        RippleButton { // pick a color from the screen
                                            implicitWidth: 32
                                            implicitHeight: 32
                                            buttonRadius: 16
                                            onClicked: {
                                                pickColorProc.target = propRow.modelData.name;
                                                pickColorProc.wid = propRow.wid;
                                                pickColorProc.running = true;
                                            }
                                            contentItem: MaterialSymbol {
                                                horizontalAlignment: Text.AlignHCenter
                                                verticalAlignment: Text.AlignVCenter
                                                text: "colorize"
                                                iconSize: 18
                                                color: Appearance.colors.colOnLayer1
                                            }
                                            StyledToolTip {
                                                text: "Pick a color from the screen"
                                            }
                                        }
                                    }

                                    // text input
                                    StyledText {
                                        visible: propRow.modelData.type === "textinput"
                                        Layout.fillWidth: true
                                        wrapMode: Text.Wrap
                                        text: propRow.modelData.label
                                        color: Appearance.colors.colOnLayer1
                                    }
                                    MaterialTextField {
                                        visible: propRow.modelData.type === "textinput"
                                        Layout.fillWidth: true
                                        text: String(propRow.current ?? "")
                                        onEditingFinished: root.weSetProp(propRow.wid, propRow.modelData.name, text)
                                    }
                                }
                            }
                            StyledText {
                                Layout.fillWidth: true
                                visible: root.weProps.length > 0
                                wrapMode: Text.Wrap
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                                text: "Options with the same name are shared if two different wallpapers show at once."
                            }
                            Process {
                                id: pickColorProc
                                property string target
                                property string wid
                                command: ["hyprpicker", "--no-fancy", "--format=hex"]
                                stdout: StdioCollector {
                                    id: pickColorCollector
                                    onStreamFinished: {
                                        const t = pickColorCollector.text.trim().toUpperCase();
                                        if (/^#[0-9A-F]{6}$/.test(t)) root.weSetProp(pickColorProc.wid, pickColorProc.target, t);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Connections {
        target: GlobalStates
        function onWallpaperSelectorOpenChanged() {
            if (GlobalStates.wallpaperSelectorOpen && monitorIsFocused) {
                filterField.forceActiveFocus();
            }
        }
    }

    Connections {
        target: Wallpapers
        function onChanged() {
            GlobalStates.wallpaperSelectorOpen = false;
        }
    }
}
