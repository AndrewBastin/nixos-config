pragma Singleton

import Quickshell
import QtQuick

Singleton {
  property string barBgColor: "#161616"
  property string barTextColor: "#d8d8d8"
  property string barAccentColor: "#285577"

  property int barSeparatorWidth: 1
  property int barSeparatorHeight: 18
  property string barSeparatorColor: "#565656"

  property int systrayMenuOffsetX: 0
  property int systrayMenuOffsetY: 15

  property int statusIconsFontSize: 10
  property int statusIconsSpacing: 11

  // The number of characters in the current window title after 
  // which the title is ellipsized.
  property int windowTitleCharsLimit: 120
}
