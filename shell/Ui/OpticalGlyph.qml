import QtQuick
import qs.Commons
import qs.Commons as Commons

Item {
  id: root

  property string text: ""
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.body
  property real paintedSize: 0
  property color color: Commons.Color.foreground
  property bool debugBounds: false

  readonly property int renderedFontSize: Math.max(1, Math.round(fontSize))
  readonly property real tightWidth: Math.max(1, glyphMetrics.tightBoundingRect.width)
  readonly property real tightHeight: Math.max(1, glyphMetrics.tightBoundingRect.height)
  readonly property real paintedScale: paintedSize > 0
    ? Math.min(paintedSize, width, height) / Math.max(tightWidth, tightHeight)
    : 1
  readonly property real paintedWidth: tightWidth * paintedScale
  readonly property real paintedHeight: tightHeight * paintedScale
  readonly property real horizontalCorrection: glyph.implicitWidth / 2 - (glyphMetrics.tightBoundingRect.x + tightWidth / 2)
  // The ink centre, in this item's coordinates, *after* the rotation above has
  // been applied. Callers (BarIconButton) use these to line the glyph up on the
  // bar; reporting the unrotated point made a rotated glyph (the pocket's mark
  // turns 90 degrees when it opens) read as off-centre by the offset between
  // the two.
  readonly property real _inkCenterX: glyph.x + (glyphMetrics.tightBoundingRect.x + tightWidth / 2) * paintedScale
  readonly property real _inkCenterY: glyph.y + (glyph.baselineOffset + glyphMetrics.tightBoundingRect.y + tightHeight / 2) * paintedScale
  readonly property real _rotationRadians: root.rotation * Math.PI / 180
  readonly property real paintedCenterX: {
    if (root.rotation === 0) return _inkCenterX
    var dx = _inkCenterX - root.width / 2
    var dy = _inkCenterY - root.height / 2
    var c = Math.cos(_rotationRadians)
    var s = Math.sin(_rotationRadians)
    return root.width / 2 + dx * c - dy * s
  }
  readonly property real paintedCenterY: {
    if (root.rotation === 0) return _inkCenterY
    var dx = _inkCenterX - root.width / 2
    var dy = _inkCenterY - root.height / 2
    var c = Math.cos(_rotationRadians)
    var s = Math.sin(_rotationRadians)
    return root.height / 2 + dx * s + dy * c
  }
  readonly property real baselineY: glyph.y + glyph.baselineOffset * paintedScale

  TextMetrics {
    id: glyphMetrics
    font.family: root.fontFamily
    font.pixelSize: root.renderedFontSize
    text: root.text
  }

  Text {
    id: glyph
    textFormat: Text.PlainText
    // Bar icons fit their painted bounds. Text labels retain their line box.
    x: root.width / 2 - (glyphMetrics.tightBoundingRect.x + root.tightWidth / 2) * root.paintedScale
    y: root.paintedSize > 0
      ? root.height / 2 - (baselineOffset + glyphMetrics.tightBoundingRect.y + root.tightHeight / 2) * root.paintedScale
      : Math.round((root.height - height) / 2)
    text: root.text
    color: root.color
    font.family: root.fontFamily
    font.pixelSize: root.renderedFontSize
    transformOrigin: Item.TopLeft
    scale: root.paintedScale
    renderType: root.paintedSize > 0 ? Text.CurveRendering : Text.NativeRendering
  }

  Rectangle {
    visible: root.debugBounds
    anchors.fill: parent
    color: "transparent"
    border.width: 1
    border.color: "#4488ff"
  }

  Rectangle {
    visible: root.debugBounds
    x: 0
    y: Math.round(root.baselineY)
    width: parent.width
    height: 1
    color: "#44ff88"
  }
}
