// Window ordering for the Alt-Tab field, built from niri's own IPC.
//
// niri is a better source than Hyprland here: every window carries a
// `focus_timestamp` from the compositor's monotonic clock, so there is no
// reason to track focus in the shell the way Fathom must on Hyprland. What
// this file does instead is turn those monotonic stamps into "seconds since
// focus" against a single sample taken when the field opens.
//
// All functions work on plain objects and never touch Quickshell, so the same
// file runs inside the shell and under node.

// depth = log2(1 + seconds / 30), clamped to [0, 8] -- Fathom's model, kept
// here in four lines rather than reached through a second file so this one
// loads unchanged in the shell and under node.
var TIME_UNIT_SECONDS = 30
var MAX_DEPTH = 8

function depthForSeconds(seconds) {
    var value = Number(seconds)
    if (isNaN(value) || !isFinite(value)) return MAX_DEPTH
    if (value <= 0) return 0
    return Math.max(0, Math.min(MAX_DEPTH, Math.log(1 + value / TIME_UNIT_SECONDS) / Math.LN2))
}

// Focus timestamps are monotonic, not wall clock: they count from boot. A
// stamp is meaningful only relative to another stamp, which is why the field
// carries its own `now` rather than reading Date.now().
function stampSeconds(stamp) {
    if (!stamp) return null
    var secs = Number(stamp.secs)
    var nanos = Number(stamp.nanos)
    if (!isFinite(secs)) return null
    return secs + (isFinite(nanos) ? nanos / 1e9 : 0)
}

// The newest stamp in a window list, used as "now" for every age.
function newestStamp(windows) {
    var best = null
    for (var i = 0; i < windows.length; i++) {
        var value = stampSeconds(windows[i] ? windows[i].focus_timestamp : null)
        if (value !== null && (best === null || value > best)) best = value
    }
    return best
}

// Turn `niri msg -j windows` into the ordered field, front (most recent) first.
// Candidates whose focus stamp is missing sit at the far end: nothing is known
// about when they were used.
function buildField(windows, now, focusedId) {
    var list = windows || []
    var entries = []
    var focused = String(focusedId === undefined || focusedId === null ? "" : focusedId)

    for (var i = 0; i < list.length; i++) {
        var window = list[i]
        if (!window) continue
        var address = String(window.id)
        var at = stampSeconds(window.focus_timestamp)
        var active = address === focused
        // The focused window is zero seconds away even if its stamp was
        // debounced away by niri's own MRU bookkeeping.
        var seconds = active ? 0 : (at === null || now === null ? Infinity : Math.max(0, now - at))

        var appId = String(window.app_id || "")
        entries.push({
            address: address,
            id: window.id,
            title: String(window.title || ""),
            appId: appId,
            // The label under an icon, and the icon itself (a themed name or a
            // file URL), filled by the controller once it has looked the app up.
            appName: appId,
            icon: "",
            workspaceId: window.workspace_id,
            active: active,
            urgent: !!window.is_urgent,
            floating: !!window.is_floating,
            seconds: seconds,
            depth: depthForSeconds(seconds)
        })
    }

    // The focused window is always in front; the window that just lost focus
    // is also zero seconds away, so seconds alone cannot order the two. niri's
    // raw list is already newest-first, and a stable tie-break preserves that.
    entries.sort(function(a, b) {
        if (a.active !== b.active) return a.active ? -1 : 1
        if (a.seconds !== b.seconds) return a.seconds < b.seconds ? -1 : 1
        return 0
    })

    for (var j = 0; j < entries.length; j++) entries[j].index = j
    return entries
}

// Opening with a step of one lands on the window used before the focused one.
function initialSelection(count, step) {
    if (count <= 0) return -1
    if (step > 0) return count > 1 ? 1 : 0
    if (step < 0) return count - 1
    return 0
}

function stepSelection(index, delta, count) {
    if (count <= 0) return -1
    var current = Math.max(0, Math.min(count - 1, Number(index) || 0))
    var next = (current + Math.round(Number(delta) || 0)) % count
    return next < 0 ? next + count : next
}

// ------------------------------------------------------------ workspaces

// Group the field's entries by workspace, for the map under the Deep. Each
// group carries the indices of its entries in recency order, so the map can
// highlight the same windows the Deep shows.
function workspaceGroups(entries) {
    var list = entries || []
    var byId = {}
    var groups = []
    for (var i = 0; i < list.length; i++) {
        var entry = list[i]
        if (!entry) continue
        var key = entry.workspaceId === null || entry.workspaceId === undefined
            ? "none" : String(entry.workspaceId)
        var group = byId[key]
        if (!group) {
            group = { id: entry.workspaceId, entries: [] }
            byId[key] = group
            groups.push(group)
        }
        group.entries.push(i)
    }
    // Workspaces are already numbered by niri; sort by that id so the map
    // reads left to right the way the bar does.
    groups.sort(function(a, b) {
        var ai = a.id === null || a.id === undefined ? Infinity : Number(a.id)
        var bi = b.id === null || b.id === undefined ? Infinity : Number(b.id)
        if (ai !== bi) return ai < bi ? -1 : 1
        return 0
    })
    return groups
}

// The shell imports this file as a QML library; the tests load it with node.
if (typeof module !== "undefined") {
  module.exports = {
    buildField: buildField,
    newestStamp: newestStamp,
    stampSeconds: stampSeconds,
    initialSelection: initialSelection,
    stepSelection: stepSelection,
    depthForSeconds: depthForSeconds,
    workspaceGroups: workspaceGroups,
    MAX_DEPTH: MAX_DEPTH
  }
}
