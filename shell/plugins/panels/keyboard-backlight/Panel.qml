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

  function brightnessIpc(percent) {
    IpcHandler {
      id: ipc
      target: root.ipcTarget
      onCreate: {
        if (percent === "get") {
          var proc = Process {
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
          proc.start()
          proc.waitForExited()
        } else if (percent !== "") {
          var setProc = Process {
            command: ["omarchy-brightness-keyboard", "--no-osd", "set", String(Model.clampBrightness(Number(percent)))]
            onExited: (exitCode) => {
              root.brightnessSetQueued = false
              if (exitCode === 0) {
                root.brightnessPercent = Model.clampBrightness(Number(percent))
              }
            }
          }
          setProc.start()
        }
      }
      onMessage: (msg) => {
        if (msg && msg.brightness !== undefined) {
          root.brightnessAvailable = msg.brightnessAvailable
          root.brightnessPercent = Model.clampBrightness(msg.brightness)
        }
      }
    }
  }

  function setBrightness(percent) {
    if (!brightnessAvailable) return
    root.brightnessPercent = Model.clampBrightness(percent)
    root.brightnessSetQueued = true
    brightnessIpc(String(root.brightnessPercent))
  }

  function refresh() {
    brightnessIpc("get")
  }

  Component.onCompleted: refresh()
  Timer {
    interval: 5000
    running: true
    repeat: true
    onTriggered: root.refresh()
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
