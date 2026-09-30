import QtQuick
import qs.Commons
import qs.Ui

// LookOut's settings, inside the popup. Omarchy keeps a widget's schema but
// draws no settings screen for it, so they are set here. Every change goes
// to the widget's entry in shell.json at once.
FocusScope {
  id: root

  property var service: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  signal save(string key, var value)
  signal closed()

  function value(key, fallback) {
    var entry = root.service ? root.service.widgetEntry : null
    var v = entry ? entry[key] : undefined
    return v === undefined || v === null ? fallback : v
  }

  implicitHeight: settingsColumn.implicitHeight

  component Note: Text {
    width: parent ? parent.width : 0
    textFormat: Text.PlainText
    wrapMode: Text.Wrap
    color: Qt.darker(root.foreground, 1.8)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }

  Column {
    id: settingsColumn
    width: parent.width
    spacing: Style.space(10)

    Item {
      width: parent.width
      height: doneButton.implicitHeight

      Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "SETTINGS"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
        font.letterSpacing: 1
      }

      Button {
        id: doneButton
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: "Done"
        bordered: true
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        onClicked: root.closed()
      }
    }

    Row {
      spacing: Style.space(10)

      NumberField {
        label: "Minutes between breaks"
        value: root.service ? Math.round(root.service.intervalMs / 60000) : 45
        from: 1
        to: 240
        stepSize: 5
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        onModified: function(v) { root.save("intervalMin", v) }
      }

      NumberField {
        label: "Break length (sec)"
        value: root.service ? Math.round(root.service.breakMs / 1000) : 45
        from: 5
        to: 1800
        stepSize: 15
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        onModified: function(v) { root.save("breakSec", v) }
      }
    }

    NumberField {
      label: "Idle time that counts as a break (sec)"
      value: root.service ? root.service.cfg.idleSec : 60
      from: 10
      to: 3600
      stepSize: 10
      foreground: root.foreground
      fontFamily: root.fontFamily
      fontSize: Style.font.bodySmall
      onModified: function(v) { root.save("idleSec", v) }
    }

    Toggle {
      width: parent.width
      label: "Wait for calls and videos"
      description: "A break that comes due during a call or a playing video starts when it ends."
      checked: root.value("waitWhenBusy", true) !== false
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: root.save("waitWhenBusy", !checked)
    }

    Toggle {
      width: parent.width
      label: "Allow skipping a break"
      description: "Shows Skip and +5 min on the break screen. Esc skips."
      checked: root.value("allowSkip", true) !== false
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: root.save("allowSkip", !checked)
    }

    Text {
      textFormat: Text.PlainText
      text: "Apps that are not calls"
      color: Qt.darker(root.foreground, 1.4)
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    TextField {
      id: ignoredField
      width: parent.width
      text: String(root.value("ignoredApps", "cava,easyeffects"))
      placeholderText: "None"
      foreground: root.foreground
      font.family: root.fontFamily
      onEditingFinished: {
        var v = text.replace(/\s+/g, "")
        if (v !== String(root.value("ignoredApps", "cava,easyeffects"))) root.save("ignoredApps", v)
      }
    }

    Note {
      text: "Comma-separated names of apps that record audio but are not calls. Press Enter to save."
    }
  }
}
