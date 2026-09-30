import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Ui

// Profiles laid out as a cross around an empty centre: left, right, then up and
// down once there are 3-4 profiles. An arrow key opens its profile at once.
// Summoned by bin/chrome-launcher
// with { profiles: [{ dir, name, email, picture }], icon, selectionFile, doneFile }.
// The chosen profile's dir is written to selectionFile, then doneFile is created.
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property var profiles: []
  property string icon: ""
  property int hoveredIndex: -1
  property string selectionFile: ""
  property string doneFile: ""

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

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) {}
    root.profiles = payload.profiles || []
    root.icon = String(payload.icon || "")
    root.selectionFile = String(payload.selectionFile || "")
    root.doneFile = String(payload.doneFile || "")
    root.hoveredIndex = -1
    root.opened = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    // Hidden from outside (e.g. toggled away): still release the waiting script.
    if (root.opened) root.finish(null)
  }

  function finish(dir) {
    root.opened = false
    if (root.doneFile) {
      var done = Util.shellQuote(root.doneFile)
      resultProc.command = dir === null
        ? ["bash", "-c", ": > " + done]
        : ["bash", "-c", "printf '%s\\n' " + Util.shellQuote(dir) + " > " + Util.shellQuote(root.selectionFile) + "; : > " + done]
      resultProc.running = true
    }
    root.doneFile = ""
    root.selectionFile = ""
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "jimmibram.chrome-launcher")
  }

  // Slot order: left, right, up, down (column, row in a 3x3 grid).
  readonly property var slots: [[0, 1], [2, 1], [1, 0], [1, 2]]
  // Rows only exist when there is a profile in them: up with 3+, down with 4.
  readonly property bool hasUp: profiles.length > 2
  readonly property bool hasDown: profiles.length > 3
  readonly property int topRow: hasUp ? 0 : 1
  readonly property int step: tileSize + tileSpacing

  function activate(index) {
    if (index < 0 || index >= root.profiles.length) return
    root.finish(root.profiles[index].dir)
  }

  Process { id: resultProc }

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
      onClicked: root.finish(null)
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
          var k = event.key
          if (k === Qt.Key_Escape) root.finish(null)
          else if (k === Qt.Key_Left) root.activate(0)
          else if (k === Qt.Key_Right) root.activate(1)
          else if (k === Qt.Key_Up) root.activate(2)
          else if (k === Qt.Key_Down) root.activate(3)
          else return
          event.accepted = true
        }
      }

      Item {
        id: tiles
        anchors.centerIn: parent
        width: root.step * 3 - root.tileSpacing
        height: root.step * (1 + root.hasUp + root.hasDown) - root.tileSpacing

        // The centre, where the "cursor" starts: the browser's own icon, faded.
        Rectangle {
          x: root.step
          y: (1 - root.topRow) * root.step
          width: root.tileSize
          height: root.tileSize
          radius: root.cornerRadius
          color: "transparent"
          border.width: Math.max(1, Style.space(1))
          border.color: Qt.rgba(root.border.r, root.border.g, root.border.b, 0.35)

          Image {
            anchors.centerIn: parent
            width: root.avatarSize
            height: root.avatarSize
            source: root.icon ? "file://" + root.icon : ""
            sourceSize: Qt.size(root.avatarSize * 2, root.avatarSize * 2)
            fillMode: Image.PreserveAspectFit
            smooth: true
            opacity: 0.12
          }

          // Thick arrows pointing at each profile; the hovered one lights up.
          Repeater {
            model: Math.min(root.profiles.length, 4)

            // Drawn pointing right, then rotated towards its profile's slot.
            delegate: Shape {
              id: arrow
              required property int index
              readonly property var dir: root.slots[index]  // [col, row], centre is [1, 1]
              readonly property real inset: Style.space(12)
              readonly property real size: Style.space(40)
              readonly property real stroke: Style.space(7)
              readonly property bool lit: index === root.hoveredIndex

              width: size
              height: size
              x: dir[0] === 0 ? inset : dir[0] === 2 ? parent.width - width - inset : (parent.width - width) / 2
              y: dir[1] === 0 ? inset : dir[1] === 2 ? parent.height - height - inset : (parent.height - height) / 2
              rotation: [180, 0, 270, 90][index]
              preferredRendererType: Shape.CurveRenderer
              opacity: lit ? 1 : 0.85
              scale: lit ? 1.15 : 1
              Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

              ShapePath {
                strokeColor: arrow.lit ? root.selectedText : root.foreground
                strokeWidth: arrow.stroke
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                // shaft
                startX: arrow.stroke / 2; startY: arrow.size / 2
                PathLine { x: arrow.size - arrow.stroke / 2; y: arrow.size / 2 }
                // head
                PathMove { x: arrow.size * 0.55; y: arrow.stroke / 2 + arrow.size * 0.05 }
                PathLine { x: arrow.size - arrow.stroke / 2; y: arrow.size / 2 }
                PathLine { x: arrow.size * 0.55; y: arrow.size - arrow.stroke / 2 - arrow.size * 0.05 }
              }
            }
          }
        }

        Repeater {
          model: root.profiles.slice(0, 4)

          delegate: Rectangle {
            required property var modelData
            required property int index
            readonly property bool current: index === root.hoveredIndex
            readonly property var slot: root.slots[index]

            x: slot[0] * root.step
            y: (slot[1] - root.topRow) * root.step
            width: root.tileSize
            height: root.tileSize
            radius: root.cornerRadius
            color: current ? root.selectedBackground : "transparent"
            border.width: Math.max(1, Style.space(1))
            border.color: current ? root.selectedBackground : root.border

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
                  source: modelData.picture ? "file://" + modelData.picture : ""
                  sourceSize: Qt.size(root.avatarSize * 2, root.avatarSize * 2)
                  fillMode: Image.PreserveAspectCrop
                  visible: status === Image.Ready
                }

                Text {
                  anchors.centerIn: parent
                  visible: !modelData.picture
                  text: (modelData.name || "?").charAt(0).toUpperCase()
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
