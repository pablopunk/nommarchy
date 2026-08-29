import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Ui
import qs.Commons

// Nommarchy — Razer Nommo V2 X control panel.
//
// An app-style Omarchy panel: summon it from the Omarchy menu ("Nommarchy")
// or with `omarchy-shell shell toggle pablopunk.nommarchy`, and it opens as a
// centered window. State is read from the speakers over USB HID (report 0x07)
// via the `nommarchy` CLI (installed by the repo's install.sh).
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool connected: false
  property bool eco: false
  property int sleepSeconds: 0
  property int preset: 0
  property string presetName: "flat"
  property bool bandsBeingDragged: false
  property int focusBand: -1
  property var groupDragBaseline: []
  property bool opened: false

  readonly property int sleepMinutes: Math.round(root.sleepSeconds / 60)
  readonly property var presetOptions: ["flat", "game", "movie", "music"]

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color accent: Color.accent
  property color scrim: Color.menu.scrim
  property string fontFamily: Style.font.menuFamily

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

  // -- lifecycle ------------------------------------------------------------

  function open(payloadJson) {
    root.opened = true
    root.refresh()
    Qt.callLater(function() { if (root.opened) keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "pablopunk.nommarchy")
    else
      close()
  }

  function toggle() {
    root.opened ? root.dismiss() : root.open("{}")
  }

  // -- device I/O -----------------------------------------------------------

  Process {
    id: statusProc
    command: ["nommarchy", "json"]
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
    Quickshell.execDetached(["nommarchy"].concat(args))
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

  // -- window ---------------------------------------------------------------

  PanelWindow {
    id: window
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "pablopunk.nommarchy"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Rectangle {
      anchors.fill: parent
      color: root.scrim
      MouseArea { anchors.fill: parent; onClicked: root.dismiss() }
    }

    BorderSurface {
      id: card
      anchors.centerIn: parent
      width: Math.min(Style.space(680), window.width - Style.gapsOut * 4)
      height: Math.min(Style.space(600), window.height - Style.gapsOut * 4)
      radius: Style.cornerRadius
      color: root.background
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
      padding: Style.spacing.panelPadding

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) { root.dismiss(); event.accepted = true }
          else if (event.key === Qt.Key_Down || event.text === "j") {
            if (root.focusBand < 0) root.focusBand = 0
            root.nudgeBand(root.focusBand, -1); event.accepted = true
          }
          else if (event.key === Qt.Key_Up || event.text === "k") {
            if (root.focusBand < 0) root.focusBand = 0
            root.nudgeBand(root.focusBand, 1); event.accepted = true
          }
          else if (event.key === Qt.Key_Right || event.text === "l") { root.moveFocus(1); event.accepted = true }
          else if (event.key === Qt.Key_Left || event.text === "h") { root.moveFocus(-1); event.accepted = true }
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.space(12)

        // ---- hero ----
        Item {
          width: parent.width
          implicitHeight: Math.max(heroLabels.implicitHeight, closeButton.implicitHeight)

          Column {
            id: heroLabels
            anchors.left: parent.left
            anchors.right: closeButton.left
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: "Nommarchy"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
              width: parent.width
              elide: Text.ElideRight
            }

            Text {
              text: (root.connected ? ("preset · " + root.presetName) : "not connected").toUpperCase()
              color: Qt.darker(root.foreground, 1.6)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              width: parent.width
              elide: Text.ElideRight
            }
          }

          PanelActionButton {
            id: closeButton
            iconText: "󰅖"
            tooltipText: "Close  ·  Esc"
            foreground: root.foreground
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            onClicked: root.dismiss()
          }
        }

        PanelSeparator { foreground: root.foreground }

        // ---- EQ presets ----
        PanelSectionHeader {
          text: "EQ PRESET"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        ButtonGroup {
          options: root.presetOptions
          value: root.connected ? root.presetName : ""
          foreground: root.foreground
          background: "transparent"
          accent: root.accent
          fontFamily: root.fontFamily
          onChanged: root.setPreset(value)
        }

        PanelSeparator { foreground: root.foreground }

        // ---- 10-band EQ ----
        Item {
          width: parent.width
          implicitHeight: Math.max(eqHeader.implicitHeight, minButton.implicitHeight)

          PanelSectionHeader {
            id: eqHeader
            text: "10-BAND EQUALIZER"
            foreground: root.foreground
            fontFamily: root.fontFamily
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Button {
            id: minButton
            text: "Min"
            bordered: true
            foreground: root.foreground
            background: "transparent"
            accent: root.accent
            fontFamily: root.fontFamily
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
          color: Qt.darker(root.foreground, 1.6)
          font.family: root.fontFamily
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
              foreground: root.foreground
              accent: root.accent

              Column {
                id: bandColumn
                anchors.centerIn: parent
                spacing: Style.space(4)

                Text {
                  text: (bandRow.gain > 0 ? "+" : "") + bandRow.gain
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  horizontalAlignment: Text.AlignHCenter
                  width: parent.width
                }

                Item {
                  id: slider
                  width: Style.space(18)
                  height: Style.space(140)
                  anchors.horizontalCenter: parent.horizontalCenter

                  readonly property real minimum: -12
                  readonly property real maximum: 12
                  readonly property real range: 24
                  readonly property real progress: Math.max(0, Math.min(1, (bandRow.gain - minimum) / range))
                  readonly property real trackWidth: Math.max(4, Math.round(Style.spacing.controlHeight * 0.11))
                  readonly property real knobSize: Math.max(14, Math.round(Style.spacing.controlHeight * 0.38))
                  readonly property color trackColor: Style.selectedFillFor(root.foreground, root.accent)
                  readonly property color fillColor: root.foreground

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
                    color: Util.alpha(root.foreground, 0.28)
                  }

                  BorderSurface {
                    id: knob
                    width: slider.knobSize
                    height: slider.knobSize
                    radius: width / 2
                    color: slider.fillColor
                    borderSpec: Border.flat(root.background, Math.max(1, Style.space(2)))
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
                  color: root.foreground
                  font.family: root.fontFamily
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

        PanelSeparator { foreground: root.foreground }

        // ---- power ----
        PanelSectionHeader {
          text: "POWER"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Toggle {
          width: parent.width
          label: "Eco mode"
          description: "Put the speakers to sleep when idle"
          checked: root.eco
          foreground: root.foreground
          accent: root.accent
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
                foreground: root.foreground
                fontFamily: root.fontFamily
                anchors.verticalCenter: parent.verticalCenter
              }

              Item {
                width: parent.width - sleepHeader.implicitWidth - sleepValue.implicitWidth
                height: 1
              }

              Text {
                id: sleepValue
                text: root.sleepMinutes > 0 ? root.sleepMinutes + " min" : "Never"
                color: Qt.darker(root.foreground, 1.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            PanelSlider {
              id: sleepSlider
              bar: null
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

  IpcHandler {
    target: "pablopunk.nommarchy"
    function open(): void { root.open("{}") }
    function close(): void { root.dismiss() }
    function toggle(): void { root.toggle() }
  }
}
