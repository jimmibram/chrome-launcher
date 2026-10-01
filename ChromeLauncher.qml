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
  property int chosenIndex: -1  // the profile just picked, shown with a bright edge
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
  property int keycapSize: Style.space(46)

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
    confirmTimer.stop()
    root.chosenIndex = -1
    root.opened = false
    root.release(choice)
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
    if (index < 0 || index >= root.profiles.length || root.chosenIndex !== -1) return
    // Outline the choice for a beat, then open it.
    root.chosenIndex = index
    confirmTimer.start()
  }

  Timer {
    id: confirmTimer
    interval: 320
    onTriggered: {
      var index = root.chosenIndex
      if (index >= 0 && index < root.profiles.length) root.finish(root.profiles[index].dir)
    }
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
          var k = event.key
          if (k === Qt.Key_Escape) { if (root.chosenIndex === -1) root.finish(null) }
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

        // The centre: a label, and a keycap for each profile's arrow key at the
        // edge nearest to it. The chosen one gets a bright edge, like its tile.
        Rectangle {
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

          Repeater {
            model: Math.min(root.profiles.length, 4)

            // A keycap with a triangle, drawn pointing right and rotated towards
            // its profile's slot.
            delegate: Item {
              id: keycap
              required property int index
              readonly property var dir: root.slots[index]  // [col, row], centre is [1, 1]
              readonly property real inset: Style.space(10)
              readonly property real lift: Math.max(2, Style.space(3))  // the cap sits this far above its base
              readonly property bool chosen: index === root.chosenIndex
              readonly property bool lit: chosen || (root.chosenIndex === -1 && index === root.hoveredIndex)

              width: root.keycapSize
              height: root.keycapSize
              x: dir[0] === 0 ? inset : dir[0] === 2 ? parent.width - width - inset : (parent.width - width) / 2
              y: dir[1] === 0 ? inset : dir[1] === 2 ? parent.height - height - inset : (parent.height - height) / 2
              rotation: [180, 0, 270, 90][index]
              scale: lit ? 1.1 : 1
              Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

              // Base: the darker edge the cap stands on, offset along the key's
              // own "down" so it reads as a keycap at every rotation.
              Rectangle {
                anchors.fill: cap
                anchors.topMargin: keycap.lift
                anchors.bottomMargin: -keycap.lift
                radius: cap.radius
                color: keycap.lit ? Qt.darker(root.selectedBackground, 1.4) : Qt.rgba(root.border.r, root.border.g, root.border.b, 0.9)
              }

              Rectangle {
                id: cap
                anchors.fill: parent
                anchors.bottomMargin: keycap.lift
                radius: Style.space(8)
                color: keycap.lit ? root.selectedBackground : root.background
                border.width: keycap.chosen ? Math.max(2, Style.space(2)) : Math.max(1, Style.space(1))
                border.color: keycap.chosen ? root.selectedText : keycap.lit ? root.selectedBackground : root.border
                Behavior on border.color { ColorAnimation { duration: 120 } }

                Shape {
                  id: triangle
                  anchors.centerIn: parent
                  width: parent.width * 0.42
                  height: parent.height * 0.42
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
            }
          }
        }

        Repeater {
          model: root.profiles.slice(0, 4)

          delegate: Rectangle {
            required property var modelData
            required property int index
            readonly property bool chosen: index === root.chosenIndex
            readonly property bool current: chosen || (root.chosenIndex === -1 && index === root.hoveredIndex)
            readonly property var slot: root.slots[index]

            x: slot[0] * root.step
            y: (slot[1] - root.topRow) * root.step
            width: root.tileSize
            height: root.tileSize
            radius: root.cornerRadius
            color: current ? root.selectedBackground : "transparent"
            border.width: chosen ? Math.max(2, Style.space(2)) : Math.max(1, Style.space(1))
            border.color: chosen ? root.selectedText : current ? root.selectedBackground : root.border
            Behavior on border.color { ColorAnimation { duration: 120 } }

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
