import Quickshell.Io
import QtQuick

// The service entry point. It only loads KeyBinding.qml, which takes over the
// browser key. As with ChromeLauncher.qml, a URL the shell has never seen
// makes it load the new code after an update. The shell keeps this service
// running through updates, so it also loads KeyBinding.qml again whenever the
// file changes. Keep this file unchanged between releases.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property url source: Qt.resolvedUrl("KeyBinding.qml")
  property string loadUrl: root.source + "?load=" + Date.now()

  FileView {
    path: decodeURIComponent(String(root.source).replace(/^file:\/\//, ""))
    watchChanges: true
    printErrors: false
    onFileChanged: {
      // The new code binds the key itself, so the old must not hand it back.
      if (binding.item) binding.item.handedOver = true
      root.loadUrl = root.source + "?load=" + Date.now()
    }
  }

  Loader {
    id: binding
    source: root.loadUrl
    onLoaded: {
      item.shell = Qt.binding(function() { return root.shell })
      item.manifest = Qt.binding(function() { return root.manifest })
    }
  }
}
