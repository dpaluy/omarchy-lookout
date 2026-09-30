// Break schedule as a pure state machine, plus the call probe parser.
// No Qt here, so node can test it (tests/run).
//
// Phases:
//   working  counting down to nextAt
//   idle     no input for idleSec; this counts as a break taken
//   due      the timer ran out; the break waits while you are busy
//   break    the overlay is up until breakEndsAt
//   paused   the user paused LookOut; the remaining time is frozen
//
// Every function takes the state and returns a new one. Times are ms.

function config(settings) {
  function num(key, fallback, min, max) {
    var v = Number(settings && settings[key])
    if (!isFinite(v) || v <= 0) v = fallback
    return Math.min(max, Math.max(min, v))
  }
  return {
    intervalMs: num("intervalMin", 45, 1, 240) * 60000,
    breakMs: num("breakSec", 45, 5, 1800) * 1000,
    idleSec: Math.round(num("idleSec", 60, 10, 3600))
  }
}

function copy(s, changes) {
  var out = {}
  for (var k in s) out[k] = s[k]
  for (var c in changes) out[c] = changes[c]
  return out
}

function init(now, cfg) {
  return {
    phase: "working",
    nextAt: now + cfg.intervalMs,
    remainingMs: 0,
    breakEndsAt: 0,
    lastBreakAt: 0,
    focusSince: now,
    lastTick: now
  }
}

// A rest: as if a break just ended.
function rested(s, now, cfg) {
  return copy(s, {
    phase: "working",
    nextAt: now + cfg.intervalMs,
    remainingMs: 0,
    breakEndsAt: 0,
    lastBreakAt: now,
    focusSince: now,
    lastTick: now
  })
}

var COUNTING = ["working", "due"]

function tick(s, now, cfg) {
  // A gap this long means the machine slept. That was a break.
  if (COUNTING.indexOf(s.phase) >= 0 && now - s.lastTick >= cfg.idleSec * 1000)
    return rested(s, now, cfg)
  if (s.phase === "working" && now >= s.nextAt)
    return copy(s, { phase: "due", lastTick: now })
  if (s.phase === "break" && now >= s.breakEndsAt)
    return rested(s, now, cfg)
  return copy(s, { lastTick: now })
}

// No input for idleSec. A pause or a break is not changed.
function idleStart(s, now) {
  if (COUNTING.indexOf(s.phase) < 0) return s
  return copy(s, { phase: "idle", lastTick: now })
}

// Back from idle: the time away was a break.
function idleEnd(s, now, cfg) {
  if (s.phase !== "idle") return s
  return rested(s, now, cfg)
}

// A due break starts when you are not busy (no call, no playing video).
function probed(s, now, cfg, busy) {
  if (s.phase !== "due" || busy) return s
  return startBreak(s, now, cfg)
}

function startBreak(s, now, cfg) {
  if (s.phase === "break") return s
  return copy(s, { phase: "break", breakEndsAt: now + cfg.breakMs, remainingMs: 0, lastTick: now })
}

function skip(s, now, cfg) {
  if (s.phase !== "break") return s
  return copy(s, { phase: "working", nextAt: now + cfg.intervalMs, breakEndsAt: 0, lastTick: now })
}

function pause(s, now, cfg) {
  if (s.phase === "paused" || s.phase === "break") return s
  var left = s.phase === "working" ? Math.max(0, s.nextAt - now)
    : s.phase === "idle" ? cfg.intervalMs : 0
  return copy(s, { phase: "paused", remainingMs: left, lastTick: now })
}

function resume(s, now) {
  if (s.phase !== "paused") return s
  return copy(s, {
    phase: s.remainingMs > 0 ? "working" : "due",
    nextAt: now + s.remainingMs,
    remainingMs: 0,
    lastTick: now
  })
}

// Adds minutes to the countdown. From a break or a due, the countdown
// starts again from now.
function postpone(s, now, minutes) {
  var ms = Math.max(0, Number(minutes) || 0) * 60000
  if (s.phase === "idle") return s
  if (s.phase === "paused") return copy(s, { remainingMs: s.remainingMs + ms })
  var base = s.phase === "working" ? Math.max(now, s.nextAt) : now
  return copy(s, { phase: "working", nextAt: base + ms, breakEndsAt: 0, lastTick: now })
}

// Moves the countdown by deltaMs, after the interval setting changed.
function retime(s, now, deltaMs) {
  if (!deltaMs) return s
  if (s.phase === "working") return copy(s, { nextAt: Math.max(now, s.nextAt + deltaMs) })
  if (s.phase === "paused") return copy(s, { remainingMs: Math.max(0, s.remainingMs + deltaMs) })
  return s
}

// ms until the next break (working/paused) or until the break ends (break).
function remaining(s, now) {
  if (s.phase === "working") return Math.max(0, s.nextAt - now)
  if (s.phase === "paused") return s.remainingMs
  if (s.phase === "break") return Math.max(0, s.breakEndsAt - now)
  return 0
}

