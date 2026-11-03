import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Layout.js" as Layout
import "Recency.js" as Recency

// A depth-based Alt-Tab for niri, after Fathom by Maarten Tolhuijs (MIT).
//
// Windows are placed on a z-axis by how long ago they had focus. The most
// recent sits at the camera; older ones recede up and to the right, shrinking
// and thickening with fog. Tab dives, Enter commits, Escape cancels.
//
// Two departures from Fathom, both forced by what niri exposes, and both worth
// knowing before judging the result:
//
//   * No window previews. Fathom draws each card from a live capture. niri
//     implements wlr-screencopy (the whole output) but not
//     hyprland-toplevel-export (one window), and its IPC reports no on-screen
//     position for tiled windows: `tile_pos_in_workspace_view` is filled for
//     floating windows only (niri's scrolling.rs publishes None for tiles). So
//     a window's rectangle on the screen cannot be derived, and cropping one
//     out of an output capture is not possible. Cards carry the app and title
//     instead.
//   * No "release Alt to commit". A modifier released while a surface held the
//     keyboard before it grabbed never reaches that surface (measured against
//     niri 26.04: the press is delivered, the release is not). Enter commits.
//
// The overlay never moves, resizes or closes a window. Focusing the selection
// is the only thing it asks the compositor to do.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  property bool opened: false
  property var field: []
  property int selectedIndex: -1
  // Monotonic "now" sampled from the window list, never Date.now(): niri's
  // focus stamps count from boot.
  property real fieldNow: 0
  // The step the opening chord asked for, held until the window list lands.
  // `undefined` means no pending landing.
  property var openStep: undefined

  readonly property int count: field.length
  readonly property var selection: selectedIndex >= 0 && selectedIndex < count ? field[selectedIndex] : null

  // ------------------------------------------------------------ palette

  // The menu surface tokens are followed, but both are forced opaque here.
  // They are tuned for a menu card over a desktop that stays legible: this
  // install sets `background-alpha = 0.38` and `scrim-alpha = 0` (see
  // ~/.config/omarchy/shell.toml), which is right for the menu and wrong for a
  // switcher, where a translucent card would show the windows it is covering
  // and no scrim would leave the desktop competing with the field.
  readonly property color background: Color.background
  readonly property color foreground: Color.menu.text
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent
  readonly property color scrim: Util.alpha(Color.background, 0.86)
  readonly property int cornerRadius: Style.cornerRadius

  // ------------------------------------------------------------ geometry

  // Card boxes follow Fathom's layout: a stack stepping up and to the right,
  // the camera sitting on the selection.
  readonly property var stage: Layout.deepStage(panel.width, panel.height,
    Style.gapsOut + Style.space(24), Style.gapsOut + Style.space(96), 1.6, 0)

  function planeFor(index) {
    return Layout.deepPlane(stage, index - selectedIndex)
  }

  // ------------------------------------------------------------ data

  function reload() {
    if (!windowsProcess.running) windowsProcess.running = true
  }

  function applyWindows(text) {
    var windows = []
    try {
      windows = JSON.parse(text)
    } catch (e) {
      windows = []
    }
    var focused = ""
    for (var i = 0; i < windows.length; i++) {
      if (windows[i] && windows[i].is_focused) {
        focused = String(windows[i].id)
        break
      }
    }
    root.fieldNow = Recency.newestStamp(windows)
    root.field = Recency.buildField(windows, root.fieldNow, focused)
    if (!root.opened) {
      root.selectedIndex = -1
      return
    }
    // The window list arrives after the field opens, so the selection a chord
    // asked for is applied here rather than at open(): `openStep` says where
    // to land once the windows are known. `undefined` means "keep whatever the
    // user has already tabbed to".
    if (root.openStep !== undefined) {
      var wanted = root.openStep
      root.openStep = undefined
      root.selectedIndex = wanted === 0
        ? (root.count > 0 ? 0 : -1)
        : Recency.initialSelection(root.count, wanted)
      if (root.selectedIndex < 0 && root.count > 0) root.selectedIndex = 0
      return
    }
    if (root.selectedIndex >= root.count)
      root.selectedIndex = root.count > 0 ? root.count - 1 : -1
  }

  // A compact age, in the same spirit as Fathom's caption.
  function ageLabel(seconds) {
    if (!isFinite(seconds)) return "earlier"
    if (seconds < 60) return Math.max(0, Math.round(seconds)) + "s"
    if (seconds < 3600) return Math.round(seconds / 60) + "m"
    return Math.round(seconds / 3600) + "h"
  }

  // ------------------------------------------------------------ lifecycle

  function open() {
    root.openAt(0)
  }

  // Where the camera should start once the window list arrives: 0 for the
  // focused window, +1 for the previously used one, -1 for the oldest.
  function openAt(step) {
    if (root.opened) return
    root.opened = true
    root.openStep = step
    reload()
  }

  function close() {
    root.opened = false
    root.openStep = undefined
    root.selectedIndex = -1
  }

  // Opening on the previously used window rather than the focused one, which
  // is what a quick Alt+Tab should mean.
  function openOnPrevious() {
    if (!root.opened) {
      root.openAt(1)
      return
    }
    root.step(1)
  }

  function step(delta) {
    if (!root.opened || root.count === 0) return
    root.selectedIndex = Recency.stepSelection(root.selectedIndex, delta, root.count)
  }

  function commit() {
    var target = root.selection
    root.close()
    if (!target) return
    Quickshell.execDetached(["niri", "msg", "action", "focus-window", "--id", String(target.id)])
  }

  function cancel() {
    root.close()
  }

  // ------------------------------------------------------------ IPC

  IpcHandler {
    target: "omarchy.fathom"

    function open(): string {
      root.open()
      return root.opened ? "ok" : "failed"
    }

    function next(): string {
      root.openOnPrevious()
      return root.opened ? String(root.selectedIndex) : "empty"
    }

    function previous(): string {
      if (!root.opened) {
        root.openAt(-1)
        return "opening"
      }
      root.step(-1)
      return String(root.selectedIndex)
    }

    function commit(): string {
      root.commit()
      return "ok"
    }

    function cancel(): string {
      root.cancel()
      return "ok"
    }

    function state(): string {
      return JSON.stringify({
        opened: root.opened,
        windows: root.count,
        selected: root.selectedIndex,
        screen: panel.targetScreen ? String(panel.targetScreen.name || "") : "",
        // OverlayWindow keeps its content invisible until the surface has the
        // output's exact geometry and scale, so these two say whether anything
        // is actually on screen.
        contentReady: panel.contentReady,
        contentRevealed: panel.contentRevealed,
        size: panel.width + "x" + panel.height,
        screenSize: panel.targetScreen ? panel.targetScreen.width + "x" + panel.targetScreen.height : "",
        dpr: panel.devicePixelRatio,
        colors: {
          background: String(root.background),
          scrim: String(root.scrim),
          foreground: String(root.foreground),
          accent: String(root.accent)
        }
      })
    }

    function field(): string {
      var rows = []
      for (var i = 0; i < root.count; i++) {
        var e = root.field[i]
        var p = root.planeFor(i)
        rows.push({
          index: i,
          id: e.id,
          app: e.appId,
          title: e.title,
          active: e.active,
          seconds: isFinite(e.seconds) ? Math.round(e.seconds * 10) / 10 : null,
          depth: Math.round(e.depth * 1000) / 1000,
          plane: {
            x: Math.round(p.x), y: Math.round(p.y),
            w: Math.round(p.width), h: Math.round(p.height),
            scale: Math.round(p.scale * 100) / 100,
            opacity: Math.round(p.opacity * 100) / 100
          }
        })
      }
      return JSON.stringify(rows)
    }
  }

  // ------------------------------------------------------------ processes

  Process {
    id: windowsProcess
    command: ["niri", "msg", "-j", "windows"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyWindows(text)
    }
  }

  // ------------------------------------------------------------ the field

  OverlayWindow {
    id: panel
    shown: root.opened
    WlrLayershell.namespace: "omarchy-fathom"

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.cancel()
    }

    Repeater {
      model: root.count

      delegate: Item {
        id: card
        required property int index

        readonly property var entry: root.field[index] || null
        readonly property var plane: root.planeFor(index)
        readonly property bool selected: index === root.selectedIndex
        readonly property real scale: Math.max(0.05, plane.scale)

        x: plane.x - plane.width / 2
        y: plane.y - plane.height / 2
        width: Math.max(1, plane.width)
        height: Math.max(1, plane.height)
        z: plane.z
        opacity: plane.opacity

        Rectangle {
          anchors.fill: parent
          radius: root.cornerRadius * card.scale
          color: root.background
          border.width: card.selected ? Math.max(2, 2 * card.scale) : Math.max(1, card.scale)
          border.color: card.selected ? root.accent
            : (card.entry && card.entry.urgent ? root.urgent : root.foreground)
          clip: true

          // The app's name, which is all a card can show without a capture.
          Text {
            anchors {
              left: parent.left
              right: parent.right
              top: parent.top
              bottom: caption.top
              margins: Math.max(4, 10 * card.scale)
            }
            text: card.entry ? String(card.entry.appId || "") : ""
            color: root.foreground
            opacity: card.selected ? 0.95 : 0.7
            font.family: Style.font.menuFamily
            font.pixelSize: Math.max(7, Math.min(card.height * 0.2, Style.font.baseSize * 1.4 * card.scale))
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
          }

          // The caption strip: title and age. The tinted band is a sibling of
          // the text, never its parent: a parent's opacity multiplies into the
          // text, and at 0.10 the title would vanish with the band.
          Rectangle {
            id: captionBand
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: Math.max(12, Math.min(card.height * 0.26, Style.font.baseSize * 1.5 * card.scale))
            color: root.foreground
            opacity: 0.10
          }

          Text {
            id: captionTitle
            anchors {
              left: parent.left
              right: age.left
              top: captionBand.top
              bottom: captionBand.bottom
              leftMargin: Math.max(4, 8 * card.scale)
              rightMargin: 4
            }
            text: card.entry ? String(card.entry.title || card.entry.appId || "") : ""
            color: root.foreground
            font.family: Style.font.menuFamily
            font.pixelSize: Math.max(7, Math.min(captionBand.height * 0.66, Style.font.baseSize * card.scale))
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
          }

          Text {
            id: age
            anchors {
              right: parent.right
              top: captionBand.top
              bottom: captionBand.bottom
              rightMargin: Math.max(4, 8 * card.scale)
            }
            visible: card.entry && isFinite(card.entry.seconds)
            text: card.entry ? root.ageLabel(card.entry.seconds) : ""
            color: root.foreground
            opacity: 0.55
            font.family: Style.font.menuFamily
            font.pixelSize: Math.max(6, Math.min(captionBand.height * 0.6, Style.font.baseSize * 0.85 * card.scale))
            verticalAlignment: Text.AlignVCenter
          }
        }
      }
    }

    // A compact age, in the same spirit as Fathom's caption.
    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          root.cancel()
          event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.commit()
          event.accepted = true
        } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Down || event.key === Qt.Key_Right) {
          root.step(1)
          event.accepted = true
        } else if (event.key === Qt.Key_Backtab || event.key === Qt.Key_Up || event.key === Qt.Key_Left) {
          root.step(-1)
          event.accepted = true
        }
      }
    }

    onShownChanged: if (shown) Qt.callLater(keyCatcher.forceActiveFocus)
  }
}
