pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// Niri-backed replacement for the pieces of Quickshell's `Hyprland` module that
// Omarchy's bar, dock and panels read. The upstream shell is written against
// Hyprland's API; this singleton answers the same shapes from niri's IPC so the
// translate step stays a rename rather than a rewrite.
//
// Covered surface:
//   workspaces / focusedWorkspace / focusedMonitor / monitors
//   monitorFor(screen)
//   toplevels
//   refreshMonitors() / refreshWorkspaces() / refreshToplevels() / refresh()
//   dispatch(expression)  -- accepts both the Lua form (`hl.dsp.…`,
//                            `o.workspaces.…`) and Hyprland's legacy spelling
//   overviewOpen          -- the flag BlurWallpaper.qml gates its layer on
//
// State comes from niri's IPC event stream (`niri msg -j event-stream`) rather
// than the 500 ms polling this used to do. The stream replays the full workspace
// and window lists on connect and then pushes every change, so:
//   * the overview's blurred wallpaper appears with the overview instead of up to
//     half a second later (that delay was the poll interval),
//   * the bar's workspace pills react immediately,
//   * the shell stops spawning ~6 `niri msg` processes per second while idle.
//
// Events carrying partial data (WorkspaceActivated, WindowOpenedOrChanged, ...)
// only trigger a fresh one-shot query of the relevant list, debounced so a burst
// of events costs one spawn instead of one per event.
QtObject {
    id: root

    property var workspaces: ({ values: [] })
    property var focusedWorkspace: null
    property var focusedMonitor: null
    // Every output, in Hyprland's monitor shape ({name, activeWorkspace, …}).
    property var monitors: ({ values: [] })
    // Every window, in Hyprland's toplevel shape ({address, title, workspace, …}).
    property var toplevels: ({ values: [] })
    property bool overviewOpen: false

    property string _focusedOutput: ""
    property var _winCountById: ({})
    property var _winByWorkspace: ({})
    property var _monitorNames: []
    property var _activeWorkspaceByOutput: ({})
    property var _monitorModes: ({})

    // Re-read both lists from scratch. Used on startup and by the event handlers.
    function refresh() {
        if (!wsProcess.running) wsProcess.running = true
        if (!winProcess.running) winProcess.running = true
        if (!outputProcess.running) outputProcess.running = true
    }

    // Hyprland's own refresh hooks, so call sites port by renaming only.
    function refreshMonitors() {
        if (!outputProcess.running) outputProcess.running = true
    }
    function refreshWorkspaces() {
        if (!wsProcess.running) wsProcess.running = true
    }
    function refreshToplevels() {
        if (!winProcess.running) winProcess.running = true
    }

    // The monitor a given screen shows. Workspaces.qml asks for this once per
    // bar; there is one monitor per output on niri, so the name is the key.
    function monitorFor(screen) {
        var name = screen ? String(screen.name || "") : ""
        var list = root.monitors && root.monitors.values ? root.monitors.values : []
        for (var i = 0; i < list.length; i++) {
            if (list[i].name === name) return list[i]
        }
        return root.focusedMonitor
    }

    // A dispatcher call, in whichever spelling the caller used. The Lua forms
    // are rewritten to `hyprctl dispatch …` payloads for the PATH shim, which
    // already knows how to turn those into `niri msg action …`; the legacy
    // spelling passes straight through.
    function dispatch(expression) {
        var payload = String(expression || "").trim()
        if (payload === "") return

        // o.workspaces.focus(<slot>, "<output>") — Hyprland's per-monitor
        // workspace blocks. niri numbers workspaces globally, so the slot has to
        // be resolved against this output's own active workspace first.
        var m = payload.match(/^o\.workspaces\.focus\(\s*(\d+)\s*(?:,\s*"([^"]*)")?\s*\)$/)
        if (m) {
            var slot = parseInt(m[1], 10)
            var name = m[2] || ""
            var target = root._workspaceIdForSlot(name, slot)
            if (target > 0) Util.execDetached(["niri", "msg", "action", "focus-workspace", String(target)])
            return
        }

        Util.execDetached(["hyprctl", "dispatch", payload])
    }

    // niri numbers workspaces per output but globally unique, so a Hyprland-style
    // (monitor, slot) pair maps onto the workspace list by output and position.
    function _workspaceIdForSlot(name, slot) {
        var list = root.workspaces && root.workspaces.values ? root.workspaces.values : []
        var own = []
        for (var i = 0; i < list.length; i++) {
            if (name === "" || list[i].output === name) own.push(list[i])
        }
        own.sort(function(left, right) { return left.id - right.id })
        if (own.length === 0) return -1
        if (slot >= 1 && slot <= own.length) return own[slot - 1].id
        return -1
    }

    function countArray(n) {
        var a = []
        for (var i = 0; i < n; i++) a.push({})
        return a
    }

    function applyWorkspaces(text) {
        var arr = []
        var fw = null
        var byOutput = {}
        try {
            var data = JSON.parse(text)
            for (var i = 0; i < data.length; i++) {
                var w = data[i]
                var item = {
                    "niriId": w.id,
                    "id": w.idx !== undefined ? w.idx : w.id,
                    "name": w.name || "",
                    "output": w.output || "",
                    "active": !!w.is_active,
                    "focused": !!w.is_focused,
                    "toplevels": { values: [] }
                }
                arr.push(item)
                if (w.is_focused) {
                    fw = item
                    root._focusedOutput = w.output || ""
                }
                // The workspace each output is showing, which is what Hyprland's
                // monitor.activeWorkspace carries.
                if (w.is_active && w.output) byOutput[w.output] = item
            }
        } catch (e) {
            // ignore malformed/empty output
        }
        root._activeWorkspaceByOutput = byOutput
        root.workspaces = { values: arr }
        root.focusedWorkspace = fw
        root.applyOccupancy(root._winCountById)
        root._rebuildMonitors()
    }

    function applyWindows(text) {
        var byId = {}
        var byWorkspace = {}
        var list = []
        try {
            var wins = JSON.parse(text)
            for (var i = 0; i < wins.length; i++) {
                var wid = wins[i].workspace_id
                byId[wid] = (byId[wid] || 0) + 1
                if (!byWorkspace[wid]) byWorkspace[wid] = []
                byWorkspace[wid].push(wins[i])
                list.push({
                    "address": String(wins[i].id),
                    "title": wins[i].title || "",
                    "class": (wins[i].app_id || ""),
                    "workspace": { "id": wins[i].workspace_id },
                    "activated": !!wins[i].is_focused
                })
            }
        } catch (e) {}
        root._winCountById = byId
        root._winByWorkspace = byWorkspace
        root.toplevels = { values: list }
        root.applyOccupancy(byId)
    }

    // Outputs only matter for the name and which workspace each is showing, so
    // this stays a one-shot query rather than another event-stream listener.
    function applyOutputs(text) {
        var names = []
        var modes = {}
        try {
            // `niri msg -j outputs` is keyed BY OUTPUT NAME, not an array the way
            // `workspaces` and `windows` are -- so this iterates the keys.
            var data = JSON.parse(text)
            for (var key in data) {
                var out = data[key]
                var name = String(out.name || key)
                names.push(name)
                // niri reports the current mode as an index into `modes`, and the
                // scale under `logical`; Hyprland's lastIpcObject carries the same
                // facts flattened, which is the shape callers read.
                var modesList = out.modes || []
                var idx = out.current_mode
                var cur = (typeof idx === "number" && modesList[idx]) ? modesList[idx] : null
                var logical = out.logical || {}
                modes[name] = {
                    "width": cur ? cur.width : 0,
                    "height": cur ? cur.height : 0,
                    "refresh": cur ? cur.refresh_rate : 0,
                    "scale": logical.scale !== undefined ? logical.scale : 1,
                    "transform": 0
                }
            }
        } catch (e) {}
        root._monitorNames = names
        root._monitorModes = modes
        root._rebuildMonitors()
    }

    // Hyprland's monitor shape, assembled from the output list and the workspace
    // each output shows. Kept in one place so focusedMonitor, monitors and
    // monitorFor(screen) can never disagree.
    function _rebuildMonitors() {
        var names = root._monitorNames.slice()
        var byOutput = root._activeWorkspaceByOutput
        // An output that has not reported yet still needs an entry, or the bar
        // for that screen would have no monitor to render against.
        for (var output in byOutput) {
            if (names.indexOf(output) === -1) names.push(output)
        }
        var list = []
        for (var i = 0; i < names.length; i++) {
            var name = names[i]
            var mode = root._monitorModes[name] || null
            list.push({
                "name": name,
                // Hyprland's monitor shape: the physical size lives here, and
                // lastIpcObject carries the transform Bar.qml asks for.
                "width": mode ? mode.width : 0,
                "height": mode ? mode.height : 0,
                "scale": mode && mode.scale !== undefined ? mode.scale : 1,
                "lastIpcObject": mode,
                "activeWorkspace": byOutput[name] || null,
                "focused": name === root._focusedOutput
            })
        }
        root.monitors = { values: list }
        var focused = null
        for (var j = 0; j < list.length; j++) {
            if (list[j].focused) {
                focused = list[j]
                break
            }
        }
        root.focusedMonitor = focused
    }

    function applyOccupancy(byId) {
        var ws = root.workspaces && root.workspaces.values ? root.workspaces.values : []
        var out = []
        for (var i = 0; i < ws.length; i++) {
            var w = ws[i]
            var copy = {
                "niriId": w.niriId,
                "id": w.id,
                "name": w.name,
                "output": w.output,
                "active": w.active,
                "focused": w.focused,
                "toplevels": { values: root.countArray(byId[w.niriId] || 0) }
            }
            out.push(copy)
        }
        root.workspaces = { values: out }
    }

    // One line of the event stream (a JSON object with a single key).
    function handleEvent(line) {
        var msg = null
        try {
            msg = JSON.parse(line)
        } catch (e) {
            return
        }
        if (!msg) return

        if (msg.OverviewOpenedOrClosed) {
            root.overviewOpen = !!msg.OverviewOpenedOrClosed.is_open
            return
        }
        if (msg.WorkspacesChanged || msg.WorkspaceActivated || msg.WorkspaceUrgencyChanged
                || msg.WorkspacesReordered)
            wsDebounce.restart()
        if (msg.WindowsChanged || msg.WindowOpenedOrChanged || msg.WindowClosed
                || msg.WorkspaceActivated)
            winDebounce.restart()
    }

    property Process wsProcess: Process {
        id: wsProcess
        command: ["niri", "msg", "-j", "workspaces"]
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.applyWorkspaces(text)
        }
        stderr: StdioCollector {}
    }

    property Process winProcess: Process {
        id: winProcess
        command: ["niri", "msg", "-j", "windows"]
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.applyWindows(text)
        }
        stderr: StdioCollector {}
    }

    // Outputs change rarely (monitor plugged, mode switch), so this is queried on
    // the same refresh cycle as the other two rather than watched.
    property Process outputProcess: Process {
        id: outputProcess
        command: ["niri", "msg", "-j", "outputs"]
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.applyOutputs(text)
        }
        stderr: StdioCollector {}
    }

    // Coalesce event bursts (a workspace switch emits several events) into one query.
    property Timer wsDebounce: Timer {
        interval: 40
        onTriggered: if (!wsProcess.running) wsProcess.running = true
    }

    property Timer winDebounce: Timer {
        interval: 40
        onTriggered: if (!winProcess.running) winProcess.running = true
    }

    property Process eventStream: Process {
        id: eventStream
        command: ["niri", "msg", "-j", "event-stream"]
        running: true
        stdout: SplitParser {
            onRead: line => root.handleEvent(line)
        }
        stderr: StdioCollector {}
        // niri gone (restart, crash): reconnect after a beat. The stream replays
        // the full state on connect, so no extra resync is needed.
        onExited: streamRetry.restart()
    }

    property Timer streamRetry: Timer {
        interval: 1000
        onTriggered: if (!eventStream.running) eventStream.running = true
    }

    Component.onCompleted: root.refresh()
}
