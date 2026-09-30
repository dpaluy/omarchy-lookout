// Plain node, no dependencies: `tests/run` runs this.
var assert = require("assert")
var M = require("../Model.js")

var failures = 0
function test(name, fn) {
  try {
    fn()
  } catch (e) {
    failures++
    console.error("FAIL " + name + "\n  " + e.message)
  }
}

var MIN = 60000
var cfg = M.config({ intervalMin: 20, breakSec: 45, idleSec: 60 })
var T0 = 1000000

// Ticks every 30 s; a longer gap counts as sleep.
function dueAt20() {
  var s = M.init(T0, cfg)
  for (var t = T0; t <= T0 + 20 * MIN; t += 30000) s = M.tick(s, t, cfg)
  return s
}

test("config falls back and clamps", function() {
  var c = M.config({ intervalMin: "abc", breakSec: 0, idleSec: 1 })
  assert.strictEqual(c.intervalMs, 45 * MIN)
  assert.strictEqual(c.breakMs, 45000)
  assert.strictEqual(c.idleSec, 10)
  assert.strictEqual(M.config(null).breakMs, 45000)
})

test("working becomes due when the interval ends", function() {
  var s = M.init(T0, cfg)
  s = M.tick(s, T0 + 1000, cfg)
  assert.strictEqual(s.phase, "working")
  assert.strictEqual(M.remaining(s, T0 + 1000), 20 * MIN - 1000)
  for (var t = T0 + 1000; t <= T0 + 20 * MIN; t += 1000) s = M.tick(s, t, cfg)
  assert.strictEqual(s.phase, "due")
})

test("due without a call starts the break, which ends and resets", function() {
  var s = M.init(T0, cfg)
  s.phase = "due"
  s = M.probed(s, T0, cfg, false)
  assert.strictEqual(s.phase, "break")
  assert.strictEqual(M.remaining(s, T0 + 5000), 40000)
  s = M.tick(s, T0 + 45000, cfg)
  assert.strictEqual(s.phase, "working")
  assert.strictEqual(s.lastBreakAt, T0 + 45000)
  assert.strictEqual(M.remaining(s, T0 + 45000), 20 * MIN)
})

test("the countdown runs while busy", function() {
  var s = M.init(T0, cfg)
  assert.strictEqual(M.probed(s, T0 + MIN, cfg, true), s)
  s = dueAt20()
  assert.strictEqual(s.phase, "due")
})

test("a due break waits while busy and starts when not busy", function() {
  var s = dueAt20()
  assert.strictEqual(M.probed(s, T0 + 20 * MIN, cfg, true), s)
  assert.strictEqual(M.remaining(s, T0 + 25 * MIN), 0)
  s = M.probed(s, T0 + 30 * MIN, cfg, false)
  assert.strictEqual(s.phase, "break")
})

test("default interval is 45 minutes", function() {
  assert.strictEqual(M.config({}).intervalMs, 45 * MIN)
})

test("a minute without input counts as a break", function() {
  var s = M.init(T0, cfg)
  s = M.idleStart(s, T0 + 5 * MIN)
  assert.strictEqual(s.phase, "idle")
  s = M.idleEnd(s, T0 + 5 * MIN + 1000, cfg)
  assert.strictEqual(s.phase, "working")
  assert.strictEqual(s.lastBreakAt, T0 + 5 * MIN + 1000)
  assert.strictEqual(M.remaining(s, T0 + 5 * MIN + 1000), 20 * MIN)
  assert.strictEqual(M.focusMs(s, T0 + 6 * MIN + 1000), MIN)
})

test("idle while a break waits also counts as a break", function() {
  var s = M.init(T0, cfg)
  s.phase = "due"
  s = M.idleEnd(M.idleStart(s, T0), T0 + 2 * MIN, cfg)
  assert.strictEqual(s.phase, "working")
  assert.strictEqual(s.lastBreakAt, T0 + 2 * MIN)
})

test("pause freezes the countdown and resume continues it", function() {
  var s = M.pause(M.init(T0, cfg), T0 + 5 * MIN, cfg)
  assert.strictEqual(s.phase, "paused")
  s = M.tick(s, T0 + 60 * MIN, cfg)
  assert.strictEqual(s.phase, "paused")
  assert.strictEqual(M.remaining(s, T0 + 60 * MIN), 15 * MIN)
  s = M.resume(s, T0 + 60 * MIN)
  assert.strictEqual(s.phase, "working")
  assert.strictEqual(M.remaining(s, T0 + 60 * MIN), 15 * MIN)
})

test("idle does not end a pause", function() {
  var s = M.pause(M.init(T0, cfg), T0, cfg)
  assert.strictEqual(M.idleStart(s, T0 + MIN).phase, "paused")
  assert.strictEqual(M.idleEnd(s, T0 + 2 * MIN, cfg).phase, "paused")
})

test("pause does not end a break; resume from zero is due", function() {
  var b = M.startBreak(M.init(T0, cfg), T0, cfg)
  assert.strictEqual(M.pause(b, T0, cfg).phase, "break")
  var d = M.init(T0, cfg)
  d.phase = "due"
  assert.strictEqual(M.resume(M.pause(d, T0, cfg), T0 + MIN).phase, "due")
})

test("idle does not interrupt a break", function() {
  var s = M.startBreak(M.init(T0, cfg), T0, cfg)
  assert.strictEqual(M.idleStart(s, T0 + 1000).phase, "break")
})

