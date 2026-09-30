import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The break screen: one full-screen layer per monitor while the service is
// in the "break" phase. Keys and clicks go here, not to the apps below.
Item {
  id: root

  property var service: null

  readonly property bool active: !!service && service.phase === "break"
  readonly property bool allowSkip: !!service && service.allowSkip
  readonly property double remainingMs: service ? service.remainingMs : 0
  readonly property double breakMs: service ? service.breakMs : 1
  readonly property color foreground: Color.menu.text
  readonly property string fontFamily: Style.font.menuFamily

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: window
      required property var modelData
      screen: modelData
      visible: root.active
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      WlrLayershell.namespace: "lookout-break"
      WlrLayershell.layer: WlrLayer.Overlay
      // One surface takes the keyboard; the others only cover their screen.
      WlrLayershell.keyboardFocus: modelData === Quickshell.screens[0] ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore

      Rectangle {
        anchors.fill: parent
        color: Color.menu.background
        opacity: 0.94
      }

      MouseArea { anchors.fill: parent }

      Item {
        anchors.fill: parent
        focus: root.active
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape && root.allowSkip) root.service.skip()
          event.accepted = true
        }
      }

      Column {
        anchors.centerIn: parent
        width: Math.min(Style.space(420), window.width - Style.space(40))
        spacing: Style.space(18)

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          textFormat: Text.PlainText
          text: "\u{F0208}"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.displayLarge * 2
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          textFormat: Text.PlainText
          text: "Time to look out"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.displayLarge
          font.bold: true
        }

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: "Rest your eyes on something far away. Stretch, breathe, drink water."
          color: Qt.darker(root.foreground, 1.4)
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          textFormat: Text.PlainText
          text: Model.clock(root.remainingMs)
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.displayLarge * 2.5
          font.bold: true
        }

        Item {
          width: parent.width
          implicitHeight: Style.space(8)

          Rectangle {
            id: track
            anchors.fill: parent
            radius: height / 2
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
          }

          Rectangle {
            anchors.left: track.left
            height: track.height
            radius: track.radius
            color: Color.accent
            width: Math.max(track.height, track.width * (1 - root.remainingMs / Math.max(1, root.breakMs)))
            Behavior on width { NumberAnimation { duration: 900 } }
          }
        }

        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(10)
          visible: root.allowSkip

          Button {
            text: "+5 min"
            fontSize: Style.font.body
            foreground: root.foreground
            fontFamily: root.fontFamily
            bordered: true
            onClicked: root.service.postpone(5)
          }

          Button {
            text: "Skip (Esc)"
            fontSize: Style.font.body
            foreground: root.foreground
            fontFamily: root.fontFamily
            bordered: true
            onClicked: root.service.skip()
          }
        }
      }
    }
  }
}
