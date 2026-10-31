# Voice Memo — Omarchy shell plugin

Bar widget for a mic voice-memo pipeline: record toggle, live elapsed time,
and an un-transcribed recordings badge. Built around two companion scripts:

- `omarchy-soundrecord` — toggle the mic recorder (pw-record → FLAC)
- `omarchy-voicenote` — transcribe recordings that have no `.txt` yet

The widget watches the recorder's runtime state file and the recordings
folder, so it stays in sync with the keybind, the menu, and anything else
that drives the same scripts.

## Screenshots

While recording — recorder glyph with live elapsed time in the alert color:

![Recording state](docs/widget-recording.png)

Idle with one un-transcribed recording in the backlog:

![Backlog badge](docs/widget-idle.png)

After clicking stop (or toggling the keybind) — the save notification:
![Saved notification](docs/notification-saved.png)

## Install

```bash
omarchy plugin add https://github.com/RmnSoni/voicememo
```

Then place the widget in the bar:

```bash
omarchy bar put io.github.rmnsoni.voicememo --section center
```

(or add `{"id": "io.github.rmnsoni.voicememo"}` to `~/.config/omarchy/shell.json`).

The two scripts are personal (the voice pipeline runs on one machine), so
they are not part of the plugin. Without them the widget still works
read-only: it reflects the recorder state file and counts un-transcribed
`*.flac` files in the folder it watches.

## Widget behaviour

- **Recording** — polls `${XDG_RUNTIME_DIR}/omarchy-soundrecording` (the
  state file written by `omarchy-soundrecord`) once a second; while
  recording shows the recorder glyph with live elapsed time in the alert
  color. Click stops the recording.
- **Backlog badge** — counts `*.flac` in the recordings folder that have no
  sibling `.txt` (i.e. not yet transcribed by `omarchy-voicenote`); shows mic
  glyph + count when idle, hidden when everything is processed.
- **Hidden when idle with no backlog** (same behaviour as the built-in
  indicators).

### Clicks

| Button | Action |
|---|---|
| Left | Toggle recording (same as the SUPER SHIFT + R keybind) |
| Middle | `omarchy-voicenote --all` — transcribe every unprocessed recording |
| Right | Open the recordings folder |

## Settings

| Key | Default | Meaning |
|---|---|---|
| `recordDir` | *(empty)* | Override recordings folder; empty follows `OMARCHY_SOUNDRECORD_DIR` / `XDG_MUSIC_DIR` (default `~/Music/Recordings`) |
| `showPending` | `On` | Badge for un-transcribed recordings |

## How it works

One bash probe per second emits a single line:

```
recording|startedEpoch|pendingCount|recordDir
```

parsed in QML; the elapsed time is interpolated locally on a 500 ms timer so
no extra process spawns between probes. The widget uses the public
`WidgetButton` (same text path as the built-in clock, auto-width labels).

Fails soft: if a probe fails, the widget simply hides until the next tick.

## License

MIT — see [LICENSE](LICENSE).