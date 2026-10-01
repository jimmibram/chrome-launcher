import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Ui

// Up to eight profiles are laid out around an empty centre: left, right, up and
// down first, and an arrow key opens its profile at once. The fifth to eighth
// take the corners, up-left, up-right, down-left, down-right, and open on their
// two arrow keys pressed together.
// Summoned by bin/chrome-launcher with { dir }, the script's private directory.
// dir/payload.json holds { profiles: [{ dir, name, email, picture }] }.
// The chosen profile's dir is written to dir/selection, then dir/done is created.
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property var profiles: []
  property int hoveredIndex: -1
  property int chosenIndex: -1  // the profile just picked (and already answered), shown with a bright edge
  property string dir: ""  // the waiting script's directory, empty once answered

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int tileSize: Style.space(180)
  property int tileSpacing: Style.spacing.md
  property int avatarSize: Style.space(88)
  property int keycapSize: Style.space(38)
  property int cornerKeycapSize: Style.space(26)
  // How long after one arrow a second one still counts as pressed together.
  property int chordWindow: 200

  function open(requestJson) {
    // Summoned again while already up: the script behind the first summon is
    // still waiting, so answer it (cancelled) before taking the new one.
    if (root.dir) root.release(null)
    var request = {}
    try { request = JSON.parse(requestJson || "{}") } catch (e) {}
    root.dir = String(request.dir || "")
    if (!root.dir) { root.finish(null); return }
    var path = root.dir + "/payload.json"
    if (payloadFile.path === path) payloadFile.reload()
    else payloadFile.path = path
  }

  function show(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) {}
    root.profiles = payload.profiles || []
    root.hoveredIndex = -1
    root.chosenIndex = -1
    root.pendingSlot = -1
    chordTimer.stop()
    root.opened = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  FileView {
    id: payloadFile
    printErrors: false
    onLoaded: root.show(text())
    onLoadFailed: root.finish(null)  // nothing to show, but don't leave the script waiting
  }

  function close() {
    // Hidden from outside (e.g. toggled away): still release the waiting script.
    if (root.opened) root.finish(null)
  }

  // Answer the waiting script: its chosen profile dir, or null for cancelled.
  function release(choice) {
    if (!root.dir) return
    // The files live in the script's private directory and never exist beforehand;
    // noclobber (set -C) makes bash refuse to write through anything that does,
    // symlinks included, instead of truncating it. Detached rather than a Process
    // so that two answers in quick succession can't lose the second one.
    var dir = Util.shellQuote(root.dir)
    Quickshell.execDetached(["bash", "-c", choice === null
      ? "set -C; : > " + dir + "/done"
      : "set -C; printf '%s\\n' " + Util.shellQuote(choice) + " > " + dir + "/selection && : > " + dir + "/done"])
    root.dir = ""
  }

  function finish(choice) {
    closeTimer.stop()
    chordTimer.stop()
    root.pendingSlot = -1
    root.chosenIndex = -1
    root.opened = false
    root.release(choice)
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "jimmibram.chrome-launcher")
  }

  // Slot order: left, right, up, down, then the corners up-left, up-right,
  // down-left, down-right (column, row in a 3x3 grid).
  readonly property var slots: [[0, 1], [2, 1], [1, 0], [1, 2], [0, 0], [2, 0], [0, 2], [2, 2]]
  readonly property int shown: Math.min(profiles.length, 8)
  // Rows only exist when there is a profile in them: up with 3+, down with 4+.
  readonly property bool hasUp: profiles.length > 2
  readonly property bool hasDown: profiles.length > 3
  readonly property int topRow: hasUp ? 0 : 1
  readonly property int step: tileSize + tileSpacing

  // The arrows that open a corner: its horizontal one (left or right) and its
  // vertical one (up or down), as slots.
  function cornerArrows(slot) {
    return [(slot - 4) % 2, 2 + Math.floor((slot - 4) / 2)]
  }

  // The corner two arrows open together, or -1 when they are on one axis.
  function corner(a, b) {
    var h = a < 2 ? a : b < 2 ? b : -1
    var v = a > 1 ? a : b > 1 ? b : -1
    return h < 0 || v < 0 ? -1 : 4 + (v - 2) * 2 + h
  }

  // An arrow key. With a corner profile reachable from it, the pick waits a
  // moment for the second arrow, so the two needn't land in the same instant.
  property int pendingSlot: -1
  function arrow(slot) {
    if (root.chosenIndex !== -1) return
    if (root.pendingSlot !== -1) {
      var c = root.corner(root.pendingSlot, slot)
      if (c >= 0 && c < root.shown) root.activate(c)
      return  // same axis, or no profile in that corner: the first arrow's pick stands
    }
    var waits = false
    for (var i = 4; i < root.shown; i++) {
      var arrows = root.cornerArrows(i)
      if (arrows[0] === slot || arrows[1] === slot) waits = true
    }
    if (!waits) { root.activate(slot); return }
    root.pendingSlot = slot
    chordTimer.restart()
  }

  Timer {
    id: chordTimer
    interval: root.chordWindow
    onTriggered: root.activate(root.pendingSlot)
  }

  // A key on the keyboard: a triangle pointing at its profile. Lights up when
  // hovered, gets a bright edge when chosen.
  component Keycap: Rectangle {
    id: keycap
    property bool lit: false
    property bool chosen: false
    property int arrowIndex: 0  // slot the triangle points at
    property int size: root.keycapSize

    width: size
    height: size
    radius: Style.space(8)
    color: lit ? root.selectedBackground : root.background
    border.width: chosen ? Math.max(2, Style.space(2)) : Math.max(1, Style.space(1))
    border.color: chosen ? root.selectedText : lit ? root.selectedBackground : root.border
    scale: lit ? 1.1 : 1

    Shape {
      id: triangle
      anchors.centerIn: parent
      width: parent.width * 0.42
      height: parent.height * 0.42
      rotation: [180, 0, 270, 90][keycap.arrowIndex]
      preferredRendererType: Shape.CurveRenderer

      ShapePath {
        strokeWidth: -1
        fillColor: keycap.lit ? root.selectedText : root.foreground
        joinStyle: ShapePath.RoundJoin
        startX: 0; startY: 0
        PathLine { x: triangle.width; y: triangle.height / 2 }
        PathLine { x: 0; y: triangle.height }
        PathLine { x: 0; y: 0 }
      }
    }
  }

  function activate(index) {
    chordTimer.stop()
    root.pendingSlot = -1
    if (index < 0 || index >= root.shown || root.chosenIndex !== -1) return
    // Outline the choice and answer the script at once, so the browser starts
    // right away; the picker itself stays on screen for a beat before closing.
    root.chosenIndex = index
    root.release(root.profiles[index].dir)
    closeTimer.start()
  }

  Timer {
    id: closeTimer
    interval: 320
    onTriggered: root.finish(null)  // already answered: this only hides
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "jimmibram-chrome-launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: if (root.chosenIndex === -1) root.finish(null)
    }

    BorderSurface {
      id: card
      anchors.centerIn: parent
      width: tiles.width + root.contentMargin * 2
      height: tiles.height + root.contentMargin * 2
      radius: root.cornerRadius
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.isAutoRepeat) return
          var k = event.key
          if (k === Qt.Key_Escape) { if (root.chosenIndex === -1) root.finish(null) }
          else if (k === Qt.Key_Left) root.arrow(0)
          else if (k === Qt.Key_Right) root.arrow(1)
          else if (k === Qt.Key_Up) root.arrow(2)
          else if (k === Qt.Key_Down) root.arrow(3)
          else return
          event.accepted = true
        }
      }

      Item {
        id: tiles
        anchors.centerIn: parent
        width: root.step * 3 - root.tileSpacing
        height: root.step * (1 + root.hasUp + root.hasDown) - root.tileSpacing

        // The centre holds the label and a keycap for each profile's arrow key
        // at the edge nearest to it; a corner profile's two keys sit in its corner.
        Rectangle {
          id: centre
          x: root.step
          y: (1 - root.topRow) * root.step
          width: root.tileSize
          height: root.tileSize
          radius: root.cornerRadius
          color: "transparent"
          border.width: Math.max(1, Style.space(1))
          border.color: Qt.rgba(root.border.r, root.border.g, root.border.b, 0.35)

          Text {
            anchors.centerIn: parent
            width: parent.width - root.keycapSize * 2 - Style.space(16)
            text: "SELECT PROFILE"
            textFormat: Text.PlainText
            color: root.foreground
            opacity: 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.weight: Font.DemiBold
            font.letterSpacing: Style.space(2)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }

          readonly property real inset: Style.space(10)

          Repeater {
            model: Math.min(root.shown, 4)

            delegate: Keycap {
              required property int index
              readonly property var dir: root.slots[index]  // [col, row], centre is [1, 1]
              arrowIndex: index
              chosen: index === root.chosenIndex
              lit: chosen || (root.chosenIndex === -1 && (index === root.hoveredIndex || index === root.pendingSlot))
              x: dir[0] === 0 ? centre.inset : dir[0] === 2 ? parent.width - width - centre.inset : (parent.width - width) / 2
              y: dir[1] === 0 ? centre.inset : dir[1] === 2 ? parent.height - height - centre.inset : (parent.height - height) / 2
            }
          }

          // Corners: the two keys stacked like a copy icon, the horizontal arrow
          // behind and the vertical one in front, a little down and to the
          // right. The stack sits on the diagonal from the middle, as far out as
          // the single keys, so it lands halfway between the two it combines.
          // While one arrow waits for its partner, its half of each stack lights.
          Repeater {
            model: Math.max(0, root.shown - 4)

            delegate: Item {
              id: pair
              required property int index
              readonly property int slot: index + 4
              readonly property var dir: root.slots[slot]
              readonly property var arrows: root.cornerArrows(slot)
              readonly property bool chosen: slot === root.chosenIndex
              readonly property bool lit: chosen || (root.chosenIndex === -1 && slot === root.hoveredIndex)
              readonly property int offset: Math.round(root.cornerKeycapSize * 0.35)
              readonly property real radius: centre.width / 2 - centre.inset - root.keycapSize / 2
              width: root.cornerKeycapSize + offset
              height: width
              x: centre.width / 2 + (dir[0] === 0 ? -1 : 1) * radius / Math.SQRT2 - width / 2
              y: centre.height / 2 + (dir[1] === 0 ? -1 : 1) * radius / Math.SQRT2 - height / 2

              Keycap {
                size: root.cornerKeycapSize
                arrowIndex: pair.arrows[0]
                chosen: pair.chosen
                lit: pair.lit || (root.chosenIndex === -1 && root.pendingSlot === arrowIndex)
              }
              Keycap {
                x: pair.offset; y: pair.offset
                size: root.cornerKeycapSize
                arrowIndex: pair.arrows[1]
                chosen: pair.chosen
                lit: pair.lit || (root.chosenIndex === -1 && root.pendingSlot === arrowIndex)
              }
            }
          }
        }

        Repeater {
          model: root.profiles.slice(0, root.shown)

          delegate: Rectangle {
            id: tile
            required property var modelData
            required property int index
            readonly property bool chosen: index === root.chosenIndex
            readonly property bool current: chosen || (root.chosenIndex === -1 && (index === root.hoveredIndex || index === root.pendingSlot))
            readonly property var slot: root.slots[index]

            x: slot[0] * root.step
            y: (slot[1] - root.topRow) * root.step
            width: root.tileSize
            height: root.tileSize
            radius: root.cornerRadius
            color: current ? root.selectedBackground : "transparent"
            border.width: chosen ? Math.max(2, Style.space(2)) : Math.max(1, Style.space(1))
            border.color: chosen ? root.selectedText : current ? root.selectedBackground : root.border

            Column {
              anchors.centerIn: parent
              width: parent.width - Style.space(16)
              spacing: Style.space(8)

              ClippingRectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: root.avatarSize
                height: root.avatarSize
                radius: width / 2
                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.15)

                Image {
                  anchors.fill: parent
                  source: modelData.picture ? Util.fileUrl(modelData.picture) : ""
                  sourceSize: Qt.size(root.avatarSize * 2, root.avatarSize * 2)
                  fillMode: Image.PreserveAspectCrop
                  visible: status === Image.Ready
                }

                Text {
                  anchors.centerIn: parent
                  visible: !modelData.picture
                  text: (modelData.name || "?").charAt(0).toUpperCase()
                  textFormat: Text.PlainText
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.displayLarge
                }
              }

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: modelData.name
                color: current ? root.selectedText : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.heading
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: modelData.email || ""
                visible: text !== ""
                color: current ? root.selectedText : root.foreground
                opacity: 0.65
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideMiddle
              }

            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onContainsMouseChanged: root.hoveredIndex = containsMouse ? index : -1
              onClicked: root.activate(index)
            }
          }
        }
      }
    }
  }
}
