import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Nommarchy — Razer Nommo V2 X control panel.
//
// A tray-style bar widget: an equalizer icon in the bar opens this popup with
// the 10-band EQ, presets, eco mode and sleep timeout. The Quit button removes
// the icon from the bar (`omarchy plugin enable pablopunk.nommarchy right`
// brings it back). State is read from the speakers over USB HID (report 0x07)
// via the `nommarchy` CLI (installed by the repo's install.sh).
Panel {
  id: root
  moduleName: "pablopunk.nommarchy"
  ipcTarget: "pablopunk.nommarchy"

  property bool connected: false
  property bool eco: false
  property int sleepSeconds: 0
  property int preset: 0
  property string presetName: "flat"
  property bool bandsBeingDragged: false
  property int focusBand: -1
  property var groupDragBaseline: []

  readonly property int sleepMinutes: Math.round(root.sleepSeconds / 60)
  readonly property var presetOptions: ["flat", "game", "movie", "music"]
  // The installer (install.sh) puts the CLI at ~/.local/bin/nommarchy; invoke
  // it by absolute path so the panel does not depend on the shell's PATH.
  readonly property string backend: Quickshell.env("HOME") + "/.local/bin/nommarchy"

  ListModel {
    id: bandsModel
    ListElement { label: "31";  gain: 0 }
    ListElement { label: "63";  gain: 0 }
    ListElement { label: "125"; gain: 0 }
    ListElement { label: "250"; gain: 0 }
    ListElement { label: "500"; gain: 0 }
    ListElement { label: "1k";  gain: 0 }
    ListElement { label: "2k";  gain: 0 }
    ListElement { label: "4k";  gain: 0 }
    ListElement { label: "8k";  gain: 0 }
    ListElement { label: "16k"; gain: 0 }
  }

  function gains() {
    var arr = []
    for (var i = 0; i < bandsModel.count; i++) arr.push(bandsModel.get(i).gain)
    return arr
  }

  // -- device I/O -----------------------------------------------------------

  Process {
    id: statusProc
    command: [root.backend, "json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseStatus(text)
    }
  }

  function parseStatus(raw) {
    var o
    try { o = JSON.parse(String(raw).trim()) } catch (e) { return }
    if (!o) return
    root.connected = !!o.connected
    if (!o.connected) return
    root.eco = !!o.eco
    root.sleepSeconds = Number(o.sleepSeconds) || 0
    root.preset = Number(o.preset) || 0
    root.presetName = String(o.presetName || "flat")
    // The band registers only hold the *custom* curve; a built-in preset's
    // curve is firmware-owned and unreadable, so while a preset (not custom)
    // is active the bars show flat and we ignore the stale register values.
    if (root.bandsBeingDragged || bandWrite.running || refreshTimer.running) return
    if (root.preset === 0x10) {
      var bands = o.bands || []
      for (var i = 0; i < bandsModel.count && i < bands.length; i++)
        bandsModel.setProperty(i, "gain", Number(bands[i]))
    } else {
      for (var i = 0; i < bandsModel.count; i++)
        bandsModel.setProperty(i, "gain", 0)
    }
  }

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function exec(args) {
    if (!root.connected) return
    Quickshell.execDetached([root.backend].concat(args))
    refreshTimer.restart()
  }

  Timer {
    id: refreshTimer
    interval: 250
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    id: bandWrite
    interval: 150
    repeat: false
    onTriggered: root.exec(["eq"].concat(root.gains().map(String)))
  }

  Timer {
    id: sleepWrite
    interval: 150
    repeat: false
    onTriggered: root.exec(["sleep", root.sleepMinutes > 0 ? String(root.sleepMinutes) : "off"])
  }

  Timer {
    id: pollTimer
    interval: 4000
    running: root.opened
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!bandWrite.running && !sleepWrite.running) root.refresh()
  }

  onOpenedChanged: if (root.opened) root.refresh()

  function setPreset(name) {
    if (!root.connected) return
    root.presetName = name
    root.resetBandsToFlat()
    root.exec(["preset", name])
  }

  function resetBandsToFlat() {
    for (var i = 0; i < bandsModel.count; i++)
      bandsModel.setProperty(i, "gain", 0)
  }

  function zeroAllBands() {
    if (!root.connected) return
    root.resetBandsToFlat()
    root.presetName = "custom"
    root.bandsBeingDragged = false
    bandWrite.restart()
  }

  function setEco(on) {
    if (!root.connected) return
    root.eco = on
    root.exec(["eco", on ? "on" : "off"])
  }

  function setBand(index, gain) {
    bandsModel.setProperty(index, "gain", gain)
    root.presetName = "custom"
    bandWrite.restart()
  }

  function nudgeBand(index, delta) {
    var g = bandsModel.get(index).gain
    setBand(index, Math.max(-12, Math.min(12, g + delta)))
  }

  function moveFocus(dx) {
    if (root.focusBand < 0) root.focusBand = 0
    else root.focusBand = Math.max(0, Math.min(bandsModel.count - 1, root.focusBand + dx))
  }

  function beginGroupDrag() {
    root.groupDragBaseline = root.gains()
    root.bandsBeingDragged = true
    root.presetName = "custom"
  }

  function applyGroupDrag(delta) {
    for (var i = 0; i < bandsModel.count; i++) {
      var g = root.groupDragBaseline[i] + delta
      bandsModel.setProperty(i, "gain", Math.max(-12, Math.min(12, g)))
    }
    root.bandsBeingDragged = true
    bandWrite.restart()
  }

  function endGroupDrag() {
    root.groupDragBaseline = []
    root.bandsBeingDragged = false
    bandWrite.restart()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // -- tray icon ------------------------------------------------------------

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰺢"
    opacity: root.connected ? 1.0 : 0.45
    onPressed: function(b) {
      if (b === Qt.RightButton) root.refresh()
      else root.toggle()
    }
  }

  // -- popup panel ----------------------------------------------------------

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(600))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) {
          if (root.focusBand < 0) root.focusBand = 0
          root.nudgeBand(root.focusBand, dy < 0 ? 1 : -1)
        } else if (dx !== 0) {
          root.moveFocus(dx)
        }
      }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: panelColumn.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        Binding {
          target: scrollArea.contentItem
          property: "interactive"
          value: panelColumn.implicitHeight > scrollArea.height
        }

        Column {
          id: panelColumn
          width: scrollArea.availableWidth
          spacing: Style.space(14)

          // ---- hero ----
          Item {
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, quitButton.implicitHeight)

            Text {
              id: heroIcon
              text: "󰺢"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.display
              opacity: root.connected ? 1.0 : 0.45
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Column {
              id: heroLabels
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.right: quitButton.left
              anchors.rightMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                text: "Nommarchy"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
                width: parent.width
              }

              Text {
                text: (root.connected ? ("preset · " + root.presetName) : "not connected").toUpperCase()
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
                elide: Text.ElideRight
                width: parent.width
              }
            }

            Button {
              id: quitButton
              text: "Quit"
              bordered: true
              foreground: root.bar.foreground
              background: "transparent"
              accent: Color.accent
              fontFamily: root.bar.fontFamily
              fontSize: Style.font.caption
              tooltipText: "Remove nommarchy from the bar"
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              onClicked: Quickshell.execDetached(["omarchy", "plugin", "disable", "pablopunk.nommarchy"])
            }
          }

          PanelSeparator { foreground: root.bar.foreground }

          // ---- EQ presets ----
          PanelSectionHeader {
            text: "EQ PRESET"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          ButtonGroup {
            options: root.presetOptions
            value: root.connected ? root.presetName : ""
            foreground: root.bar.foreground
            background: "transparent"
            fontFamily: root.bar.fontFamily
            onChanged: root.setPreset(value)
          }

          PanelSeparator { foreground: root.bar.foreground }

          // ---- 10-band EQ ----
          Item {
            width: parent.width
            implicitHeight: Math.max(eqHeader.implicitHeight, minButton.implicitHeight)

            PanelSectionHeader {
              id: eqHeader
              text: "10-BAND EQUALIZER"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Button {
              id: minButton
              text: "Min"
              bordered: true
              foreground: root.bar.foreground
              background: "transparent"
              fontFamily: root.bar.fontFamily
              fontSize: Style.font.caption
              tooltipText: "Every band at −12 dB"
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              onClicked: {
                if (!root.connected) return
                for (var i = 0; i < bandsModel.count; i++) bandsModel.setProperty(i, "gain", -12)
                root.presetName = "custom"
                bandWrite.restart()
              }
            }
          }

          Text {
            text: "right-drag all · 2×click reset · 2×right-click flat"
            color: Qt.darker(root.bar.foreground, 1.5)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            opacity: 0.85
            width: parent.width
            elide: Text.ElideRight
          }

          Row {
            id: bandsRow
            width: parent.width
            spacing: Style.space(2)

            Repeater {
              model: bandsModel
              delegate: CursorSurface {
                id: bandRow
                required property int index
                required property string label
                required property int gain
                width: (bandsRow.width - (bandsModel.count - 1) * bandsRow.spacing) / bandsModel.count
                implicitHeight: bandColumn.implicitHeight + Style.space(6)
                hasCursor: root.focusBand === index
                foreground: root.bar.foreground

                Column {
                  id: bandColumn
                  anchors.centerIn: parent
                  spacing: Style.space(4)

                  Text {
                    text: (bandRow.gain > 0 ? "+" : "") + bandRow.gain
                    color: root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    width: parent.width
                  }

                  Item {
                    id: slider
                    width: Style.space(18)
                    height: Style.space(130)
                    anchors.horizontalCenter: parent.horizontalCenter

                    readonly property real minimum: -12
                    readonly property real maximum: 12
                    readonly property real range: 24
                    readonly property real progress: Math.max(0, Math.min(1, (bandRow.gain - minimum) / range))
                    readonly property real trackWidth: Math.max(4, Math.round(Style.spacing.controlHeight * 0.11))
                    readonly property real knobSize: Math.max(14, Math.round(Style.spacing.controlHeight * 0.38))
                    readonly property color trackColor: root.bar ? Style.selectedFillFor(root.bar.foreground, Color.accent) : "#333"
                    readonly property color fillColor: root.bar ? root.bar.foreground : Color.foreground

                    property bool groupDragging: false
                    property real groupStartY: 0
                    property bool zeroLock: false

                    function valueFromY(y) {
                      var clamped = Math.max(0, Math.min(height, y))
                      var progress = 1 - clamped / height
                      var raw = minimum + progress * range
                      return Math.max(minimum, Math.min(maximum, Math.round(raw)))
                    }

                    Rectangle {
                      anchors.horizontalCenter: parent.horizontalCenter
                      anchors.top: parent.top
                      anchors.bottom: parent.bottom
                      width: slider.trackWidth
                      radius: width / 2
                      color: slider.trackColor
                    }

                    Rectangle {
                      anchors.horizontalCenter: parent.horizontalCenter
                      anchors.bottom: parent.bottom
                      width: slider.trackWidth
                      height: parent.height * slider.progress
                      radius: slider.trackWidth / 2
                      color: slider.fillColor
                      Behavior on height { enabled: !mouseArea.pressed; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    }

                    Rectangle {
                      anchors.horizontalCenter: parent.horizontalCenter
                      y: parent.height / 2 - height / 2
                      width: slider.trackWidth + Style.space(4)
                      height: Math.max(1, Style.space(1))
                      color: Util.alpha(root.bar.foreground, 0.28)
                    }

                    BorderSurface {
                      id: knob
                      width: slider.knobSize
                      height: slider.knobSize
                      radius: width / 2
                      color: slider.fillColor
                      borderSpec: Border.flat(root.bar ? root.bar.background : "#101315", Math.max(1, Style.space(2)))
                      anchors.horizontalCenter: parent.horizontalCenter
                      y: Math.max(0, Math.min(parent.height - height, parent.height * (1 - slider.progress) - height / 2))
                      scale: (mouseArea.containsMouse || mouseArea.pressed) ? 1.15 : 1.0
                      Behavior on y { enabled: !mouseArea.pressed; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                      Behavior on scale { NumberAnimation { duration: 110 } }
                    }

                    MouseArea {
                      id: mouseArea
                      anchors.fill: parent
                      enabled: root.connected
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      acceptedButtons: Qt.LeftButton | Qt.RightButton

                      onPressed: function(mouse) {
                        if (slider.zeroLock) return
                        if (mouse.button === Qt.RightButton) {
                          slider.groupDragging = true
                          slider.groupStartY = mouse.y
                          root.beginGroupDrag()
                        } else {
                          root.bandsBeingDragged = true
                          root.setBand(bandRow.index, slider.valueFromY(mouse.y))
                        }
                      }
                      onPositionChanged: function(mouse) {
                        if (slider.zeroLock) return
                        if (slider.groupDragging) {
                          var delta = slider.valueFromY(mouse.y) - slider.valueFromY(slider.groupStartY)
                          root.applyGroupDrag(delta)
                        } else if (pressed) {
                          root.setBand(bandRow.index, slider.valueFromY(mouse.y))
                        }
                      }
                      onReleased: function(mouse) {
                        if (slider.zeroLock) {
                          slider.zeroLock = false
                          return
                        }
                        if (slider.groupDragging && mouse.button === Qt.RightButton) {
                          slider.groupDragging = false
                          root.endGroupDrag()
                        } else {
                          root.bandsBeingDragged = false
                          bandWrite.restart()
                        }
                      }
                      onDoubleClicked: function(mouse) {
                        if (mouse.button === Qt.RightButton) {
                          slider.groupDragging = false
                          slider.zeroLock = true
                          root.zeroAllBands()
                        } else if (mouse.button === Qt.LeftButton) {
                          root.setBand(bandRow.index, 0)
                        }
                      }
                      onWheel: function(wheel) {
                        var delta = wheel.angleDelta.y > 0 ? 1 : -1
                        root.nudgeBand(bandRow.index, delta)
                      }
                    }
                  }

                  Text {
                    text: bandRow.label
                    color: root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    width: parent.width
                  }
                }

                HoverHandler {
                  onHoveredChanged: if (hovered) root.focusBand = bandRow.index
                }
              }
            }
          }

          PanelSeparator { foreground: root.bar.foreground }

          // ---- power ----
          PanelSectionHeader {
            text: "POWER"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Toggle {
            width: parent.width
            label: "Eco mode"
            description: "Put the speakers to sleep when idle"
            checked: root.eco
            foreground: root.bar.foreground
            onClicked: root.setEco(!root.eco)
          }

          Item {
            width: parent.width
            implicitHeight: sleepColumn.implicitHeight + Style.space(6)

            Column {
              id: sleepColumn
              width: parent.width
              spacing: Style.space(4)

              Row {
                width: parent.width

                PanelSectionHeader {
                  id: sleepHeader
                  text: "SLEEP TIMEOUT"
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                  anchors.verticalCenter: parent.verticalCenter
                }

                Item {
                  width: parent.width - sleepHeader.implicitWidth - sleepValue.implicitWidth
                  height: 1
                }

                Text {
                  id: sleepValue
                  text: root.sleepMinutes > 0 ? root.sleepMinutes + " min" : "Never"
                  color: Qt.darker(root.bar.foreground, 1.4)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              PanelSlider {
                id: sleepSlider
                bar: root.bar
                width: parent.width
                minimum: 0
                maximum: 120
                step: 5
                integer: true
                tickCount: 25
                value: root.sleepMinutes
                enabled: root.connected
                onMoved: function(v) {
                  root.sleepSeconds = Math.round(v) * 60
                  sleepWrite.restart()
                }
              }
            }
          }
        }
      }
    }
  }
}
