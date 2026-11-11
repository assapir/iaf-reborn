# Logs

This doc lists the logs the game and its tools write, where each one is, and what it holds. Send these with a bug
report.

## 1. Where they are

`<user>` is Godot's user folder: `~/Library/Application Support/Godot/app_userdata/iaf-reborn/` on macOS,
`~/.local/share/godot/app_userdata/iaf-reborn/` on Linux (macos.md).

| log | where | kept |
|---|---|---|
| game | `<user>/logs/godot.log` (the current run); older runs `godot<date>T<time>.log` beside it | the newest 30 |
| blackbox | `<user>/flights/flight-<date>_<time>-m<mission>.jsonl` (one per flight, blackbox.schema.json) | the newest 10 |
| setup wizard | `assets/logs/setup-<date>-<time>.log` (one per run, setup.md) | all |
| guide pictures | `assets/logs/guide-shots-<date>-<time>-<pid>/` (one Godot log per process, guides/README.md) | only when one failed |

## 2. The game log

Godot writes everything the game prints, and every error and warning, with the script and line. The game adds:
- **At startup** (`settings.gd` `_log_startup`): the build (the extension's git commit, `IafInfo.commit()`), the
  Godot version, the OS and its version, the CPU, cores and RAM; the GPU, its driver API and the renderer; the window
  size and UI scale; this log's path and the assets folder; every setting changed from the default, the Physics
  switches on and the Better cockpit items off (`Settings.changed_settings()`).
- **At a flight's start** (`terrain_view.gd`): the mission number and name, the player's entity and flight; the jet
  (flight-model section, type code, model, cockpit) and the Arming screen's picks; the blackbox file.
- **During the flight:** a crash with its reason, an ejection, a jump to another aircraft.
- **At the flight's end:** the mission, debrief or exit, and the sim time flown.
- **A stall:** a frame longer than 250 ms gets a `stall:` line with its length, the scene (in the menus, the screen)
  and the last mouse click (button, double or not, where, how long before). A scene that loads in one frame shows as
  one; the flight's start is spread over frames behind the loading screen (rendering.md §1.5). A test script's frames
  before its first scene show the scene as `?`. A pause (the mission card, the pause menu) also shows as a stall when it ends.
- **A Rust panic** in the extension: godot-rust's error line (the message and its source file and line), then
  `[panic backtrace]` with the call stack by function name (the hook in `crates/iaf-godot/src/lib.rs`).

- **The flight's loading** (`terrain_view.gd`): each step with its time since the loading screen opened
  (`loading: terrain at 2250 ms`), each sub-step with its own time (`loading:   cockpit cut 213 ms`), the end
  (`loading: done at 4199 ms`); the stores as loaded, per station (`stores: 1 AIM-9M x1, …`). Modern IAF's watchdog
  adds `hang:` lines (modern-iaf/docs/front-end.md §7).

**Modern IAF's log** (`shared/util/timed_log.gd`, since 2026-11-10) starts every line with the local wall-clock time,
`HH:MM:SS.mmm`, so a stall shows as a gap. Its project turns Godot's own file log off and the sim writes the log
itself, at the same path (`<user>/logs/godot.log`, `<user>` the "Modern IAF" folder) with the same rotation (the newest
30). It misses only what Godot prints before the scripts load (Godot's first line and the GPU's line; the startup lines
repeat both). Its own thread prints `hang: no frame for 30 s; loading step <step>, after <sub-step>` when the main
thread runs no frame for 30 s (a paused game still runs frames: no hang); the line only logs, since a first start's
single frame can compile shaders that long on a Mac. After a flight's first 10 frames after the loading come the first world
frame's time (`loading: first world frame drawn at <ms>`), a line per shader in use and `shaders: <n> in use, <n>
failed, <n> shader errors logged`; `safe:` lines name the features IAF_SAFE turned off (modern-iaf/docs/front-end.md
§11.1). A scripted run (`IAF_DEFAULT_SETTINGS=1`, with `--log-file`) gets Godot's log there,
without the times. The original game's log is unchanged.

A test or tool run with `--log-file` writes its log there instead; the startup line still names the default path
(Godot does not show scripts that argument).
