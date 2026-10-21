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
  (flight-model section, type code, model, cockpit) and the arming loadouts; the blackbox file.
- **During the flight:** a crash with its reason, an ejection, a jump to another aircraft.
- **At the flight's end:** the mission, debrief or exit, and the sim time flown.
- **A Rust panic** in the extension: godot-rust's error line (the message and its source file and line), then
  `[panic backtrace]` with the call stack by function name (the hook in `crates/iaf-godot/src/lib.rs`).

A test or tool run with `--log-file` writes its log there instead; the startup line still names the default path
(Godot does not show scripts that argument).
