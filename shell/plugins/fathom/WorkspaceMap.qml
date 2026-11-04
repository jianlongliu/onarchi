// The Surface: every workspace with its windows, in one row of cards. Card
// widths follow each workspace's minimap aspect and shrink together when the
// row would not fit.
//
// Ported from Fathom (WorkspaceMap.qml) by Maarten Tolhuijs, MIT licensed.
// niri reports no on-screen position for tiled windows, so a minimap can only
// place the ones it does know; the rest are listed as tiles in a row.

pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons // qmllint disable import

Item {
  id: map

  property var controller: null
  required property var theme
  required property var appearance
  property real unit: 1
  property real textUnit: unit

  readonly property var groups: controller ? controller.groups : []
  readonly property real gap: 10 * unit
  readonly property real headerSpace: 14 * unit + 20 * textUnit

  // One card per workspace, as wide as its share of the row allows.
  Row {
    id: row

    anchors.fill: parent
    spacing: map.gap

    Repeater {
      model: map.groups

      delegate: Rectangle {
        id: card

        required property var modelData

        width: Math.max(72 * map.unit,
          (map.width - map.gap * Math.max(0, map.groups.length - 1)) / Math.max(1, map.groups.length))
        height: map.height
        radius: map.appearance.cornerRadius
        color: map.theme.panel
        border.width: map.appearance.borderWidth
        border.color: card.highlighted ? map.theme.accent : map.theme.panelBorder

        readonly property bool highlighted: {
          const entry = map.controller ? map.controller.selectionAt() : null
          return entry !== null && modelData.entries.indexOf(map.controller.selectedIndex) !== -1
        }

        // The workspace's name, and how many windows it holds.
        Text {
          id: title

          anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 * map.unit }
          height: 20 * map.textUnit
          text: "workspace " + String(modelData.id === null ? "?" : modelData.id)
          color: card.highlighted ? map.theme.accent : map.theme.textSoft
          font.family: Style.font.family
          font.pixelSize: 11 * map.textUnit
          elide: Text.ElideRight
          textFormat: Text.PlainText
          verticalAlignment: Text.AlignVCenter
        }

        // A tile per window, in the order the Deep shows them.
        Flow {
          anchors {
            left: parent.left
            right: parent.right
            top: title.bottom
            bottom: parent.bottom
            margins: 8 * map.unit
          }
          spacing: 3 * map.unit

          Repeater {
            model: card.modelData.entries

            delegate: Rectangle {
              id: tile

              required property var modelData

              readonly property var entry: map.controller ? map.controller.field[modelData] : null
              readonly property bool isSelected: map.controller !== null && modelData === map.controller.selectedIndex

              width: Math.max(10 * map.unit, (parent.width - 3 * map.unit * 3) / 4)
              height: Math.max(8 * map.unit, width * 0.62)
              radius: Math.min(2 * map.unit, map.appearance.cornerRadius)
              color: tile.isSelected ? map.theme.accent : map.theme.key
              border.width: tile.entry && tile.entry.urgent ? Math.max(1, map.unit) : 0
              border.color: map.theme.urgent
              opacity: tile.entry && tile.entry.active ? 1 : 0.75
            }
          }
        }
      }
    }
  }
}
