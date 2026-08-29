import QtQuick
import qs.Ui

// Nommarchy — the menubar launcher icon. Left-click toggles the EQ panel;
// right-click quits (removes this icon from the bar). The panel itself is the
// plugin's `panel` entry point (Panel.qml), and the launcher entry survives
// so it can be relaunched from the Omarchy menu at any time.
BarWidget {
  id: root
  moduleName: "pablopunk.nommarchy"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰺢"
    onPressed: function(b) {
      if (!root.bar) return
      if (b === Qt.RightButton)
        root.bar.run("omarchy plugin disable pablopunk.nommarchy")
      else
        root.bar.run("omarchy-shell shell toggle pablopunk.nommarchy")
    }
  }
}
