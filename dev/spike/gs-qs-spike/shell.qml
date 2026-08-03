import Quickshell
import Quickshell.Io
import QtQuick

// Gamescope-as-session spike — prove Quickshell runs as a plain xdg client
// under gamescope: window maps, Process facts work, IPC reachable.
ShellRoot {
  id: root

  property string kernel: ""
  property bool windowMapped: false

  FloatingWindow {
    id: win
    title: "proteus-gs-qs-spike"
    implicitWidth: 1280
    implicitHeight: 720
    color: "#101418"

    onVisibleChanged: if (visible) root.windowMapped = true
    Component.onCompleted: if (visible) root.windowMapped = true

    Column {
      anchors.centerIn: parent
      spacing: 12

      Text {
        text: "Proteus GS spike"
        color: "#e8eaed"
        font.pixelSize: 42
        font.weight: Font.Bold
      }
      Text {
        text: root.kernel.length ? ("Process OK · " + root.kernel) : "Process pending…"
        color: root.kernel.length ? "#7fd68a" : "#c9a25e"
        font.pixelSize: 24
      }
      Text {
        text: "IPC target: spike · fn: status"
        color: "#9aa0a6"
        font.pixelSize: 18
      }
    }
  }

  Process {
    id: unameProc
    running: true
    command: ["uname", "-r"]
    stdout: StdioCollector {
      onStreamFinished: root.kernel = String(text || "").trim()
    }
  }

  IpcHandler {
    target: "spike"

    function status(): string {
      return JSON.stringify({
        mapped: root.windowMapped,
        processOk: root.kernel.length > 0,
        kernel: root.kernel,
        waylandDisplay: Quickshell.env("WAYLAND_DISPLAY") || "",
        x11Display: Quickshell.env("DISPLAY") || ""
      })
    }
  }
}
