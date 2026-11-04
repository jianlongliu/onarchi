// The field's contents: the wallpaper and veil, the Deep (the selection in
// front, older windows receding behind it), the sounding line, the caption,
// the map of every workspace, and the key hints. Kept apart from the
// layer-shell window so the controller can drive it and tests can host it.
//
// Ported from Fathom (FieldView.qml) by Maarten Tolhuijs, MIT licensed. The
// layout is upstream's; what changed is where the data comes from and what a
// card can draw (see the note in Fathom.qml about previews).

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Commons // qmllint disable import
import "Layout.js" as Layout
import "Palette.js" as Palette

Item {
  id: view

  property var controller: null

  // Every color the field draws with, derived from the theme and derived
  // again when the theme changes.
  readonly property var theme: Palette.derive({
    foreground: Color.foreground,
    background: Color.background,
    accent: Color.accent,
    urgent: Color.urgent
  })

  readonly property Appearance appearance: Appearance {}

  // One unit is a pixel on a 1000 px tall screen; everything scales with it.
  readonly property real unit: Math.max(0.75, Math.min(1.6, height / 1000))
  readonly property real textUnit: unit * Math.max(0.85, Math.min(1.6, Number(Style.fontScale) || 1))
  readonly property real margin: Math.max(16, width * 0.022)
  readonly property var entry: controller ? controller.selection : null
  readonly property bool empty: controller !== null && controller.opened && controller.count === 0

  opacity: controller && controller.opened ? 1 : 0

  Behavior on opacity {
    enabled: view.controller !== null && view.controller.opened
    NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
  }

  function focusKeys() {
    keyCatcher.forceActiveFocus()
  }

  // ------------------------------------------------------------ backdrop

  Rectangle {
    anchors.fill: parent
    gradient: Gradient {
      GradientStop { position: 0.0; color: view.theme.veilTop }
      GradientStop { position: 0.55; color: view.theme.veilMiddle }
      GradientStop { position: 1.0; color: view.theme.veilBottom }
    }
  }

  // Light from the surface, fading as the selection goes deeper; the scene
  // dims with it. Diving into older windows feels like diving.
  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    height: parent.height * 0.45
    opacity: 1 - view.sceneDepth / 8
    gradient: Gradient {
      GradientStop { position: 0.0; color: view.theme.surfaceLight }
      GradientStop { position: 1.0; color: view.theme.surfaceLightEnd }
    }
  }

  Rectangle {
    anchors.fill: parent
    color: view.theme.depthShade
    opacity: view.sceneDepth * 0.035
    visible: opacity > 0.005
  }

  MouseArea {
    anchors.fill: parent
    onClicked: if (view.controller) view.controller.cancel()
  }

  // ------------------------------------------------------------ geometry

  readonly property real mapHeight: Math.max(96, Math.min(height * 0.2, 210 * unit))
  readonly property real captionHeight: 62 * unit
  readonly property real deepTop: margin + 44 * unit
  // The sounding line takes a column on the left when there is room.
  readonly property real gaugeWidth: width >= 1000 ? 112 * textUnit : 0
  readonly property var stage: Layout.deepStage(width, height, deepTop,
    mapHeight + captionHeight + margin + 30 * unit, width / Math.max(1, height), margin + gaugeWidth)

  readonly property real selectedDepth: entry ? Math.min(8, Math.max(0, entry.depth)) : 0
  property real sceneDepth: selectedDepth

  Behavior on sceneDepth {
    enabled: view.controller !== null
    NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
  }

  // ------------------------------------------------------------ the Deep

  Repeater {
    id: planes

    model: view.controller ? view.controller.field : []

    delegate: Card {
      required property int index

      controller: view.controller
      entryIndex: index
      theme: view.theme
      appearance: view.appearance
      stage: view.stage
      unit: view.unit
      textUnit: view.textUnit

      Component.onCompleted: view.cardSurfaces.push(this.surfaceItem)
      Component.onDestruction: {
        var at = view.cardSurfaces.indexOf(this.surfaceItem)
        if (at !== -1) view.cardSurfaces.splice(at, 1)
      }
    }
  }

  // The painted rectangle of every card on screen. The overlay asks the
  // compositor to frost exactly these, so the field is glass over the windows
  // behind it rather than a solid panel on top of them.
  property var cardSurfaces: []

  // ------------------------------------------------------------ sounding line

  SoundingLine {
    x: view.margin
    y: view.deepTop
    width: view.gaugeWidth
    height: Math.max(1, view.stage.frontY + view.stage.frontHeight / 2 - view.deepTop)
    visible: view.gaugeWidth > 0
    controller: view.controller
    theme: view.theme
    unit: view.unit
    textUnit: view.textUnit
    leadDepth: view.sceneDepth
  }

  // ------------------------------------------------------------ caption

  Item {
    id: caption

    x: view.stage.frontX - view.stage.frontWidth / 2
    y: view.height - view.margin - view.mapHeight - view.captionHeight - 14 * view.unit
    width: view.width - x - view.margin
    height: view.captionHeight
    visible: view.entry !== null

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: if (view.controller && view.controller.selection) view.controller.commit()
    }

    AppIcon {
      id: captionIcon

      anchors.verticalCenter: parent.verticalCenter
      size: 38 * view.unit
      source: view.entry ? view.entry.icon : ""
      name: view.entry ? view.entry.appName : ""
    }

    Column {
      anchors.left: captionIcon.right
      anchors.leftMargin: 14 * view.unit
      anchors.right: counter.left
      anchors.rightMargin: 20 * view.unit
      anchors.verticalCenter: parent.verticalCenter
      spacing: 3 * view.unit

      Text {
        width: parent.width
        elide: Text.ElideRight
        color: view.theme.text
        font.family: Style.font.family
        font.pixelSize: 20 * view.textUnit
        font.bold: true
        textFormat: Text.PlainText
        text: view.entry ? String(view.entry.title || view.entry.appName) : ""
      }

      Text {
        width: parent.width
        elide: Text.ElideRight
        color: view.theme.textSoft
        font.family: Style.font.family
        font.pixelSize: 13 * view.textUnit
        textFormat: Text.PlainText
        text: {
          const entry = view.entry
          if (!entry) return ""
          const parts = []
          if (entry.appName) parts.push(entry.appName)
          parts.push("workspace " + String(entry.workspaceId === null ? "?" : entry.workspaceId))
          parts.push(view.ageLabel(entry.seconds))
          const reading = view.fathomLabel(entry.depth)
          if (reading) parts.push(reading)
          if (entry.urgent) parts.push("wants attention")
          return parts.join("  ·  ")
        }
      }
    }

    Text {
      id: counter

      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      color: view.theme.textSoft
      font.family: Style.font.family
      font.pixelSize: 13 * view.textUnit
      textFormat: Text.PlainText
      text: view.controller && view.controller.selectedIndex >= 0
        ? (view.controller.selectedIndex + 1) + " / " + view.controller.count : ""
    }
  }

  function ageLabel(seconds) {
    if (!isFinite(seconds)) return "earlier"
    if (seconds < 60) return Math.max(0, Math.round(seconds)) + "s ago"
    if (seconds < 3600) return Math.round(seconds / 60) + "m ago"
    return Math.round(seconds / 3600) + "h ago"
  }

  // Fathom's reading of depth: a window d fathoms down lost focus
  // 30 * (2^d - 1) seconds ago.
  function fathomLabel(depth) {
    const value = Number(depth)
    if (!isFinite(value)) return ""
    if (value < 0.35) return "at the surface"
    const seconds = 30 * (Math.pow(2, value) - 1)
    const whole = Math.round(value * 10) / 10
    return whole + (whole === 1 ? " fathom" : " fathoms")
  }

  // ------------------------------------------------------------ summary

  Text {
    x: view.margin
    y: view.margin + 8 * view.unit
    visible: view.controller !== null && !view.empty
    color: view.theme.textSoft
    font.family: Style.font.family
    font.pixelSize: 13 * view.textUnit
    textFormat: Text.PlainText
    text: {
      const controller = view.controller
      if (!controller) return ""
      const windows = controller.count
      const workspaces = controller.groups.length
      return windows + (windows === 1 ? " window" : " windows") + "  ·  "
        + workspaces + (workspaces === 1 ? " workspace" : " workspaces")
    }
  }

  Text {
    anchors.centerIn: parent
    visible: view.empty
    color: view.theme.text
    font.family: Style.font.family
    font.pixelSize: 20 * view.textUnit
    textFormat: Text.PlainText
    text: "No windows"
  }

  // ------------------------------------------------------------ hints

  Row {
    id: hints

    anchors.right: parent.right
    anchors.rightMargin: view.margin
    y: view.height - view.margin - view.mapHeight - 20 * view.unit
    spacing: 16 * view.unit

    Repeater {
      model: [["Tab", "deeper"], ["↑↓", "dive"], ["Enter", "focus"], ["Esc", "close"]]

      delegate: Row {
        id: hint

        required property var modelData

        spacing: 5 * view.unit

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: Math.max(height, keyText.implicitWidth + 10 * view.unit)
          height: 18 * view.unit
          radius: Math.min(view.appearance.cornerRadius, height / 2)
          color: view.theme.key
          border.width: view.appearance.borderWidth
          border.color: view.theme.keyBorder

          Text {
            id: keyText

            anchors.centerIn: parent
            color: view.theme.textSoft
            font.family: Style.font.family
            font.pixelSize: 11 * view.textUnit
            textFormat: Text.PlainText
            text: hint.modelData[0]
          }
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          color: view.theme.textFaint
          font.family: Style.font.family
          font.pixelSize: 11 * view.textUnit
          textFormat: Text.PlainText
          text: hint.modelData[1]
        }
      }
    }
  }

  // ------------------------------------------------------------ the map

  WorkspaceMap {
    id: map

    x: view.margin
    width: view.width - view.margin * 2
    height: view.mapHeight
    y: view.height - view.margin - height
    controller: view.controller
    theme: view.theme
    appearance: view.appearance
    unit: view.unit
    textUnit: view.textUnit
  }

  // ------------------------------------------------------------ keys

  Item {
    id: keyCatcher

    anchors.fill: parent
    focus: true

    Keys.onPressed: event => {
      if (!view.controller) return
      view.controller.handleKey(event)
    }
  }
}
