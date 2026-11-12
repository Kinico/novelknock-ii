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
        property string label
        property string icon
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
                    visible: chip.icon.length > 0
                    text: chip.icon
                    iconSize: Appearance.font.pixelSize.normal
                    color: chip.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                }
                StyledText {
                    text: chip.label
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
                root.weCurrent = JSON.parse(weCurrentFile.text()).key ?? "";
            } catch (e) {
                root.weCurrent = "";
            }
        }
    }
    Component.onCompleted: root.weRefresh()

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
    Timer { // search the Workshop shortly after you stop typing
        id: wsSearchTimer
        interval: 600
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
                        implicitWidth: 140
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
                            icon: "photo_library"
                            label: root.weLoading ? "Library" : `Library ${root.weItems.length}`
                            toggled: root.weTab === "library"
                            onClicked: root.setWeTab("library")
                        }
                        HeaderChip {
                            icon: "storefront"
                            label: "Workshop"
                            toggled: root.weTab === "workshop"
                            onClicked: root.setWeTab("workshop")
                        }
                        Item {
                            Layout.fillWidth: true
                        }

                        // Library filters (click to switch)
                        HeaderChip {
                            visible: root.weTab === "library"
                            icon: "category"
                            label: root.typeNames[root.prefs.libType]
                            toggled: root.prefs.libType !== "all"
                            onClicked: root.setPref("libType", root.cycle(["all", "scene", "video", "web"], root.prefs.libType))
                        }
                        HeaderChip {
                            visible: root.weTab === "library"
                            icon: "shield"
                            label: root.ratingNames[root.prefs.libRating]
                            toggled: root.prefs.libRating !== "all"
                            onClicked: root.setPref("libRating", root.cycle(["all", "Everyone", "Questionable", "Mature"], root.prefs.libRating))
                        }
                        HeaderChip {
                            visible: root.weTab === "library"
                            icon: "sort"
                            label: root.libSortNames[root.prefs.libSort]
                            onClicked: root.setPref("libSort", root.cycle(["newest", "title"], root.prefs.libSort))
                        }

                        // Workshop filters
                        HeaderChip {
                            visible: root.weTab === "workshop"
                            icon: "trending_up"
                            label: root.weFilter.trim().length > 0 ? "Best match" : root.wsSortNames[root.prefs.wsSort]
                            onClicked: root.setPref("wsSort", root.cycle(["trend", "votes", "subscriptions", "date", "updated"], root.prefs.wsSort))
                        }
                        HeaderChip {
                            visible: root.weTab === "workshop"
                            icon: "category"
                            label: root.typeNames[root.prefs.wsType]
                            toggled: root.prefs.wsType !== "all"
                            onClicked: root.setPref("wsType", root.cycle(["all", "Scene", "Video", "Web"], root.prefs.wsType))
                        }
                        HeaderChip {
                            visible: root.weTab === "workshop"
                            icon: "shield"
                            label: root.ratingNames[root.prefs.wsRating]
                            toggled: root.prefs.wsRating !== "all"
                            onClicked: root.setPref("wsRating", root.cycle(["all", "Everyone", "Questionable", "Mature"], root.prefs.wsRating))
                        }
                        HeaderChip {
                            visible: root.weTab === "workshop"
                            icon: "chevron_left"
                            label: ""
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
                            icon: "chevron_right"
                            label: ""
                            implicitWidth: 32
                            enabled: root.wsHasNext && !root.wsLoading
                            opacity: enabled ? 1 : 0.4
                            onClicked: root.wsQuery(root.wsPage + 1)
                        }

                        HeaderChip {
                            icon: "refresh"
                            label: ""
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
                            readonly property bool isCurrent: modelData.id === root.weCurrent
                            readonly property bool highlighted: index === weGrid.currentIndex || containsMouse
                            width: weGrid.cellWidth
                            height: weGrid.cellHeight
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: weGrid.currentIndex = index
                            onClicked: root.applyWe(modelData.dir)

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
                            readonly property bool highlighted: index === wsGrid.currentIndex || containsMouse
                            width: wsGrid.cellWidth
                            height: wsGrid.cellHeight
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: wsGrid.currentIndex = index
                            onClicked: root.wsActivate(modelData)

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
                                    Wallpapers.searchQuery = text;
                                    root.weFilter = text;
                                    if (root.weMode && root.weTab === "workshop") wsSearchTimer.restart();
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
