import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar pill with the time to the next break, and a popup to start or
// postpone it. All state lives in the service; there is one widget per bar.
Panel {
  id: root
  moduleName: "dpaluy.lookout"
  ipcTarget: "dpaluy.lookout"

  readonly property var service: root.bar && root.bar.shell && typeof root.bar.shell.serviceFor === "function"
    ? root.bar.shell.serviceFor(root.moduleName) : null
  readonly property string phase: service ? service.phase : "off"
  readonly property double remainingMs: service ? service.remainingMs : 0
  readonly property bool waiting: service ? service.waiting : false
  readonly property bool inCall: service ? service.inCall : false
  readonly property color fg: root.bar ? root.bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(fg, 1.4)
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family

  readonly property string icon: {
    if (phase === "idle") return "\u{F0209}"
    if (waiting && inCall) return "\u{F03F2}"
    if (phase === "paused") return "\u{F03E4}"
    return "\u{F0208}"
  }

  readonly property string pillText: {
    if (!service) return icon
    if (phase === "idle") return icon + " Idle"
    if (phase === "paused") return icon + " Paused"
    if (phase === "due") return icon + (waiting ? " Wait" : " Now")
    return icon + " " + Model.short(remainingMs)
  }

  readonly property string headline: {
    if (phase === "idle") return "Away: counts as a break"
    if (phase === "paused") return "LookOut is paused"
    if (phase === "break") return "Break ends in"
    if (waiting) return inCall ? "Break after the call" : "Break after the video"
    return "Break starts in"
  }

  readonly property string bigText: {
    if (phase === "idle") return "Idle"
    if (waiting) return "Wait"
    return Model.clock(remainingMs)
  }

  property bool showingSettings: false
  onOpenedChanged: if (!root.opened) root.showingSettings = false

  // Writes one setting to the widget's entry in shell.json. Applied here
  // first, so the service and the popup change at once.
  function saveSetting(key, value) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    entry[key] = value
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  Binding {
    target: root.service
    property: "widgetSettings"
    value: root.settings
    when: root.service !== null
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.pillText
    tooltipText: ""
    fontSize: 12
    horizontalMargin: 7.5
    verticalPadding: 6
    onPressed: function(mouseButton) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened && root.service !== null
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(root.showingSettings ? settingsView.implicitHeight : column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      SettingsView {
        id: settingsView
        visible: root.showingSettings
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        service: root.service
        foreground: root.fg
        fontFamily: root.fontFamily
        onSave: function(key, value) { root.saveSetting(key, value) }
        onClosed: root.showingSettings = false
      }

      Column {
        id: column
        visible: !root.showingSettings
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        Row {
          spacing: Style.space(12)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.icon
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.displayLarge
          }

          Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              textFormat: Text.PlainText
              text: root.headline
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            Text {
              textFormat: Text.PlainText
              text: root.bigText
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
              font.bold: true
            }
          }
        }

        Text {
          width: parent.width
          visible: root.waiting && root.inCall
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: "In a call: " + (root.service ? root.service.callApps.join(", ") : "")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Row {
          id: actions
          width: parent.width
          spacing: Style.space(6)

          readonly property real smallWidth: (width - spacing * 3) / 5

          Button {
            width: actions.smallWidth * 2
            text: root.phase === "break" ? "Skip break" : "Start break"
            enabled: root.phase !== "break" || (root.service && root.service.allowSkip)
            fontSize: Style.font.bodySmall
            foreground: root.fg
            fontFamily: root.fontFamily
            bordered: true
            onClicked: {
              if (root.phase === "break") root.service.skip()
              else root.service.startBreak()
              root.close()
            }
          }

          Repeater {
            model: [1, 5, 15]
            Button {
              required property var modelData
              width: actions.smallWidth
              text: "+" + modelData + "m"
              fontSize: Style.font.bodySmall
              foreground: root.fg
              fontFamily: root.fontFamily
              bordered: true
              onClicked: root.service.postpone(modelData)
            }
          }
        }

        Row {
          id: controls
          width: parent.width
          spacing: Style.space(6)

          Button {
            width: controls.width - settingsButton.width - controls.spacing
            text: root.phase === "paused" ? "Resume" : "Pause LookOut"
            iconText: root.phase === "paused" ? "\u{F040A}" : "\u{F03E4}"
            enabled: root.phase !== "break"
            fontSize: Style.font.bodySmall
            foreground: root.fg
            fontFamily: root.fontFamily
            bordered: true
            onClicked: root.service.togglePause()
          }

          Button {
            id: settingsButton
            width: actions.smallWidth * 2
            text: "Settings"
            iconText: "\u{F0493}"
            fontSize: Style.font.bodySmall
            foreground: root.fg
            fontFamily: root.fontFamily
            bordered: true
            onClicked: root.showingSettings = true
          }
        }

        PanelSeparator { foreground: root.fg }

        InfoRow {
          label: "Current focus time"
          value: root.service ? Model.short(root.service.focusMs) : ""
        }
        InfoRow {
          label: "Last break"
          value: root.service && root.service.lastBreakAt > 0
            ? Model.short(root.service.now - root.service.lastBreakAt) + " ago" : "None yet"
        }
        InfoRow {
          label: "Upcoming break"
          value: root.service ? Model.duration(root.service.breakMs) : ""
        }
      }
    }
  }

  component InfoRow: Item {
    property string label: ""
    property string value: ""
    width: parent ? parent.width : 0
    implicitHeight: labelText.implicitHeight

    Text {
      id: labelText
      anchors.left: parent.left
      textFormat: Text.PlainText
      text: parent.label
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    Text {
      anchors.right: parent.right
      textFormat: Text.PlainText
      text: parent.value
      color: root.fg
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }
  }
}
