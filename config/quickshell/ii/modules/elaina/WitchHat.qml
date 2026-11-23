import QtQuick
import QtQuick.Shapes
import qs.modules.elaina

// A plain pointed witch hat with a brim and a band, drawn with shapes
Item {
    id: hat
    property color hatColor: ElainaTheme.robe
    property color bandColor: ElainaTheme.ribbon
    property color outline: ElainaTheme.lavender
    implicitWidth: 30
    implicitHeight: 26

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath { // cone, tip bending to the right
            fillColor: hat.hatColor
            strokeColor: hat.outline
            strokeWidth: 1.2
            startX: hat.width * 0.30; startY: hat.height * 0.74
            PathQuad { x: hat.width * 0.72; y: hat.height * 0.06; controlX: hat.width * 0.42; controlY: hat.height * 0.25 }
            PathQuad { x: hat.width * 0.70; y: hat.height * 0.74; controlX: hat.width * 0.62; controlY: hat.height * 0.38 }
            PathLine { x: hat.width * 0.30; y: hat.height * 0.74 }
        }
        ShapePath { // band
            fillColor: hat.bandColor
            strokeColor: "transparent"
            startX: hat.width * 0.31; startY: hat.height * 0.62
            PathLine { x: hat.width * 0.69; y: hat.height * 0.62 }
            PathLine { x: hat.width * 0.70; y: hat.height * 0.74 }
            PathLine { x: hat.width * 0.30; y: hat.height * 0.74 }
            PathLine { x: hat.width * 0.31; y: hat.height * 0.62 }
        }
        ShapePath { // brim
            fillColor: hat.hatColor
            strokeColor: hat.outline
            strokeWidth: 1.2
            startX: hat.width * 0.04; startY: hat.height * 0.80
            PathQuad { x: hat.width * 0.96; y: hat.height * 0.80; controlX: hat.width * 0.5; controlY: hat.height * 1.02 }
            PathQuad { x: hat.width * 0.04; y: hat.height * 0.80; controlX: hat.width * 0.5; controlY: hat.height * 0.62 }
        }
    }
}