function focusMs(s, now) {
  return s.phase === "break" ? 0 : Math.max(0, now - s.focusSince)
}

function pad(n) { return (n < 10 ? "0" : "") + n }

// 43:51, or 1:05:00 past an hour.
function clock(ms) {
  var total = Math.ceil(Math.max(0, ms) / 1000)
  var h = Math.floor(total / 3600), m = Math.floor(total % 3600 / 60), sec = total % 60
  return h > 0 ? h + ":" + pad(m) + ":" + pad(sec) : m + ":" + pad(sec)
}

// 44m, 1h 5m, 30s.
function short(ms) {
  var total = Math.ceil(Math.max(0, ms) / 1000)
  if (total < 60) return total + "s"
  var min = Math.ceil(total / 60)
  if (min < 60) return min + "m"
  return Math.floor(min / 60) + "h " + (min % 60) + "m"
}

function duration(ms) {
  var sec = Math.round(ms / 1000)
  if (sec < 60) return sec + " sec"
  var min = Math.round(sec / 60)
  return min < 60 ? min + " min" : Math.floor(min / 60) + " h " + (min % 60) + " min"
}

function ignoredList(text) {
  return String(text || "").split(",").map(function(x) { return x.trim().toLowerCase() })
    .filter(function(x) { return x.length > 0 })
}

// PROBE_SEPARATOR splits the probe output into: source outputs (pactl JSON),
// sources (pactl JSON), and one process name per line that has /dev/video* open.
var PROBE_SEPARATOR = "\n--lookout--\n"
var CAMERA_SERVICES = ["pipewire", "wireplumber"]

function parseJson(text) {
  try { var v = JSON.parse(text); return Array.isArray(v) ? v : [] } catch (e) { return [] }
}

// Returns {inCall, apps}. A call is a microphone recording that is not a
// monitor source and not corked, or a camera in use.
function parseProbe(text, ignored) {
  var parts = String(text || "").split(PROBE_SEPARATOR)
  var outputs = parseJson(parts[0])
  var sources = parseJson(parts[1])
  var skip = ignoredList(ignored)
  var monitors = {}
  sources.forEach(function(src) {
    if (String(src.name || "").slice(-8) === ".monitor") monitors[src.index] = true
  })
  var apps = []
  function add(name) {
    var n = String(name || "").trim()
    if (n && apps.indexOf(n) < 0) apps.push(n)
  }
  outputs.forEach(function(o) {
    if (o.corked || monitors[o.source]) return
    var p = o.properties || {}
    var names = [p["application.name"], p["application.process.binary"]]
      .filter(Boolean).map(function(x) { return String(x).toLowerCase() })
    if (names.some(function(n) { return skip.indexOf(n) >= 0 })) return
    add(p["application.name"] || p["application.process.binary"] || "Microphone")
  })
  String(parts[2] || "").split("\n").forEach(function(line) {
    var comm = line.trim()
    var lower = comm.toLowerCase()
    if (!comm || CAMERA_SERVICES.indexOf(lower) >= 0 || skip.indexOf(lower) >= 0) return
    add(comm)
  })
  return { inCall: apps.length > 0, apps: apps }
}

// Browsers and video players. Music players are not video.
var VIDEO_APPS = ["chrome", "chromium", "firefox", "brave", "vivaldi", "edge", "opera", "zen",
  "librewolf", "mpv", "vlc", "celluloid", "totem", "haruna", "smplayer", "kodi", "jellyfin",
  "plex", "stremio", "freetube"]

// True when an MPRIS player of a browser or video player is playing.
function videoPlaying(players) {
  return (players || []).some(function(p) {
    if (!p || !p.isPlaying) return false
    var name = [p.identity, p.desktopEntry, p.dbusName].join(" ").toLowerCase()
    return VIDEO_APPS.some(function(app) { return name.indexOf(app) >= 0 })
  })
}

function probeCommand() {
  var sep = PROBE_SEPARATOR.replace(/\n/g, "")
  return ["sh", "-c",
    "pactl -f json list source-outputs 2>/dev/null || echo '[]'; echo; echo '" + sep + "'; " +
    "pactl -f json list sources short 2>/dev/null || echo '[]'; echo; echo '" + sep + "'; " +
    "find /proc/[0-9]*/fd -maxdepth 1 -lname '/dev/video*' 2>/dev/null | cut -d/ -f3 | sort -u | " +
    "while read p; do cat /proc/$p/comm 2>/dev/null; done"]
}

if (typeof module !== "undefined") {
  module.exports = {
    config: config,
    init: init,
    tick: tick,
    idleStart: idleStart,
    idleEnd: idleEnd,
    probed: probed,
    startBreak: startBreak,
    skip: skip,
    pause: pause,
    resume: resume,
    postpone: postpone,
    retime: retime,
    remaining: remaining,
    focusMs: focusMs,
    clock: clock,
    short: short,
    duration: duration,
    parseProbe: parseProbe,
    videoPlaying: videoPlaying,
    probeCommand: probeCommand,
    PROBE_SEPARATOR: PROBE_SEPARATOR
  }
}
