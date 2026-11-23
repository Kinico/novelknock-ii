import QtQuick
import qs.modules.common

// A picture from ~/Pictures/Elaina/<name>.png (or .jpg / .webp). Your own images, never shipped in the repo.
// "found" is false when the file is missing, so each spot can fall back to its drawn look.
Image {
    id: art
    required property string name
    property int tryIndex: 0
    readonly property var exts: ["png", "jpg", "jpeg", "webp"]
    readonly property bool found: status === Image.Ready
    source: `${Directories.pictures}/Elaina/${art.name}.${art.exts[art.tryIndex]}`
    asynchronous: true
    cache: true
    smooth: true
    mipmap: true
    fillMode: Image.PreserveAspectCrop
    visible: found
    onStatusChanged: {
        if (status === Image.Error && tryIndex < exts.length - 1) tryIndex += 1;
    }
}
