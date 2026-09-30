import QtQuick
import Quickshell
import "plugin" as Plugin

// Loads the service, its break overlay, and the bar widget in a bare
// Quickshell, runs one real call probe, and walks the break flow.
ShellRoot {
  id: root

  QtObject {
    id: fakeShell
    property var barConfig: ({ layout: { right: [{ id: "dpaluy.lookout", intervalMin: 30, breakSec: 20 }] } })
    function serviceFor(id) { return id === "dpaluy.lookout" ? service : null }
    // The real shell does not refresh a service's barConfig on a settings write.
    property var written: null
    function updateEntryInline(id, entry) { written = entry }
  }

  Plugin.Service {
    id: service
    shell: fakeShell
  }

  // Gets its shell after it starts, as the real shell may do.
  Plugin.Service {
    id: lateService
  }

  Plugin.BarWidget {
    id: widget
    settings: ({ id: "dpaluy.lookout", intervalMin: 30, breakSec: 20 })
    bar: QtObject {
      property color foreground: "white"
      property color barForeground: "white"
      property color background: "black"
      property color urgent: "red"
      property bool foregroundAnimationEnabled: false
      property string fontFamily: "monospace"
      property string position: "top"
      property bool vertical: false
      property int barSize: 26
      property var shell: fakeShell
      function run(command) {}
    }
  }

  function check(ok, message) {
    if (!ok) throw new Error("LOOKOUT_QML_SMOKE_FAIL " + message)
  }

  Timer {
    interval: 200
    running: true
    onTriggered: {
      lateService.shell = fakeShell
      check(lateService.phase === "working" && Math.abs(lateService.remainingMs - 30 * 60000) < 2000,
            "late settings: " + lateService.phase + " " + lateService.remainingMs)
      check(service.intervalMs === 30 * 60000, "interval setting not read")
      check(service.breakMs === 20000, "break setting not read")
      check(widget.service === service, "widget did not find the service")
      check(widget.pillText.indexOf("30m") >= 0, "pill text: " + widget.pillText)
      service.postpone(5)
      check(widget.pillText.indexOf("35m") >= 0, "postpone: " + widget.pillText)
      service.pause()
      check(widget.pillText.indexOf("Paused") >= 0 && widget.bigText === "35:00", "pause: " + widget.pillText + " " + widget.bigText)
      service.resume()
      check(service.phase === "working", "resume: " + service.phase)
      service.probed({ inCall: true, apps: ["Zoom"] })
      check(service.phase === "working" && widget.pillText.indexOf("35m") >= 0, "call while working: " + service.phase + " " + widget.pillText)
      widget.showingSettings = true
      widget.saveSetting("intervalMin", 50)
      check(service.intervalMs === 50 * 60000 && service.breakMs === 20000, "settings save: " + service.intervalMs + " " + service.breakMs)
      check(fakeShell.written && fakeShell.written.intervalMin === 50 && fakeShell.written.breakSec === 20, "settings write: " + JSON.stringify(fakeShell.written))
      widget.saveSetting("allowSkip", false)
      check(!service.allowSkip && service.intervalMs === 50 * 60000, "settings toggle: " + service.allowSkip)
      widget.saveSetting("allowSkip", true)
      check(typeof service.videoPlaying === "boolean", "video state: " + service.videoPlaying)
      // The real probe that the due phase starts ends after these checks.
      service.state = Object.assign({}, service.state, { phase: "due" })
      service.probed({ inCall: true, apps: ["Zoom"] })
      check(service.phase === "due" && service.waiting && widget.pillText.indexOf("Wait") >= 0
            && widget.headline === "Break after the call", "call wait: " + service.phase + " " + widget.pillText)
      service.probed({ inCall: false, apps: [] })
      check(service.phase === (service.videoPlaying ? "due" : "break"), "call end: " + service.phase)
      service.skip()
      widget.saveSetting("waitWhenBusy", false)
      check(!service.waitWhenBusy, "busy setting: " + service.waitWhenBusy)
      widget.saveSetting("waitWhenBusy", true)
      service.probe()
      probeWait.start()
    }
  }

  Timer {
    id: probeWait
    interval: 1500
    onTriggered: {
      check(Array.isArray(service.callApps), "probe did not finish")
      service.startBreak()
      check(service.phase === "break" && widget.bigText === "0:20", "break: " + service.phase + " " + widget.bigText)
      service.skip()
      check(service.phase === "working", "skip: " + service.phase)
      console.log("LOOKOUT_QML_SMOKE_OK")
      Qt.quit()
    }
  }
}
