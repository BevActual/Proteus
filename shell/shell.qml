import Quickshell
import QtQuick
import "surfaces"

ShellRoot {
  // Override with: PROTEUS_SURFACE=phone ./scripts/run-desktop.sh
  // Later: auto-detect from form factor / session.
  readonly property string surface: {
    const e = Quickshell.env("PROTEUS_SURFACE")
    return (e && e.length) ? e : "desktop"
  }

  Loader {
    active: true
    sourceComponent: {
      switch (surface) {
      case "phone":
        return phoneComp
      case "vr":
        return vrComp
      case "couch":
        return couchComp
      case "watch":
        return watchComp
      default:
        return desktopComp
      }
    }
  }

  Component { id: desktopComp; DesktopShell {} }
  Component { id: phoneComp; PhoneShell {} }
  Component { id: vrComp; VrShell {} }
  Component { id: couchComp; CouchShell {} }
  Component { id: watchComp; WatchShell {} }
}
