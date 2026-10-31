import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Voice-memo bar widget: recording toggle + un-transcribed backlog badge.
//
// Replaces the old `soundrec` command module with the same hide-when-idle
// behaviour, and adds the two things a shell script badge could not do:
// live elapsed time while recording and a "recordings waiting to be
// transcribed" indicator for the voicenote pipeline.
//
// Probes once a second; the probe protocol is a single line:
//   recording|startedEpoch|pendingCount|recordDir
BarWidget {
  id: root
  moduleName: "io.github.rmnsoni.voicememo"

  property bool recording: false
  property double started: 0
  property int pending: 0
  property string recordDir: ""
  property string elapsedText: ""

  readonly property bool showPending: String(setting("showPending", "On")) !== "Off"
  readonly property bool hasBacklog: showPending && pending > 0

  visible: recording || hasBacklog
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function fmt(sec) {
    sec = Math.max(0, Math.floor(sec))
    var m = Math.floor(sec / 60)
    var s = sec % 60
    return m + ":" + (s < 10 ? "0" : "") + s
  }

  function apply(raw) {
    var parts = String(raw || "").trim().split("|")
    if (parts.length < 3) return
    recording = parts[0] === "1"
    var st = Number(parts[1])
    started = isFinite(st) && st > 0 ? st : 0
    pending = parseInt(parts[2], 10) || 0
    recordDir = parts.length > 3 ? parts[3] : ""
    elapsedText = recording && started > 0 ? fmt(Date.now() / 1000 - started) : ""
  }

  function toggleRecord() {
    // PATH lookup: works wherever an omarchy-soundrecord script exists
    // (stock Omarchy installs ship one; personal pipelines may shadow it)
    if (root.bar) root.bar.run("omarchy-soundrecord")
  }

  function transcribeAll() {
    if (root.bar) root.bar.run("omarchy-voicenote --all")
  }

  function openFolder() {
    if (root.recordDir === "") return // 1s probe fills this from bash resolution
    if (root.bar) root.bar.run("xdg-open \"" + root.recordDir.replace(/"/g, "") + "\"")
  }

  readonly property string probe: [
    "rec=0; started=0",
    "state=\"${XDG_RUNTIME_DIR:-/tmp}/omarchy-soundrecording\"",
    "if [[ -f \"$state\" ]]; then",
    "  IFS='|' read -r pid _f st _rest <\"$state\"",
    "  kill -0 \"$pid\" 2>/dev/null && { rec=1; started=\"$st\"; }",
    "fi",
    "dir=\"${1:-}\"",
    "if [[ -z \"$dir\" ]]; then",
    "  [[ -f \"$HOME/.config/user-dirs.dirs\" ]] && source \"$HOME/.config/user-dirs.dirs\"",
    "  dir=\"${OMARCHY_SOUNDRECORD_DIR:-${XDG_MUSIC_DIR:-$HOME/Music}/Recordings}\"",
    "fi",
    "pending=0",
    "shopt -s nullglob",
    "for f in \"$dir\"/*.flac; do",
    "  [[ -f \"${f%.flac}.txt\" ]] || pending=$((pending + 1))",
    "done",
    "printf '%d|%s|%d|%s\\n' \"$rec\" \"$started\" \"$pending\" \"$dir\""
  ].join("\n")

  readonly property var probeCommand: [
    "bash", "-c", probe, "io.github.rmnsoni.voicememo-probe", String(setting("recordDir", ""))
  ]

  Process {
    id: prober
    command: root.probeCommand
    stdout: StdioCollector {
      id: proberOut
      waitForEnd: true
      onStreamFinished: root.apply(proberOut.text)
    }
  }

  function probeNow() {
    if (!prober.running) prober.running = true
  }

  Timer {
    interval: 1000
    running: root.bar !== null
    repeat: true
    triggeredOnStart: true
    onTriggered: root.probeNow()
  }

  Timer {
    interval: 500
    running: root.recording
    repeat: true
    onTriggered: {
      if (root.started > 0) root.elapsedText = root.fmt(Date.now() / 1000 - root.started)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.recording ? "󰻂 " + root.elapsedText : (root.hasBacklog ? "󰍬 " + root.pending : "")
    labelVisible: true
    hasVisualContent: text !== ""
    tooltipText: root.recording
      ? ("Recording voice memo — " + root.elapsedText
         + "\nLeft: stop · Middle: transcribe all · Right: open folder")
      : (root.pending + " recording(s) not transcribed yet"
         + "\nLeft: record · Middle: transcribe all · Right: open folder")
    active: root.recording

    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.transcribeAll()
      else if (b === Qt.RightButton) root.openFolder()
      else root.toggleRecord()
    }
  }
}