pragma Singleton
import QtQuick
import Quickshell

QtObject {
  id: root
  
  property var currentWindow: null
  property string currentText: ""
  property var currentItem: null
  property bool visible: false
  
  function show(item, text, window) {
    currentItem = item
    currentText = text
    currentWindow = window
    visible = true
  }
  
  function hide() {
    visible = false
    currentItem = null
    currentText = ""
  }
}
