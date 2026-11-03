// The sounding line: Fathom's depth gauge beside the Deep. It reads depth the
// way a lead line reads water -- the surface is now, eight fathoms down is two
// hours and more. Every window is a mark at its depth, and the sounding lead
// hangs on the line at the selection's depth, descending as you dive.
//
// Ported from Fathom (SoundingLine.qml) by Maarten Tolhuijs, MIT licensed.

pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons // qmllint disable import
import "Layout.js" as Layout

Item {
  id: gauge

  property var controller: null
  required property var theme
  property real unit: 1
  property real textUnit: unit
  // The selection's depth, animated by the view as the camera moves.
  property real leadDepth: 0

  readonly property int maxDepth: 8
  readonly property real lineX: 46 * textUnit
  readonly property real lineTop: 22 * unit
  readonly property real lineBottom: height - 8 * unit
  readonly property real markSize: 6 * unit
  readonly property real markStep: markSize + 2 * unit
  readonly property real marksX: lineX + 8 * unit
  readonly property int maxColumns: Math.max(1, Math.floor((width - marksX - 18 * textUnit) / markStep))
  readonly property var marks: {
    const depths = []
    const list = controller ? controller.field : []
    for (let i = 0; i < list.length; i++) depths.push(list[i] ? list[i].depth : 0)
    return Layout.soundingMarks(depths, lineTop, lineBottom, maxDepth, markSize * 1.3, maxColumns)
  }

  // The surface.
  Text {
    x: gauge.lineX - width / 2
    y: gauge.lineTop - height - 4 * gauge.unit
    color: gauge.theme.textFaint
    font.family: Style.font.family
    font.pixelSize: 14 * gauge.textUnit
    textFormat: Text.PlainText
    text: "≈"
  }

  // The line itself.
  Rectangle {
    x: gauge.lineX - width / 2
    y: gauge.lineTop
    width: 1
    height: Math.max(1, gauge.lineBottom - gauge.lineTop)
    color: gauge.theme.line
  }

  // A tick per fathom, with the time it stands for.
  Repeater {
    model: gauge.maxDepth + 1

    delegate: Item {
      id: tick

      required property int index

      y: Layout.soundingY(index, gauge.lineTop, gauge.lineBottom, gauge.maxDepth)

      Rectangle {
        x: gauge.lineX - width / 2
        y: -height / 2
        width: (tick.index % 2 === 0 ? 9 : 5) * gauge.unit
        height: 1
        color: gauge.theme.tick
      }

      Text {
        x: gauge.lineX + 12 * gauge.unit
        y: -height / 2
        visible: tick.index % 2 === 0
        color: gauge.theme.textFaint
        font.family: Style.font.family
        font.pixelSize: 10 * gauge.textUnit
        textFormat: Text.PlainText
        text: {
          if (tick.index === 0) return "now"
          const seconds = 30 * (Math.pow(2, tick.index) - 1)
          if (seconds < 3600) return Math.round(seconds / 60) + "m"
          return Math.round(seconds / 3600) + "h"
        }
      }
    }
  }

  // A mark per window at its depth.
  Repeater {
    model: gauge.marks

    delegate: Rectangle {
      id: mark

      required property var modelData

      x: gauge.marksX + modelData.column * gauge.markStep
      y: modelData.y - height / 2
      width: gauge.markSize
      height: gauge.markSize
      radius: width / 2
      visible: !modelData.hidden
      color: "transparent"
      border.width: Math.max(1, gauge.unit)
      border.color: gauge.theme.textFaint

      Text {
        anchors.left: parent.right
        anchors.leftMargin: 2 * gauge.unit
        anchors.verticalCenter: parent.verticalCenter
        visible: mark.modelData.more > 0
        color: gauge.theme.textFaint
        font.family: Style.font.family
        font.pixelSize: 9 * gauge.textUnit
        textFormat: Text.PlainText
        text: "+" + mark.modelData.more
      }
    }
  }

  // The sounding lead: hangs at the selection's depth.
  Rectangle {
    id: lead

    x: gauge.lineX - width / 2
    y: Math.max(gauge.lineTop, Math.min(gauge.lineBottom,
      Layout.soundingY(gauge.leadDepth, gauge.lineTop, gauge.lineBottom, gauge.maxDepth))) - height / 2
    width: 5 * gauge.unit
    height: 5 * gauge.unit
    radius: width / 2
    color: gauge.theme.accent
  }
}
