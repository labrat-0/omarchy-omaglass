import QtQuick
import QtQuick.Effects
import qs.Commons

// A platform mark, optionally in the 1977 six-stripe Apple colours.
//
// The stripes are a gradient masked by the glyph itself rather than artwork:
// the font already has the silhouette, so masking keeps it sharp at any size
// and avoids shipping a second asset that would have to track the font.
Item {
  id: root

  property string glyph: ""
  property real size: 20
  property color color: Color.foreground
  property bool rainbow: false

  implicitWidth: size
  implicitHeight: size * 1.15

  // Solid form. Also the mask source when striped, which is why it stays
  // laid out rather than `visible: false` — a hidden item has nothing to
  // rasterise into the layer texture.
  // Fills the item rather than centring: MultiEffect maps mask and source by
  // geometry, so any size difference between them skews the result.
  Text {
    id: mark
    anchors.fill: parent
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    text: root.glyph
    font.family: Style.font.family
    font.pixelSize: root.size
    color: root.rainbow ? "white" : root.color
    opacity: root.rainbow ? 0 : 1
    layer.enabled: root.rainbow
  }

  // Inset to the glyph's ink rather than the line box. Spanning the full box
  // would put green and blue in the ascender and descender gaps, so the apple
  // itself would only ever show the middle bands.
  Rectangle {
    id: stripes
    anchors.fill: parent
    anchors.topMargin: root.size * 0.13
    anchors.bottomMargin: root.size * 0.26
    opacity: 0
    layer.enabled: root.rainbow
    // Paired stops make hard bands instead of a blend.
    gradient: Gradient {
      GradientStop { position: 0.000; color: "#61BB46" }
      GradientStop { position: 0.167; color: "#61BB46" }
      GradientStop { position: 0.167; color: "#FDB827" }
      GradientStop { position: 0.333; color: "#FDB827" }
      GradientStop { position: 0.333; color: "#F5821F" }
      GradientStop { position: 0.500; color: "#F5821F" }
      GradientStop { position: 0.500; color: "#E03A3E" }
      GradientStop { position: 0.667; color: "#E03A3E" }
      GradientStop { position: 0.667; color: "#963D97" }
      GradientStop { position: 0.833; color: "#963D97" }
      GradientStop { position: 0.833; color: "#009DDC" }
      GradientStop { position: 1.000; color: "#009DDC" }
    }
  }

  MultiEffect {
    anchors.fill: stripes
    visible: root.rainbow
    source: stripes
    maskEnabled: true
    maskSource: mark
  }
}
