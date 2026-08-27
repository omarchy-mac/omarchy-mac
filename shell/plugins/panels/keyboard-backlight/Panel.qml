import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model

Panel {
  id: root
  moduleName: "omarchy.keyboard-backlight"
  ipcTarget: "omarchy.keyboard-backlight"
  manageIpc: false

  property int brightnessPercent: 0
  property bool brightnessAvailable: false
  property bool brightnessSetQueued: false

  readonly property var visibleSections: brightnessAvailable ? ["brightness"] : []

  // Single IpcHandler at the panel level, matching the monitor panel pattern.
  IpcHandler {
    target: root.ipcTarget

    function brightness(percent: string): string {
      root.setBrightness(Number(percent))
      return "ok"
    }

    function state(): string {
      return JSON.stringify({
        brightness: root.brightnessPercent,
        brightnessAvailable: root.brightnessAvailable
      })
    }
  }

  // Process objects at panel level to avoid creating new ones per call.
  Process {
    id: getBrightnessProc
    command: ["omarchy-brightness-keyboard", "--no-osd", "get"]
    onExited: (exitCode, stdout) => {
      if (exitCode === 0) {
        var value = Number(stdout.trim())
        if (isFinite(value)) {
          root.brightnessPercent = Model.clampBrightness(value)
          root.brightnessAvailable = true
        } else {
          root.brightnessAvailable = false
        }
      } else {
        root.brightnessAvailable = false
      }
    }
  }

  Process {
    id: setBrightnessProc
    onExited: (exitCode) => {
      root.brightnessSetQueued = false
      if (exitCode === 0) {
        root.brightnessPercent = Model.clampBrightness(root.pendingBrightnessPercent)
      }
    }
  }

  property int pendingBrightnessPercent: 0

  function refresh() {
    if (!getBrightnessProc.running) {
      getBrightnessProc.start()
    }
  }

  function setBrightness(value) {
    var percent = Model.clampBrightness(value)
    root.pendingBrightnessPercent = percent

    if (setBrightnessProc.running) {
      root.brightnessSetQueued = true
      return
    }

    root.brightnessSetQueued = false
    setBrightnessProc.command = ["omarchy-brightness-keyboard", "--no-osd", "set", String(percent)]
    setBrightnessProc.start()
  }

  brightnessDebounce: Timer {
    id: brightnessDebounce
    interval: 150
    repeat: false
    onTriggered: root.setBrightness(root.brightnessPercent)
  }

  ListModel { id: sectionModel }

  function buildSections() {
    sectionModel.clear()
    if (!brightnessAvailable) return
    sectionModel.append({ type: "brightness" })
  }

  onBrightnessAvailableChanged: buildSections()

  Component.onCompleted: refresh()
  Timer {
    interval: 5000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  content: Item {
    anchors.fill: parent
    clip: true

    ListView {
      anchors.fill: parent
      model: sectionModel
      spacing: 12
      delegate: Component {
        Item {
          width: parent.width
          height: type === "brightness" ? 80 : 0

          visible: type === "brightness"

          Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 12

            Label {
              text: "Keyboard"
              font.pixelSize: 14
              color: Style.colors.foreground
            }

            Slider {
              id: brightnessSlider
              from: 0
              to: 100
              value: root.brightnessPercent
              live: true
              implicitHeight: 20
              width: Math.min(200, parent.width - 100)

              onMoved: {
                root.brightnessPercent = Model.clampBrightness(value)
                brightnessDebounce.restart()
              }

              onPressedChanged: {
                if (!pressed && brightnessDebounce.running) {
                  brightnessDebounce.stop()
                  root.setBrightness(root.brightnessPercent)
                }
              }
            }

            Label {
              text: Math.round(brightnessSlider.dragging ? brightnessSlider.liveValue : root.brightnessPercent) + "%"
              font.pixelSize: 14
              color: Style.colors.foreground
            }
          }
        }
      }
    }
  }
}
