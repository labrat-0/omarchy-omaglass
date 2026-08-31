import QtQuick
import qs.Commons

// The OmaGlass mark: a laptop with a phone standing in front of it, each
// carrying a vertical "pane" line.
//
// Drawn rather than shipped as an image so it takes the bar's foreground
// colour and stays crisp at any size. The source artwork is pure line work,
// which is exactly what strokes reproduce well.
Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground
  // The pane lines are the first thing to become noise when the mark is small.
  property bool showPanes: iconSize >= 18

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  // Stroke weight tracks the mark so the shape keeps its proportions when it
  // is drawn large in the panel rather than tiny in the bar.
  readonly property real stroke: Math.max(1, Math.round(iconSize / 16))

  Item {
    id: mark
    anchors.centerIn: parent
    width: root.iconSize
    height: Math.round(root.iconSize * 0.74)

    // Laptop screen
    Rectangle {
      id: screen
      x: Math.round(mark.width * 0.06)
      y: 0
      width: Math.round(mark.width * 0.70)
      height: Math.round(mark.height * 0.76)
      color: "transparent"
      border.color: root.color
      border.width: root.stroke
    }

    // Laptop base
    Rectangle {
      x: 0
      y: screen.y + screen.height
      width: Math.round(mark.width * 0.86)
      height: Math.max(root.stroke * 2, Math.round(mark.height * 0.14))
      color: "transparent"
      border.color: root.color
      border.width: root.stroke
    }

    // Phone, standing in front and overlapping the base
    Rectangle {
      id: phone
      x: Math.round(mark.width * 0.54)
      y: Math.round(mark.height * 0.26)
      width: Math.round(mark.width * 0.26)
      height: Math.round(mark.height * 0.74)
      color: "transparent"
      border.color: root.color
      border.width: root.stroke
    }

    Rectangle {
      visible: root.showPanes
      width: root.stroke
      height: Math.round(screen.height * 0.62)
      x: screen.x + Math.round(screen.width * 0.42)
      y: screen.y + Math.round(screen.height * 0.16)
      color: root.color
    }

    Rectangle {
      visible: root.showPanes
      width: root.stroke
      height: Math.round(phone.height * 0.60)
      x: phone.x + Math.round(phone.width * 0.44)
      y: phone.y + Math.round(phone.height * 0.18)
      color: root.color
    }
  }
}
