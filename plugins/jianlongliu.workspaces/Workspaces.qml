import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// GNOME-style workspace capsule: one solid dot per workspace, the focused one
// stretched into a short pill. No numbers, no border, no heavy background.
// Every state is a tier of barForeground alpha so it stays monochrome.
BarWidget {
  id: root
  moduleName: "jianlongliu.workspaces"

  function workspaceById(id) {
    var values = Niri.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }

    return null
  }

  // Dots are not a fixed 1..5 strip: show 1..N where N is one past the last
  // workspace that holds a window (or the focused one, so a jump to an empty
  // workspace never hides the capsule). Empty desktop = two dots: "1 + 1".
  function workspaceIds() {
    var values = Niri.workspaces.values
    var highest = 1

    for (var i = 0; i < values.length; i++) {
      var w = values[i]
      var id = w.id
      if (id <= 0 || id > 10) continue
      var occupied = w.toplevels && w.toplevels.values.length > 0
      if ((occupied || w.focused) && id > highest) highest = id
    }

    var ids = []
    var last = Math.min(highest + 1, 10)
    for (var n = 1; n <= last; n++) ids.push(n)
    return ids
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  // Geometry: small dots, the focused one stretched. Dots are sized off the
  // bar so they follow the font scale.
  readonly property real dot: Math.max(7, Math.round(root.barSize * 0.28))
  readonly property real expanded: root.vertical ? dot : dot * 2.6
  readonly property real spacing: root.vertical ? dot * 0.6 : dot * 0.5
  readonly property color base: root.bar ? root.bar.barForeground : Color.foreground

  implicitWidth: row.implicitWidth + Style.spaceReal(1.5)
  // Filling the bar height is what makes the bar centre the dots; a slot sized
  // to the dot itself sits top-aligned.
  implicitHeight: root.vertical ? row.implicitHeight : root.barSize

  Row {
    id: row
    spacing: root.spacing
    // Filling the bar height is what keeps the dots vertically centred.
    anchors.verticalCenter: parent.verticalCenter

    Repeater {
      model: root.workspaceIds()

      Rectangle {
        id: capsule
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        readonly property bool focused: Niri.focusedWorkspace !== null && Niri.focusedWorkspace.id === modelData
        property bool hovered: false

        // Alpha tiers: empty < occupied < focused, hover lights up either way.
        readonly property color col: focused
          ? Qt.alpha(root.base, hovered ? 1.0 : 0.9)
          : hovered
            ? Qt.alpha(root.base, 0.85)
            : occupied
              ? Qt.alpha(root.base, 0.62)
              : Qt.alpha(root.base, 0.15)

        implicitWidth: width
        implicitHeight: height
        width: focused ? root.expanded : root.dot
        height: root.dot
        radius: height / 2
        color: col

        Behavior on width {
          NumberAnimation {
            duration: 220
            easing.type: Easing.OutBack
            easing.overshoot: 1.2
          }
        }
        Behavior on color {
          ColorAnimation { duration: 160; easing.type: Easing.InOutCubic }
        }

        MouseArea {
          id: hoverArea
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.LeftButton
          cursorShape: Qt.ArrowCursor
          onEntered: capsule.hovered = true
          onExited: capsule.hovered = false
          onClicked: function(mouse) { root.focusWorkspace(modelData) }
        }
      }
    }
  }
}
