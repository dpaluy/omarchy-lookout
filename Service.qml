import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Wayland
import "Model.js" as Model

// One per shell. Owns the break schedule, the away detection, the busy
// check (call or video), and the break overlay. The bar widget only shows this state and
// calls start/skip/postpone.
//
// Settings live on the widget's entry in shell.json. Without the widget in
// the bar, the defaults apply.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string moduleName: "dpaluy.lookout"

  // The bar widget passes its live settings here. The shell refreshes a
  // service's barConfig only when plugins change, not when shell.json does.
  property var widgetSettings: null

  readonly property var widgetEntry: {
    if (root.widgetSettings) return root.widgetSettings
    var config = root.shell ? root.shell.barConfig : null
    var layout = config && config.layout ? config.layout : {}
    for (var section in layout) {
      var entries = Array.isArray(layout[section]) ? layout[section] : []
      for (var i = 0; i < entries.length; i++)
        if (entries[i] && entries[i].id === root.moduleName) return entries[i]
    }
    return null
  }

  function setting(key, fallback) {
    var v = root.widgetEntry ? root.widgetEntry[key] : undefined
    return v === undefined || v === null ? fallback : v
  }

  readonly property var cfg: Model.config(root.widgetEntry || {})
  readonly property bool waitWhenBusy: setting("waitWhenBusy", true) !== false
  readonly property bool allowSkip: setting("allowSkip", true) !== false
  readonly property string ignoredApps: String(setting("ignoredApps", "cava,easyeffects"))

  // Starts from the default interval and is not bound to cfg; the settings
  // may arrive later, and syncInterval moves the countdown to them.
  property var state: Model.init(Date.now(), Model.config({}))
  property double now: Date.now()
  property var callApps: []

  readonly property bool videoPlaying: Model.videoPlaying(Mpris.players ? Mpris.players.values : [])
  readonly property bool inCall: root.callApps.length > 0
  // A due break waits while you are in a call or a video plays.
  readonly property bool waiting: root.phase === "due" && root.waitWhenBusy && (root.inCall || root.videoPlaying)

  readonly property string phase: state.phase
  readonly property double remainingMs: Model.remaining(state, now)
  readonly property double focusMs: Model.focusMs(state, now)
  readonly property double lastBreakAt: state.lastBreakAt
  readonly property double breakMs: cfg.breakMs
  readonly property double intervalMs: cfg.intervalMs

  function apply(next) {
    if (next !== root.state) root.state = next
  }

  function startBreak() { root.now = Date.now(); apply(Model.startBreak(root.state, root.now, root.cfg)) }
  function skip() { root.now = Date.now(); apply(Model.skip(root.state, root.now, root.cfg)) }
  function postpone(minutes) { root.now = Date.now(); apply(Model.postpone(root.state, root.now, minutes)) }
  function pause() { root.now = Date.now(); apply(Model.pause(root.state, root.now, root.cfg)) }
  function resume() { root.now = Date.now(); apply(Model.resume(root.state, root.now)) }
  function togglePause() { root.phase === "paused" ? resume() : pause() }

  // A changed interval moves the running countdown by the difference.
  property double appliedIntervalMs: Model.config({}).intervalMs
  function syncInterval() {
    if (root.intervalMs === root.appliedIntervalMs) return
    root.now = Date.now()
    apply(Model.retime(root.state, root.now, root.intervalMs - root.appliedIntervalMs))
    root.appliedIntervalMs = root.intervalMs
  }
  onIntervalMsChanged: syncInterval()
  Component.onCompleted: syncInterval()

  // A video that stops can start a waiting break, or make you idle.
  onVideoPlayingChanged: if (root.phase === "due" || idleMonitor.isIdle) root.probe()

  onPhaseChanged: {
    if (root.phase === "due") root.probe()
    else root.callApps = []
  }

  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: {
      root.now = Date.now()
      root.apply(Model.tick(root.state, root.now, root.cfg))
    }
  }

  // While a break waits, checks again until the call ends.
  Timer {
    interval: 15000
    running: root.phase === "due"
    repeat: true
    onTriggered: root.probe()
  }

  IdleMonitor {
    id: idleMonitor
    enabled: root.shell !== null
    timeout: root.cfg.idleSec
    // Video players inhibit idle, so watching is not a break.
    respectInhibitors: true
    onIsIdleChanged: {
      root.now = Date.now()
      if (isIdle) root.probe()
      else root.apply(Model.idleEnd(root.state, root.now, root.cfg))
    }
  }

  property bool probeAgain: false

  function probe() {
    if (!root.waitWhenBusy) {
      root.probed({ inCall: false, apps: [] })
      return
    }
    if (probeProc.running) {
      root.probeAgain = true
      return
    }
    probeProc.running = true
  }

  function probed(result) {
    root.now = Date.now()
    var busy = root.waitWhenBusy && (result.inCall || root.videoPlaying)
    // Time without input during a call or a video is not a break.
    if (idleMonitor.isIdle && !busy)
      apply(Model.idleStart(root.state, root.now))
    apply(Model.probed(root.state, root.now, root.cfg, busy))
    root.callApps = root.phase === "due" ? result.apps : []
  }

  Process {
    id: probeProc
    command: Model.probeCommand()
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.probed(Model.parseProbe(text, root.ignoredApps))
    }
    onExited: {
      if (!root.probeAgain) return
      root.probeAgain = false
      Qt.callLater(root.probe)
    }
  }

  BreakOverlay {
    service: root
  }

  IpcHandler {
    target: "lookout"

    function start(): void { root.startBreak() }
    function skip(): void { root.skip() }
    function postpone(minutes: int): void { root.postpone(minutes) }
    function pause(): void { root.pause() }
    function resume(): void { root.resume() }
    function toggle(): void { root.togglePause() }
    function status(): string {
      return JSON.stringify({
        phase: root.phase,
        remainingSec: Math.ceil(root.remainingMs / 1000),
        focusSec: Math.floor(root.focusMs / 1000),
        inCall: root.inCall,
        videoPlaying: root.videoPlaying,
        lastBreakAt: root.lastBreakAt ? new Date(root.lastBreakAt).toISOString() : null,
        callApps: root.callApps
      })
    }
  }
}
