#!/bin/bash

# Bundled mic sound recording toggle for the rmnsoni.voicememo bar widget
# (needs pw-record from pipewire; ships with Omarchy).
#
#   soundrecord.sh                  # toggle: start / stop mic recording
#   soundrecord.sh --stop-recording # stop only; exit 1 when nothing is recording
#   soundrecord.sh --status         # exit 0 while recording, 1 otherwise
#
# Output: $OMARCHY_SOUNDRECORD_DIR (default ~/Music/Recordings)/soundrecording-<timestamp>.flac
# While recording a state file at ${XDG_RUNTIME_DIR}/omarchy-soundrecording holds
# "pid|file|started". Keybinds or other toggles that use the same state file
# (the omarchy-soundrecord convention) stay in sync with the bar widget.

set -u

[[ -f ~/.config/user-dirs.dirs ]] && source ~/.config/user-dirs.dirs
OUTPUT_DIR="${OMARCHY_SOUNDRECORD_DIR:-${XDG_MUSIC_DIR:-$HOME/Music}/Recordings}"
STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/omarchy-soundrecording"
LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/omarchy-soundrecord.lock"

write_state() { # atomic rename, so a racing reader never sees a torn/partial line
  local tmp="$STATE_FILE.tmp.$$"
  printf '%s\n' "$1" >"$tmp" && mv -f "$tmp" "$STATE_FILE"
}

is_recording() {
  if [[ -f $STATE_FILE ]]; then
    if kill -0 "$(cut -d'|' -f1 "$STATE_FILE")" 2>/dev/null; then
      return 0
    fi
    rm -f "$STATE_FILE" # stale state from a crashed recorder
  fi
  # Self-heal: adopt an orphaned pw-record writing into our output dir (state
  # file lost to a raced toggle) so the next press stops it cleanly.
  local orphan ofile
  orphan="$(pgrep -f "^pw-record .*$OUTPUT_DIR" 2>/dev/null | head -n1)"
  [[ -n "$orphan" ]] || return 1
  ofile="$(tr '\0' '\n' <"/proc/$orphan/cmdline" 2>/dev/null | grep '\.flac$' | head -n1)"
  [[ -n "$ofile" ]] || return 1
  write_state "$orphan|$ofile|0"
  return 0
}

stop_recording() {
  local pid file duration count

  IFS='|' read -r pid file _ <"$STATE_FILE"

  # SIGINT lets pw-record finalize the FLAC properly, like gpu-screen-recorder
  kill -SIGINT "$pid" 2>/dev/null

  # Give it up to 5 seconds to finish writing
  count=0
  while kill -0 "$pid" 2>/dev/null && ((count < 50)); do
    sleep 0.1
    count=$((count + 1))
  done

  if kill -0 "$pid" 2>/dev/null; then
    kill -9 "$pid" 2>/dev/null
    rm -f "$STATE_FILE"
    omarchy-notification-send -u critical -t 5000 "Sound recording error" \
      "Recording process had to be force-killed. File may be corrupted."
    exit 1
  fi

  rm -f "$STATE_FILE"

  duration=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$file" 2>/dev/null)
  if [[ -n ${duration:-} ]]; then
    duration=" ($(printf '%02d:%02d' "$(echo "$duration" | awk '{printf "%d", $1/60}')" "$(echo "$duration" | awk '{printf "%d", $1%60}')"))"
  fi

  omarchy-notification-send "Sound recording saved$duration" "$file
Transcribe later: Capture → Transcribe recordings" \
    -t 8000 --exec mpv -- "$file"
}

start_recording() {
  local file pid mute_state

  mkdir -p "$OUTPUT_DIR"
  file="$OUTPUT_DIR/soundrecording-$(date +'%Y-%m-%d_%H-%M-%S').flac"

  # 200>&- keeps the lock fd out of the child: pw-record outlives this script
  pw-record "$file" 200>&- &
  pid=$!

  # Bail out early if pw-record failed to spawn/link (e.g. no source node)
  sleep 0.3
  if ! kill -0 "$pid" 2>/dev/null; then
    omarchy-notification-send -u critical -t 3000 "Sound recording failed to start" \
      "pw-record exited immediately. Check that a microphone/audio source is available."
    exit 1
  fi

  write_state "$pid|$file|$(date +%s)"

  mute_state=$(pactl get-source-mute @DEFAULT_SOURCE@ 2>/dev/null | awk '{print $2}')
  if [[ $mute_state == "yes" ]]; then
    omarchy-notification-send "Sound recording started (microphone is muted!)" \
      "Unmute the mic, or only silence will be captured. Press SUPER SHIFT + R to stop."
  else
    omarchy-notification-send "Sound recording started" "Press SUPER SHIFT + R to stop"
  fi
}

# Serialize mutating instances: a double-fired toggle key must never spawn a
# second recorder over the same-second output file (raced the state file away).
# --status stays unlocked: the bar badge polls it every second.
if [[ ${1:-} != "--status" ]]; then
  exec 200>>"$LOCK_FILE"
  flock -n 200 || exit 0
fi

case ${1:-} in
--status)
  is_recording
  ;;
--stop-recording)
  if is_recording; then
    stop_recording
  else
    echo "No sound recording in progress" >&2
    exit 1
  fi
  ;;
"")
  # Toggle: stop whatever is recording before starting anew
  if is_recording; then
    stop_recording
  else
    start_recording
  fi
  ;;
*)
  echo "Usage: omarchy-soundrecord [--stop-recording|--status]" >&2
  exit 64
  ;;
esac