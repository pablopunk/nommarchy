import QtQuick
import Quickshell

// Installs the launcher entry so the panel is reachable from the Omarchy menu
// (search "Nommarchy"). The entry is left in place when the plugin is
// disabled or quit, so it can always be relaunched.
QtObject {
  id: root

  property string omarchyPath: ""
  property var shell: null
  property var manifest: null

  readonly property string dest: Quickshell.env("HOME") + "/.local/share/applications/nommarchy.desktop"

  property bool installed: false

  onManifestChanged: {
    var dir = manifest && manifest.__sourceDir
    if (installed || !dir) return
    installed = true
    Quickshell.execDetached(["sh", "-c",
      'mkdir -p "${2%/*}" && cp "$1" "$2"', "sh",
      dir + "/nommarchy.desktop", dest])
  }
}
