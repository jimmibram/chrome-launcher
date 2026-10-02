import QtQuick

// The overlay entry point. It only loads Picker.qml, which holds the picker.
// The shell keeps compiled QML by URL for as long as it runs, so after an
// update it would rebuild this overlay from the old code. Loading the picker
// under a URL it has never seen gets the new code instead. Since the shell may
// keep running this file as it was, keep it unchanged between releases.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property bool opened: picker.item ? picker.item.opened === true : false
  property var pending: []  // requests that came before the picker had loaded

  function open(request) {
    if (picker.item) picker.item.open(request)
    else root.pending.push(request)
  }

  function close() {
    if (picker.item) picker.item.close()
  }

  Loader {
    id: picker
    source: Qt.resolvedUrl("Picker.qml") + "?load=" + Date.now()
    onLoaded: {
      item.shell = Qt.binding(function() { return root.shell })
      item.manifest = Qt.binding(function() { return root.manifest })
      var requests = root.pending
      root.pending = []
      for (var i = 0; i < requests.length; i++) item.open(requests[i])
    }
  }
}
