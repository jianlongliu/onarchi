// An application icon, or a lettered tile in a color derived from the app's
// name when the icon theme has nothing for it.
//
// Ported from Fathom (AppIcon.qml) by Maarten Tolhuijs, MIT licensed.

import QtQuick

Item {
  id: icon

  property string source: ""
  property string name: ""
  property real size: 24

  readonly property bool loaded: image.status === Image.Ready
  readonly property bool missing: source.length === 0 || image.status === Image.Error




  function hue(text) {
    let hash = 0
    for (let i = 0; i < text.length; i++) hash = (hash * 31 + text.charCodeAt(i)) % 3600
    return hash / 3600
  }

  implicitWidth: size
  implicitHeight: size
  width: size
  height: size

  Image {
    id: image

    anchors.fill: parent
    source: icon.visible ? icon.source : ""
    // No sourceSize and no asynchronous: with both set, an `image://icon/` URL
    // never leaves the Loading state (measured against Quickshell 0.3.1), so
    // every app fell through to its lettered tile. The icons here are small
    // theme files; loading them synchronously costs nothing.
    mipmap: true
    fillMode: Image.PreserveAspectFit
    visible: icon.loaded
  }

  Rectangle {
    anchors.fill: parent
    visible: icon.missing
    radius: width * 0.26
    // The tile's colour comes from the name; an unnamed app still needs a
    // stable one, so the empty string hashes as itself.
    color: Qt.hsla(icon.hue(icon.name || ""), 0.32, 0.42, 1)

    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      // A "?" here would read as a failure; an unnamed app shows a dot instead.
      text: icon.name.length > 0 ? icon.name.charAt(0).toUpperCase() : "\u00b7"
      color: "#f4f4f4"
      font.pixelSize: Math.max(6, icon.size * 0.52)
      font.bold: true
    }
  }
}
