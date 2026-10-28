import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Ui

// Bar-left replacement for omarchy.menu's logo button: the same button, drawn
// as the Arch logo. The menu panel itself is untouched — omarchy.menu is
// keepLoaded, so it stays mounted with its button off the bar.
//
// Drawn with WidgetButton rather than BarIconButton: the latter centres a
// glyph through its own optical-bounds maths, which is built for icon fonts and
// puts this SVG against the top edge of the slot. A plain Item with the image
// centred in it is what the other first-party bar widgets do (see flux).
BarWidget {
  id: root
  moduleName: "jianlongliu.arch-logo"

  // iconCanvas, not iconSize: iconSize is the size a *glyph* is drawn at, where
  // the font's own ink already fills the box. The Arch mark's path leaves a
  // margin inside its 256x256 viewBox, so at the glyph size it read lighter
  // than every icon beside it -- 22 units of ink against the battery's 25, and
  // visibly small next to the tray. The canvas puts it level with its
  // neighbours; anything larger (tried 24) overshoots them.
  readonly property int markSize: Style.bar.iconCanvas

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    fixedWidth: root.vertical ? -1 : root.markSize + scaledHorizontalMargin * 2
    fixedHeight: root.vertical ? root.markSize + scaledVerticalPadding * 2 : -1
    tooltipText: "Omarchy menu"

    Item {
      id: mark
      anchors.centerIn: parent
      width: root.markSize
      height: root.markSize

      Image {
        id: logo
        anchors.fill: parent
        source: Qt.resolvedUrl("arch-logo.svg")
        sourceSize.width: Math.round(width * Screen.devicePixelRatio)
        sourceSize.height: Math.round(height * Screen.devicePixelRatio)
        fillMode: Image.PreserveAspectFit
        smooth: true
        // Hidden but layered so MultiEffect can sample it as a texture.
        // colorization multiplies by source luminance, so the SVG must be
        // pure white or the logo renders dimmer than its neighbours.
        visible: false
        layer.enabled: true
      }

      MultiEffect {
        anchors.fill: parent
        source: logo
        colorization: 1.0
        colorizationColor: button.foreground
      }
    }

    onPressed: function(btn) {
      if (!root.bar) return
      if (btn === Qt.RightButton) root.bar.run("xdg-terminal-exec")
      else root.bar.run("omarchy-shell shell toggle omarchy.menu '{\"menu\":\"root\"}'")
    }
  }
}
