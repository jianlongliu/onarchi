import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Recency.js" as Recency

// A depth-based Alt-Tab for niri, after Fathom by Maarten Tolhuijs (MIT).
//
// Windows are placed on a z-axis by how long ago they had focus. The most
// recent sits at the camera; older ones recede up and to the right, shrinking
// and fading with age. A sounding line on the left reads their depth, and a
// map along the bottom shows every workspace. Tab dives, Enter commits,
// Escape cancels.
//
// Two departures from Fathom, both forced by what niri exposes:
//
//   * Cards carry no window frames. The only per-window capture niri offers is
//     `niri msg action screenshot-window`, which unconditionally replaces the
//     clipboard and raises a "Screenshot captured" notification per call --
//     on every focus change that made the field interrupt whatever the user
//     was doing. Capture is off until niri ships toplevel image-copy; cards
//     fall back to the app icon, title and age. See docs/fathom.md.
//   * No "release Alt to commit". A modifier released after a surface grabbed
//     the keyboard never reaches that surface, so Enter commits instead, and a
//     watchdog closes the field if it is abandoned.
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
  property var groups: []
  property int selectedIndex: -1
  // Monotonic "now" sampled from the window list, never Date.now(): niri's
  // focus stamps count from boot.
  property real fieldNow: 0
  // The step the opening chord asked for, held until the window list lands.
  property var openStep: undefined
  // id -> { url, status } for the captured frames, filled after opening.
  // The window that had focus last time the warmer ran. A focus change only
  // alters what those two windows show, so only they are captured again; every
  // other still is reused. Without this, committing a switch re-captured every
  // window on screen.
  property string lastFocusedId: ""


  // Windows in the field. Kept as its own int rather than `field.length`: a JS
  // array assigned to a `property var` is wrapped by QML, and a binding on its
  // length stops updating (measured: the array holds 4 items while
  // `field.length` reads 0). Setting the count alongside the array keeps the
  // two in step.
  property int fieldCount: 0
  readonly property int count: fieldCount
  // A function, not a binding. `field[selectedIndex]` inside a `property var`
  // binding is not re-evaluated when the array's contents change -- QML tracks
  // the `field` reference, not what is inside it -- so `selection` stayed at
  // whatever it evaluated to before the window list arrived (null, measured:
  // selected=1 with windows=4 while the property read null).
  // No `selection` property. Every attempt to expose `field[selectedIndex]`
  // through a property or a helper returned null while the same expression
  // written at the call site returned the entry (measured repeatedly). The
  // callers index the array directly instead.
  property int fieldVersion: 0

  // Everything inside a function body must be reached through `root.`:
  // an unqualified `field` in a method resolves to undefined here, so the
  // index check failed and every caller got null while the same expression
  // written at a call site returned the entry (measured against this shell).
  function selectionAt() {
    return root.selectedIndex >= 0 && root.selectedIndex < root.fieldCount
      ? root.field[root.selectedIndex] : null
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
    var built = root.decorate(Recency.buildField(windows, root.fieldNow, focused))
    // Assign the array itself. Re-using the same array object (or handing
    // QML a JS array it has already wrapped) makes `field.length` read back as
    // 0 while the original still has its items -- the field then draws nothing.
    root.field = built
    root.fieldCount = built.length
    root.fieldVersion++
    root.groups = Recency.workspaceGroups(root.field)

    if (!root.opened) {
      root.selectedIndex = -1
      return
    }
    if (root.openStep !== undefined) {
      var wanted = root.openStep
      root.openStep = undefined
      root.selectedIndex = wanted === 0
        ? (root.count > 0 ? 0 : -1)
        : Recency.initialSelection(root.count, wanted)
      if (root.selectedIndex < 0 && root.count > 0) root.selectedIndex = 0
    } else if (root.selectedIndex >= root.count) {
      root.selectedIndex = root.count > 0 ? root.count - 1 : -1
    }
  }

  // Icons and human names come from the desktop entry that matches the
  // window's app id, through Quickshell's own index: no process, no file I/O.
  property var iconCache: ({})

  function desktopEntryFor(appId) {
    var name = String(appId || "")
    if (!name) return null
    try {
      return DesktopEntries.heuristicLookup(name)
    } catch (e) {
      return null
    }
  }

  function appInfo(appId) {
    var key = String(appId || "")
    if (key in root.iconCache) return root.iconCache[key]
    var entry = root.desktopEntryFor(key)
    var icon = ""
    var names = [entry ? String(entry.icon || "") : "", key]
    for (var i = 0; i < names.length && !icon; i++) {
      if (!names[i]) continue
      if (names[i].charAt(0) === "/") icon = "file://" + names[i]
      else icon = String(Quickshell.iconPath(names[i], true) || "")
    }
    var info = { icon: icon, name: entry ? String(entry.name || key) : root.prettyAppId(key) }
    root.iconCache[key] = info
    return info
  }

  // "com.mitchellh.ghostty" reads better as "Ghostty" when no desktop entry
  // names it; the last segment capitalized is close enough.
  function prettyAppId(appId) {
    var text = String(appId || "")
    if (!text) return ""
    var last = text.split(".").pop()
    return last ? last.charAt(0).toUpperCase() + last.slice(1) : text
  }

  // Fill in the icon and the human name for every entry.
  function decorate(entries) {
    for (var i = 0; i < entries.length; i++) {
      var info = root.appInfo(entries[i].appId)
      entries[i].icon = info.icon
      entries[i].appName = info.name
    }
    return entries
  }

  // ------------------------------------------------------------ captures

  // ------------------------------------------------------------ lifecycle

  function open() {
    root.openAt(0)
  }

  function openAt(step) {
    if (root.opened) return
    root.opened = true
    root.openStep = step
    reload()
    watchdog.restart()
  }

  function close() {
    watchdog.stop()
    root.opened = false
    root.openStep = undefined
    root.selectedIndex = -1
  }

  // niri never delivers the Alt release to this surface, so an abandoned field
  // would keep the keyboard until Enter or Escape. Fifteen seconds without
  // input closes it, the same bound Fathom uses.
  Timer {
    id: watchdog
    interval: 15000
    onTriggered: root.cancel()
  }

  function touch() {
    if (root.opened) watchdog.restart()
  }

  function openOnPrevious() {
    if (!root.opened) {
      root.openAt(1)
      return
    }
    root.step(1)
  }

  function step(delta) {
    if (!root.opened || root.count === 0) return
    root.touch()
    root.selectedIndex = Recency.stepSelection(root.selectedIndex, delta, root.count)
  }

  function handleKey(event) {
    root.touch()
    if (event.key === Qt.Key_Escape) {
      root.cancel()
      return true
    }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.commit()
      return true
    }
    if (event.key === Qt.Key_Tab || event.key === Qt.Key_Down || event.key === Qt.Key_Right) {
      root.step(1)
      return true
    }
    if (event.key === Qt.Key_Backtab || event.key === Qt.Key_Up || event.key === Qt.Key_Left) {
      root.step(-1)
      return true
    }
    return false
  }

  function commit() {
    var target = root.selectionAt()
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
      var sel = root.selectionAt()
      return JSON.stringify({
        selName: sel ? String(sel.appName || "") : "null",
        selIcon: sel ? String(sel.icon || "") : "null",
        opened: root.opened,
        windows: root.count,
        selected: root.selectedIndex,
        workspaces: root.groups.length,
        screen: panel.targetScreen ? String(panel.targetScreen.name || "") : ""
      })
    }

    function field(): string {
      var rows = []
      for (var i = 0; i < root.count; i++) {
        var e = root.field[i]
        rows.push({
          index: i,
          id: e.id,
          app: e.appId,
          title: e.title,
          active: e.active,
          workspace: e.workspaceId,
          seconds: isFinite(e.seconds) ? Math.round(e.seconds * 10) / 10 : null,
          depth: Math.round(e.depth * 1000) / 1000,
          preview: "",
          hasStill: false
        })
      }
      return JSON.stringify(rows)
    }
  }

  // ------------------------------------------------------------ processes

  // Screenshot capture is removed. niri writes every still to the clipboard
  // and raises one "Screenshot captured" notification per window with no way
  // to opt out, and it fires on every focus change -- so a background warmer
  // kept interrupting the user while they worked. The cards show the app icon
  // and title instead; window frames wait for niri to expose toplevel
  // image-copy (see docs/fathom.md, "现状：暂停").

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

    // No client blur region. Asking for one (BackgroundEffect.blurRegion) made
    // the frost die a couple of seconds after opening -- measured: it survives
    // until the card stills finish decoding, then niri recomputes the region
    // and ends up with nothing. The rule in effects.kdl carries `blur true`, so
    // niri blurs the surface itself and no region has to stay in sync.
    FieldView {
      id: field

      anchors.fill: parent
      controller: root
    }

    onShownChanged: if (shown) Qt.callLater(fieldKeys.forceActiveFocus)

    Item {
      id: fieldKeys
      anchors.fill: parent
      focus: true

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (root.handleKey(event)) event.accepted = true
      }
    }
  }
}