test("a sleep gap counts as a break", function() {
  var s = M.init(T0, cfg)
  s = M.tick(s, T0 + 10 * MIN, cfg)
  assert.strictEqual(s.phase, "working")
  assert.strictEqual(s.lastBreakAt, T0 + 10 * MIN)
  assert.strictEqual(M.remaining(s, T0 + 10 * MIN), 20 * MIN)
})

test("skip ends the break without recording it", function() {
  var s = M.startBreak(M.init(T0, cfg), T0, cfg)
  s = M.skip(s, T0 + 3000, cfg)
  assert.strictEqual(s.phase, "working")
  assert.strictEqual(s.lastBreakAt, 0)
  assert.strictEqual(M.remaining(s, T0 + 3000), 20 * MIN)
  assert.strictEqual(M.skip(s, T0, cfg), s)
})

test("postpone adds to the countdown or restarts it", function() {
  var s = M.init(T0, cfg)
  assert.strictEqual(M.remaining(M.postpone(s, T0, 5), T0), 25 * MIN)
  var b = M.postpone(M.startBreak(s, T0, cfg), T0 + 1000, 5)
  assert.strictEqual(b.phase, "working")
  assert.strictEqual(M.remaining(b, T0 + 1000), 5 * MIN)
  var p = M.postpone(M.pause(s, T0, cfg), T0, 1)
  assert.strictEqual(p.phase, "paused")
  assert.strictEqual(M.remaining(p, T0), 21 * MIN)
})

test("a changed interval moves the countdown", function() {
  var s = M.init(T0, cfg)
  assert.strictEqual(M.remaining(M.retime(s, T0 + MIN, -10 * MIN), T0 + MIN), 9 * MIN)
  assert.strictEqual(M.remaining(M.retime(s, T0 + 15 * MIN, -10 * MIN), T0 + 15 * MIN), 0)
  var p = M.retime(M.pause(s, T0, cfg), T0, 5 * MIN)
  assert.strictEqual(M.remaining(p, T0), 25 * MIN)
})

test("focus time runs from the last break", function() {
  var s = M.init(T0, cfg)
  assert.strictEqual(M.focusMs(s, T0 + 7 * MIN), 7 * MIN)
})

test("formats", function() {
  assert.strictEqual(M.clock(43 * MIN + 51000), "43:51")
  assert.strictEqual(M.clock(65 * MIN), "1:05:00")
  assert.strictEqual(M.clock(44500), "0:45")
  assert.strictEqual(M.short(43 * MIN + 1000), "44m")
  assert.strictEqual(M.short(30000), "30s")
  assert.strictEqual(M.short(65 * MIN), "1h 5m")
  assert.strictEqual(M.duration(45000), "45 sec")
  assert.strictEqual(M.duration(MIN), "1 min")
})

function probe(outputs, sources, cams) {
  return JSON.stringify(outputs) + "\n" + M.PROBE_SEPARATOR +
    JSON.stringify(sources) + "\n" + M.PROBE_SEPARATOR + (cams || "")
}
var SOURCES = [{ index: 58, name: "alsa_output.x.analog-stereo.monitor" }, { index: 59, name: "alsa_input.x.analog-stereo" }]
function out(source, name, binary, corked) {
  return { source: source, corked: !!corked, properties: { "application.name": name, "application.process.binary": binary } }
}

test("probe: nothing recording is not a call", function() {
  assert.deepStrictEqual(M.parseProbe(probe([], SOURCES), ""), { inCall: false, apps: [] })
})

test("probe: a microphone recording is a call", function() {
  var r = M.parseProbe(probe([out(59, "Chromium", "chromium")], SOURCES), "")
  assert.deepStrictEqual(r, { inCall: true, apps: ["Chromium"] })
})

test("probe: monitor, corked, and ignored recordings are not calls", function() {
  var r = M.parseProbe(probe([out(58, "Chromium", "chromium"), out(59, "Zoom", "zoom", true),
                              out(59, "cava", "cava")], SOURCES), "cava")
  assert.strictEqual(r.inCall, false)
})

test("probe: a camera in use is a call, the camera services are not", function() {
  assert.strictEqual(M.parseProbe(probe([], SOURCES, "pipewire\nwireplumber\n"), "").inCall, false)
  assert.deepStrictEqual(M.parseProbe(probe([], SOURCES, "pipewire\nfirefox\n"), "").apps, ["firefox"])
})

test("probe: broken output is not a call", function() {
  assert.strictEqual(M.parseProbe("", "").inCall, false)
  assert.strictEqual(M.parseProbe("garbage", "").inCall, false)
})

test("video: only playing browsers and video players count", function() {
  var chrome = { identity: "Google Chrome", dbusName: "org.mpris.MediaPlayer2.chromium.instance1986", isPlaying: true }
  var mpv = { identity: "mpv", desktopEntry: "mpv", isPlaying: true }
  var spotify = { identity: "Spotify", desktopEntry: "spotify", dbusName: "org.mpris.MediaPlayer2.spotify", isPlaying: true }
  assert.strictEqual(M.videoPlaying([chrome]), true)
  assert.strictEqual(M.videoPlaying([mpv]), true)
  assert.strictEqual(M.videoPlaying([spotify]), false)
  assert.strictEqual(M.videoPlaying([{ identity: "Google Chrome", isPlaying: false }]), false)
  assert.strictEqual(M.videoPlaying([]), false)
  assert.strictEqual(M.videoPlaying(null), false)
})

if (failures) {
  console.error(failures + " failed")
  process.exit(1)
}
console.log("model tests passed")
