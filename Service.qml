import Quickshell
import Quickshell.Hyprland
import QtQuick

// Takes over Omarchy's browser key (SUPER+SHIFT+RETURN) while the plugin is
// enabled, so installing it is all it takes. The binding lives only in the
// running Hyprland, never in the user's config: it is applied again after every
// config reload (which drops it), and a reload on disable brings back Omarchy's
// own browser binding.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string keys: "SUPER + SHIFT + RETURN"
  readonly property string script: decodeURIComponent(String(Qt.resolvedUrl("bin/chrome-launcher")).replace(/^file:\/\//, ""))

  function bind() {
    // JSON string literals are valid Lua string literals for a plain path.
    var lua = "hl.unbind(" + JSON.stringify(root.keys) + ")"
      + " hl.bind(" + JSON.stringify(root.keys) + ", hl.dsp.exec_cmd(" + JSON.stringify(root.script) + "),"
      + " { description = \"Chrome Launcher\" })"
    Quickshell.execDetached(["hyprctl", "eval", lua])
  }

  Component.onCompleted: root.bind()
  Component.onDestruction: Quickshell.execDetached(["hyprctl", "reload"])

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event && event.name === "configreloaded") root.bind()
    }
  }
}
