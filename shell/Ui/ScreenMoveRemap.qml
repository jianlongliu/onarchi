import QtQuick
import Quickshell

// Hyprland leaves an already-mapped layer surface at its old global position
// when its monitor moves within the layout: undocking disables the internal
// panel, the external monitor shifts to x=0, and long-lived surfaces such as
// the bar and background keep rendering at the old offset — or entirely
// off-screen — until they are unmapped and remapped. Watch the screen's
// origin and pulse `remapping` when it moves; the owning window folds that
// into its `visible` binding so the compositor re-places the surface at the
// monitor's new origin.
Item {
  id: root

  required property var window
  readonly property var screen: window ? window.screen : null

  // Fold into the window's binding: visible: <shown> && !guard.remapping
  property bool remapping: false

  visible: false

  // A layout reshuffle can move the monitor more than once before it lands.
  // Let the positions settle before the single remap pulse.
  Timer {
    id: settleTimer
    interval: 200
    onTriggered: root.remapping = true
  }

  // Hold the surface unmapped for a beat so the compositor processes the
  // unmap before the remap instead of coalescing them into a no-op.
  Timer {
    interval: 50
    running: root.remapping
    onTriggered: root.remapping = false
  }

  Connections {
    target: root.screen
    // niri re-places layer surfaces itself, so the pulse is only needed under
    // Hyprland, where the bug above is real. Under niri it is not harmless: the
    // session's first output reconcile moves the origin, the background gets
    // unmapped for 250ms, and that is the "wallpaper, black with a cursor,
    // wallpaper again" flash on login. Measured on niri 26.04: eDP-1 moved
    // 0,0 -> 1,0 -> 0,0 with the pulse suppressed left the bar and background
    // correctly placed. NIRI_SOCKET is what niri exports into its sessions.
    function onXChanged() { if (!Quickshell.env("NIRI_SOCKET")) settleTimer.restart() }
    function onYChanged() { if (!Quickshell.env("NIRI_SOCKET")) settleTimer.restart() }
  }
}
