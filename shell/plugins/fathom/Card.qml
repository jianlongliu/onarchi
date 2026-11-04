// One window in the Deep: a card placed by its slot relative to the camera
// (Layout.deepPlane), with its captured frame, an icon, a title and its age.
// Fog by how deep it sits fades the capture into the backdrop, not the
// header, so every card stays readable however far back it lies.
//
// Ported from Fathom (WindowPlane.qml) by Maarten Tolhuijs, MIT licensed.
// The capture comes from niri rather than from a per-window protocol: see the
// note in Fathom.qml.

import QtQuick
import qs.Commons // qmllint disable import
import "Layout.js" as Layout

Item {
  id: card

  property var controller: null
  required property int entryIndex
  required property var theme
  required property var appearance
  property var stage: null
  property real unit: 1
  property real textUnit: unit

  readonly property var entry: controller && entryIndex < controller.count
    ? controller.field[entryIndex] : null
  readonly property int slot: entryIndex
  readonly property real r: controller ? slot - controller.selectedIndex : 0
  readonly property bool selected: controller !== null && slot === controller.selectedIndex
  readonly property bool urgent: !!(entry && entry.urgent)
  readonly property var geometry: stage ? Layout.deepPlane(stage, r) : ({ x: 0, y: 0, width: 1, height: 1, scale: 0, opacity: 0, z: 0 })
  // Text, padding and corners follow the card through the same 260 ms its
  // geometry takes. Binding them straight to the plane's scale makes them jump
  // on the frame the card starts sliding, which reads as a glitch rather than
  // a move.
  property real animatedScale: Math.min(1, geometry.scale)

  Behavior on animatedScale { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
  readonly property real headerHeight: Math.max(18 * textUnit, Math.min(30 * textUnit, height * 0.1))
  readonly property real pad: Math.max(3, 8 * unit * animatedScale)
  readonly property real radius: appearance.cornerRadius * animatedScale
  readonly property real fog: entry
    ? theme.fogStrength * Math.min(0.7, Math.max(0, Math.min(1, r)) * (0.12 + 0.75 * Math.min(1, entry.depth / 8)) + 0.05 * Math.max(0, r - 1))
    : 0
  readonly property string titleText: entry ? String(entry.title || entry.appName || "") : ""
  // Whether the warmer has a still for this window, and where it lives. The
  // URL is built from the controller so the cache-busting stamp it carries is
  // the same one the field reports.
  readonly property bool hasPreview: controller !== null && entry !== null
    && !!controller.previews[String(entry.id)]
  readonly property string previewUrl: controller && entry ? controller.previewFor(entry.id) : ""

  x: geometry.x - geometry.width / 2
  y: geometry.y - geometry.height / 2
  width: Math.max(1, geometry.width)
  height: Math.max(1, geometry.height)
  z: geometry.z
  opacity: geometry.opacity

  // Moving the camera is an animation in Fathom: diving one window slides the
  // whole stack, it does not cut. z stays instant -- interpolating depth order
  // would let a card cross another mid-flight.
  Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
  Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
  Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
  Behavior on height { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
  Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

  // The painted card. FieldView reaches it through `surfaceItem` so the
  // overlay can ask niri to frost exactly these rectangles.
  readonly property alias surfaceItem: surface

  // How much of the card's own tint sits over the frost. The field is frosted
  // as a whole now (see Fathom.qml), so a card can be almost solid without
  // losing the glass: at 0.82 the header stays crisp and the blur still shows
  // around the edges.
  property real fillOpacity: 0.82

  Rectangle {
    id: surface

    anchors.fill: parent
    radius: card.radius
    // The fill is a glass tint, not an opaque panel: niri frosts the windows
    // behind the cards, and an opaque fill would hide that frost entirely.
    // Fathom's own cards are `opacity + blur` for the same reason.
    gradient: Gradient {
      GradientStop { position: 0.0; color: Util.alpha(card.selected ? card.theme.cardSelectedTop : card.theme.cardTop, card.fillOpacity) }
      GradientStop { position: 1.0; color: Util.alpha(card.selected ? card.theme.cardSelectedBottom : card.theme.cardBottom, card.fillOpacity) }
    }
    border.width: card.selected ? Math.max(1, card.appearance.borderWidth) * 2 : Math.max(1, card.appearance.borderWidth)
    border.color: card.selected ? card.theme.accent
      : (card.urgent ? card.theme.urgent : card.theme.cardBorder)
    clip: true

    // The window's frame, captured off screen by niri when the field opened.
    Image {
      id: frame

      anchors.fill: parent
      anchors.topMargin: card.headerHeight + card.pad
      anchors.bottomMargin: card.pad
      anchors.leftMargin: card.pad
      anchors.rightMargin: card.pad
      visible: card.hasPreview
      source: card.previewUrl
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      cache: false
      smooth: true
      opacity: 1 - card.fog * 0.6
      // niri writes the still at full window size (~3200 px wide). Asking Qt
      // for a card-sized decode keeps the cost per card small and stops the
      // decoder stalling the frame the field opens on.
      sourceSize.width: Math.max(64, Math.round(width))
      sourceSize.height: Math.max(64, Math.round(height))

      Rectangle {
        anchors.fill: parent
        visible: parent.status !== Image.Ready
        color: card.theme.bed
        radius: 2 * card.unit * card.animatedScale
      }
    }

    // No frame yet, or none possible: the app's name over its bed.
    Text {
      anchors.centerIn: frame
      visible: !card.hasPreview
      width: parent.width * 0.9
      text: card.entry ? String(card.entry.appName || card.entry.appId || "") : ""
      color: card.theme.textSoft
      font.family: Style.font.family
      font.pixelSize: Math.max(7, Math.min(height * 0.5, 14 * card.textUnit * card.animatedScale))
      elide: Text.ElideRight
      horizontalAlignment: Text.AlignHCenter
    }

    // Fog over the capture: older windows sink into the backdrop.
    Rectangle {
      anchors.fill: frame
      visible: card.hasPreview && card.fog > 0
      radius: 2
      color: card.theme.fog
      opacity: card.fog
    }

    // The header strip: app icon, title, age.
    Item {
      id: header

      anchors { left: parent.left; right: parent.right; top: parent.top }
      height: card.headerHeight

      AppIcon {
        id: appIcon

        anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: card.pad }
        size: Math.max(10, card.headerHeight * 0.62)
        source: card.entry ? card.entry.icon : ""
        name: card.entry ? card.entry.appName : ""
      }

      Text {
        anchors {
          left: appIcon.right
          leftMargin: card.pad
          right: ageText.left
          rightMargin: card.pad
          verticalCenter: parent.verticalCenter
        }
        text: card.titleText
        color: card.selected ? card.theme.text : card.theme.textSoft
        font.family: Style.font.family
        font.pixelSize: Math.max(7, Math.min(card.headerHeight * 0.52, 13 * card.textUnit * card.animatedScale))
        font.bold: card.selected
        elide: Text.ElideRight
        textFormat: Text.PlainText
      }

      Text {
        id: ageText

        anchors { right: parent.right; rightMargin: card.pad; verticalCenter: parent.verticalCenter }
        visible: card.entry !== null
        text: {
          const seconds = card.entry ? card.entry.seconds : Infinity
          if (!isFinite(seconds)) return "earlier"
          if (seconds < 60) return Math.round(seconds) + "s"
          if (seconds < 3600) return Math.round(seconds / 60) + "m"
          return Math.round(seconds / 3600) + "h"
        }
        color: card.theme.textFaint
        font.family: Style.font.family
        font.pixelSize: Math.max(6, Math.min(card.headerHeight * 0.44, 11 * card.textUnit * card.animatedScale))
        textFormat: Text.PlainText
      }
    }

    // A hairline under the header, so the strip reads as chrome.
    Rectangle {
      anchors { left: parent.left; right: parent.right; top: header.bottom }
      height: 1
      color: card.theme.frameEdge
    }
  }
}
