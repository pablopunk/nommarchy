import QtQuick
import Quickshell

// Installs the launcher entry so nommarchy appears in the Omarchy menu and can
// be launched like an app (re-enabling the bar icon if it was quit, then
// opening the panel). The entry and its icon are left in place when the plugin
// is disabled or quit, so it can always be relaunched.
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
      'mkdir -p "${2%/*}" && sed "s|@ICON@|$3|" "$1" > "$2"', "sh",
      dir + "/nommarchy.desktop", dest, dir + "/icon.png"])
  }
}
