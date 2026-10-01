import Quickshell
import Quickshell.Hyprland
import QtQuick
import qs.Commons

// Takes over Omarchy's browser key (SUPER+SHIFT+RETURN) while the plugin is
// enabled, so installing it is all it takes. The binding lives only in the
// running Hyprland, never in the user's config: it is applied again after every
// config reload (which drops it). On disable the key is handed back to Omarchy's
// own browser launcher, the binding its default config gives it, rather than
// reloading the whole config: a reload would also discard runtime changes and
// would run on every shell restart, since that destroys this item too.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string keys: "SUPER + SHIFT + RETURN"
  readonly property string script: decodeURIComponent(String(Qt.resolvedUrl("bin/chrome-launcher")).replace(/^file:\/\//, ""))

  // Quote a value as a Lua string literal: backslash, double quote and control
  // characters become \ddd escapes, so nothing in it can be read as code.
  function luaString(value) {
    return '"' + String(value).replace(/[\\"\x00-\x1f\x7f]/g, function(c) {
      var n = c.charCodeAt(0)
      return "\\" + (n < 10 ? "00" : n < 100 ? "0" : "") + n
    }) + '"'
  }

  function bind() {
    // exec_cmd runs its argument through /bin/sh, so the path is shell-quoted too.
    var lua = "hl.unbind(" + luaString(root.keys) + ")"
      + " hl.bind(" + luaString(root.keys) + ", hl.dsp.exec_cmd(" + luaString(Util.shellQuote(root.script)) + "),"
      + " { description = \"Chrome Launcher\" })"
    Quickshell.execDetached(["hyprctl", "eval", lua])
  }

  function unbind() {
    var lua = "hl.unbind(" + luaString(root.keys) + ")"
      + " hl.bind(" + luaString(root.keys) + ", hl.dsp.exec_cmd(\"omarchy-launch-browser\"),"
      + " { description = \"Browser\" })"
    Quickshell.execDetached(["hyprctl", "eval", lua])
  }

  Component.onCompleted: root.bind()
  Component.onDestruction: root.unbind()

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event && event.name === "configreloaded") root.bind()
    }
  }
}
