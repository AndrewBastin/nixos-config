import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import "../singletons"
import "../components" as Components

// HACK: The implementation here is a pretty hacky one.
// The way this is implemented is that, we render the `nm-applet` systray applet here and override its icons
// Click events also get directed to its menu.

Repeater {
    model: ScriptModel {
      values: SystemTray.items.values.filter((x) => x.id === "nm-applet")
    }

    MouseArea {
      implicitWidth: child.implicitWidth
      implicitHeight: child.implicitHeight

      cursorShape: Qt.PointingHandCursor
      hoverEnabled: true

      required property SystemTrayItem modelData

    Text {
        id: child
        anchors.centerIn: parent

        // Maps an nm-applet StatusNotifierItem icon name to a Nerd Font glyph.
        // In app-indicator (SNI) mode — which is what this systray reads — nm-applet
        // only ever emits the names handled below:
        //   - nm-signal-{00,25,50,75,100}   Wi-Fi *and* mobile-broadband quality
        //   - nm-device-{wired,wireless,wwan}  per-device fallback when quality is unknown
        //   - nm-stageNN-connectingNN / nm-vpn-connectingNN  connecting animations
        //   - nm-vpn-active-lock            VPN active (non-indicator builds)
        //   - "<base>-secure"               VPN active, appended to the base icon in
        //                                   indicator mode (e.g. nm-signal-100-secure)
        //   - nm-no-connection              nothing connected / fallback
        // nm-tech-*, nm-wwan-tower and nm-mb-roam are pixbuf-composite-only in the
        // applet and never surface as an SNI icon name, so they need no handling here.

        // The VPN lock badge shown alongside the connection glyph while a VPN is up.
	// The left space in the badge is intentional
        readonly property string vpnBadge: "  󰦝"

        // Resolves a base (non-VPN) icon name to its connection glyph.
        function baseGlyph(icon) {
          // Wi-Fi / mobile-broadband signal quality (shared icons)
          if (icon.endsWith("nm-signal-100")) return "󰣺"
          if (icon.endsWith("nm-signal-75")) return "󰣸"
          if (icon.endsWith("nm-signal-50")) return "󰣶"
          if (icon.endsWith("nm-signal-25")) return "󰣴"
          if (icon.endsWith("nm-signal-00")) return "󰣾"

          // Per-device fallback when signal quality is unavailable
          if (icon.endsWith("nm-device-wireless")) return "󰖩"
          if (icon.endsWith("nm-device-wired")) return "󰈀"
          if (icon.endsWith("nm-device-wwan")) return "󰢽"

          // Connecting animations (device: nm-stageNN-connectingNN, vpn: nm-vpn-connectingNN)
          if (icon.includes("nm-stage") || icon.includes("nm-vpn-connecting")) return "󰇘"

          if (icon.endsWith("nm-no-connection")) return "󰌙"

          return icon
        }

        function nmGlyph(raw) {
          // VPN-active appends "-secure" to whatever the base icon was; show the
          // underlying connection glyph *and* a VPN lock badge next to it.
          if (raw.endsWith("-secure")) return baseGlyph(raw.slice(0, -7)) + vpnBadge

          // VPN active as a standalone lock (non-indicator builds have no base here)
          if (raw.includes("nm-vpn-active-lock")) return vpnBadge

          return baseGlyph(raw)
        }

        text: nmGlyph(parent.modelData.icon)
        color: Theme.barTextColor
        font.pointSize: Theme.statusIconsFontSize
        
        Components.Tooltip {
          text: NetworkStatus.status
        }
      }

      acceptedButtons: Qt.LeftButton

      onClicked: (mouse) => {
        // NOTE: We are straight on only using the menu implementation rather than activates
        // since nm-applet only supports the menu and since this systray is specifically only for nm-applet,
        // this onClicked behavior shouldn't be generalized for the rest

        // Mouse points are relative to the mouse area
        const {x, y} = this.mapToGlobal(mouse.x + Theme.systrayMenuOffsetX, mouse.y + Theme.systrayMenuOffsetY)

        modelData.display(rootWindow, x, y)
      }
    }
}
