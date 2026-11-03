import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Wayland._BackgroundEffect
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
//   * The card frames are one-shot stills, not live streams. niri has no
//     per-window capture protocol, but `niri msg action screenshot-window
//     --id N` renders a single window off screen -- including windows on other
//     workspaces -- and writes it to a file. That call also replaces the
//     clipboard (niri sets the image as the selection), so the clipboard is
//     saved before the captures and put back afterwards.
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
  property var previews: ({})
  property bool previewsDone: false

  // Windows in the field. Kept as its own int rather than `field.length`: a JS
  // array assigned to a `property var` is wrapped by QML, and a binding on its
  // length stops updating (measured: the array holds 4 items while
  // `field.length` reads 0). Setting the count alongside the array keeps the
  // two in step.
  property int fieldCount: 0
  readonly property int count: fieldCount
  readonly property var selection: selectedIndex >= 0 && selectedIndex < count ? field[selectedIndex] : null

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
    // Nothing is captured here. Whatever the background warmer wrote is what
    // the cards show; a window it has not reached yet falls back to its icon
    // and app name, which is the whole of the opening cost.
    if (!root.opened) return
    root.previews = root.stillsFor(root.field)
    root.previewsDone = true
  }

  // Map each entry to its cached still. The stamp is the file's age in the
  // session, kept stable across openings so Qt keeps its decoded texture.
  function stillsFor(entries) {
    var out = ({})
    for (var i = 0; i < entries.length; i++) {
      var key = String(entries[i].id)
      out[key] = { stamp: root.captureStamp }
    }
    return out
  }

  // Bumped after each background batch; it is what makes Qt decode a rewritten
  // still again (see previewFor).
  property int captureStamp: 0

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

  // niri can render a single window off screen, so every card gets a still,
  // including windows on other workspaces. The command writes the image as
  // well as setting it as the clipboard selection; the clipboard is saved once
  // before the batch and restored once after it.
  // Quickshell env has XDG_RUNTIME_DIR but not UID, so derive the scratch
  // directory from it: a private place for stills that the session cleans up.
  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ""
  readonly property string captureDir: runtimeDir + "/omarchy-fathom"
  readonly property string clipboardFile: runtimeDir + "/omarchy-fathom-clip"

  // `screenshot-window` costs ~200 ms per window (offscreen render + PNG
  // encode), so the batch for a full field would take about a second -- far
  // too slow to run when the field opens. Instead every window is captured in
  // the background as focus moves, and opening the field only reads what is
  // already on disk. A still is named after its window id, so it survives the
  // field closing; Qt's per-batch cache busting is not needed because the mtime
  // changes when the file is rewritten (see previewFor).
  readonly property int previewLimit: 24

  // One shell captures the given windows, waits for each PNG to stop growing
  // (niri writes from a worker thread and returns first), and drops files for
  // windows that no longer exist.
  function captureBatch(ids) {
    var lines = ['d="' + root.captureDir + '"', 'mkdir -p "$d"']
    for (var j = 0; j < ids.length; j++) {
      lines.push('f="$d/' + ids[j] + '.png"')
      lines.push('niri msg action screenshot-window --id ' + ids[j]
        + ' -d true --path "$f" >/dev/null 2>&1')
      lines.push('prev=-1; for i in $(seq 60); do sz=$(stat -c %s "$f" 2>/dev/null || echo 0); '
        + 'if [ "$sz" != "0" ] && [ "$sz" = "$prev" ]; then break; fi; prev=$sz; sleep 0.03; done')
    }
    // Drop stills of windows that closed: their ids never come back.
    lines.push('for f in "$d"/*.png; do [ -e "$f" ] || continue; '
      + 'id=$(basename "$f" .png); case " ' + ids.join(" ") + ' " in *" $id "*) ;; *) rm -f "$f";; esac; done')
    lines.push("printf done")
    captureProcess.command = ["sh", "-c", lines.join("; ")]
    captureProcess.running = true
  }

  // A still's URL. The file's mtime is appended so Qt decodes the new frame
  // instead of reusing the previous one from its cache -- a local file URL has
  // no query part, and Qt would look for a file literally named "60.png?v=1",
  // so the stamp goes in a fragment, which Qt strips.
  function previewFor(id) {
    var entry = root.previews[String(id)]
    var stamp = entry && entry.stamp ? entry.stamp : 0
    return "file://" + root.captureDir + "/" + String(id) + ".png#" + stamp
  }

  function finishCaptures() {
    root.captureStamp++
    root.previews = root.stillsFor(root.field)
    root.previewsDone = true
  }

  // Warm the cache once at shell start, so the first Alt+Tab of a session is
  // already served from disk rather than showing icon-only cards.
  Component.onCompleted: recaptureTimer.restart()

  // ------------------------------------------------------------ lifecycle

  function open() {
    root.openAt(0)
  }

  function openAt(step) {
    if (root.opened) return
    root.opened = true
    root.openStep = step
    root.previewsDone = false
    reload()
    watchdog.restart()
    // The captures run once the window list is known (applyWindows).
    capturePrepare.running = true
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
        workspaces: root.groups.length,
        previewsDone: root.previewsDone,
        previews: Object.keys(root.previews).length,
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
          preview: root.previewFor(e.id),
          hasStill: !!root.previews[String(e.id)]
        })
      }
      return JSON.stringify(rows)
    }
  }

  // ------------------------------------------------------------ processes

  // The compositor's own event stream drives the background capture: a window
  // entering the MRU order, or gaining focus, is the moment its still is worth
  // refreshing. Debounced so a burst of focus changes costs one batch, and
  // skipped while the field is open, where the frames are already being shown.
  Process {
    id: eventsProcess
    command: ["niri", "msg", "-j", "event-stream"]
    running: true

    stdout: SplitParser {
      onRead: function(line) {
        var msg = null
        try {
          msg = JSON.parse(line)
        } catch (e) {
          return
        }
        if (!msg) return
        // WindowFocusChanged is the one that reorders the field; the others
        // mean a window appeared, closed, or moved.
        if (msg.WindowFocusChanged || msg.WindowsChanged || msg.WindowOpenedOrChanged
            || msg.WindowClosed || msg.WorkspaceActivated)
          recaptureTimer.restart()
      }
    }
  }

  // A quiet moment after the last focus change, so switching quickly through
  // several windows does not spawn a capture batch per step.
  Timer {
    id: recaptureTimer
    interval: 400
    onTriggered: {
      if (root.opened) return
      recaptureWindows.running = true
    }
  }

  // Fetch the window list without disturbing the field, then capture.
  Process {
    id: recaptureWindows
    command: ["niri", "msg", "-j", "windows"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var list = []
        try {
          list = JSON.parse(text)
        } catch (e) {
          list = []
        }
        var ids = []
        for (var i = 0; i < list.length && ids.length < root.previewLimit; i++) {
          if (list[i]) ids.push(String(list[i].id))
        }
        if (ids.length > 0) root.captureBatch(ids)
      }
    }
  }

  Process {
    id: windowsProcess
    command: ["niri", "msg", "-j", "windows"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyWindows(text)
    }
  }

  // Keep the clipboard for the duration of the batch: niri sets each captured
  // image as the selection, so without this a switch would cost the user
  // whatever they had copied.
  Process {
    id: capturePrepare
    command: ["sh", "-c",
      'wl-paste --no-newline 2>/dev/null | base64 -w0 > "' + root.clipboardFile + '" 2>/dev/null; printf ok']
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: captureProcess.running = true
    }
  }

  Process {
    id: captureProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.finishCaptures()
    }
  }

  Process {
    id: captureRestore
    command: ["sh", "-c",
      'f="' + root.clipboardFile + '"; '
        + '[ -s "$f" ] && base64 -d "$f" | wl-copy 2>/dev/null; rm -f "$f"; printf ok']
    stdout: StdioCollector { waitForEnd: true }
  }

  // ------------------------------------------------------------ the field

  OverlayWindow {
    id: panel
    shown: root.opened
    WlrLayershell.namespace: "omarchy-fathom"

    // Frost exactly the cards, never the full-screen scrim: a `blur true` on a
    // surface this size would fog the whole display (see effects.kdl). One
    // nested Region per card, since the protocol takes a region, not a list.
    // Frost the cards, never the full-screen scrim: `blur true` on a surface
    // this size would fog the whole display (see effects.kdl).
    //
    // A Region's child list is declarative only (a Repeater is rejected with
    // "expected PendingRegion"), so the cards cannot be collected into one
    // region dynamically. Instead each Card carries its own single-item
    // region, exposed as `blurItems`, and they are chained here by hand for
    // the fixed number of depths the Deep actually shows.
    BackgroundEffect.blurRegion: Region {
      Region { item: field.cardSurfaces.length > 0 ? field.cardSurfaces[0] : null }
      Region { item: field.cardSurfaces.length > 1 ? field.cardSurfaces[1] : null }
      Region { item: field.cardSurfaces.length > 2 ? field.cardSurfaces[2] : null }
      Region { item: field.cardSurfaces.length > 3 ? field.cardSurfaces[3] : null }
      Region { item: field.cardSurfaces.length > 4 ? field.cardSurfaces[4] : null }
    }

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
