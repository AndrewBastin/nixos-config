import QtQuick
import Quickshell.Services.Pipewire
import "../singletons"
import "../components" as Components

// NOTE: Pipewire actually has data about whether the device is a bluetooth device or a headphone/headset
// and stuff, but the `defaultAudioSink` returns a Pipewire Node instead of a Pipewire Device with no built in
// API to track this info.
//
// TODO: We should probably look into integrating with `pw-cli`'s `-m` flag to monitor the situations and adapt flags

Text {
  property PwNode sink: Pipewire.defaultAudioSink

  text: {
    const vol = Math.ceil(sink.audio.volume * 100)

    const bluetoothSuffix = Object.keys(sink.properties).filter((x) => x.includes("bluez")).length > 0
    ? "  "
    : ""
    
    if (sink.audio.muted) return `󰝟${bluetoothSuffix}`
    if (vol === 0) return `${bluetoothSuffix}`
    if (vol <= 50) return `${bluetoothSuffix}`

    return `${bluetoothSuffix}`
  }
  color: Theme.barTextColor
  font.pointSize: Theme.statusIconsFontSize

  Components.Tooltip {
    text: {
      const vol = Math.ceil(sink.audio.volume * 100)
      const deviceName = sink.properties["node.description"] || sink.properties["node.name"] || "Audio Device"
      
      if (sink.audio.muted) {
        return `${deviceName} - Muted`
      }
      return `${deviceName} - ${vol}%`
    }
  }

  PwObjectTracker {
    objects: [sink]
  }
}
