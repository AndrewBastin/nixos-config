pragma Singleton

import Quickshell
import QtQuick

Singleton {
  readonly property bool enabled: Quickshell.env("ANDREW_SHELL_VM_MODE") === "1"
}
