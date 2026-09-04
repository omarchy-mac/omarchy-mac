import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Headless service: the compositor's idle notifier drives `idle` / `active`,
// and a timer runs `tick` for the ambient light sensor. All the policy lives
// in omarchy-brightness-keyboard-auto so it can also run without the shell.
// On hardware without an ambient light sensor or kbd_backlight LED the probe
// fails and the service stays inert.
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool supported: false
  property int idleSeconds: 10
  property int pollMs: 2000

  function run(action) {
    if (!root.supported) return
    if (action === "tick") {
      if (tickProc.running || idleProc.running) return
      tickProc.command = ["omarchy-brightness-keyboard-auto", "tick"]
      tickProc.running = true
    } else {
      idleProc.command = ["omarchy-brightness-keyboard-auto", action]
      idleProc.running = true
    }
  }

  Component.onCompleted: probeProc.running = true

  Process {
    id: probeProc
    command: ["omarchy-brightness-keyboard-auto", "probe"]
    onExited: function(exitCode) {
      root.supported = (exitCode === 0)
      if (root.supported) {
        console.log("keyboard-backlight: ambient light sensor and LED found, enabling")
        configProc.running = true
        root.run("active")
      } else {
        console.log("keyboard-backlight: no ambient light sensor or keyboard backlight, staying inert")
      }
    }
  }

  // IDLE_SECONDS from ~/.config/omarchy/keyboard-backlight.conf.
  Process {
    id: configProc
    command: ["bash", "-c", "source \"$HOME/.config/omarchy/keyboard-backlight.conf\" 2>/dev/null; echo \"${IDLE_SECONDS:-10}\""]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var n = parseInt(text, 10)
        if (!isNaN(n) && n > 0) root.idleSeconds = n
      }
    }
  }

  Process { id: tickProc }
  Process { id: idleProc }

  IdleMonitor {
    enabled: root.supported
    timeout: root.idleSeconds
    respectInhibitors: false
    onIsIdleChanged: root.run(isIdle ? "idle" : "active")
  }

  Timer {
    interval: root.pollMs
    running: root.supported
    repeat: true
    onTriggered: root.run("tick")
  }
}
