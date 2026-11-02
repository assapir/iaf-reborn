# IAF 2026 training: pass / fail rules and the debrief

**Terms:** blackbox = the flight recorder's JSON Lines file ([../../docs/blackbox.schema.json](../../docs/blackbox.schema.json));
engine frame = the game's world metres (X east, Y north, [../../docs/georef.md](../../docs/georef.md)); runway start = where the
declared runway begins ([airbases.md](airbases.md) §4); "inferred" = our own reasoning; "open" = no source found.

The scoring core (item E3a, plan.md) reads a recorded flight and a training mission and says pass or fail, with the
debrief's numbers. It is pure Rust and runs on recorded flights today; the in-game flow (the start command, the radio
menu, the debrief page) is item E3b / E2.

```sh
cargo run -p iaf-tools --bin iaf-training -- score <flight.jsonl> iaf-2026/data/missions/ramon_takeoff.json [airbases-dir] [--json debrief.json]
```

The airbases folder defaults to `airbases` beside the mission file's folder (`iaf-2026/data/airbases`), from any
working folder; a missing folder stops the run with its name.

## 1. Where the code is, and why
`crates/iaf-tools/src/training.rs` (module `training`) and the bin `iaf-training`. The module sits in iaf-tools beside
the georeference (`georef.rs`) and the mission compiler (`sim.rs`), whose data readers, source checks and `place()`
it uses: the compiler checks the rules with the same parser the scorer uses. The module is plain Rust over JSON in
and JSON out, ready for E3b to call through a small `iaf-godot` class.

## 2. Positions: the engine frame
The recorder logs scene metres (x east, z south) from the terrain's origin. The scorer turns each sample into the
engine frame, `(origin.x + x, origin.y − z)`, and turns the two ends of the mission's runway (lat / lon in the airbase
file) into the same frame with `Georef::geo_to_engine`, the call the mission compiler uses to place the jet. Two
reasons to work in the engine frame:
- the recorded heading is the engine frame's, so it compares with the runway's engine-frame heading directly (the
  warp turns true headings by a little, which a per-sample lat / lon conversion would have to undo);
- only two points per runway are converted, not every sample.

Near a base the engine frame is real metres to within the warp's local stretch ([../../docs/georef.md](../../docs/georef.md)),
so lengths in metres are real ones (inferred). When item B1's 1:1 terrain replaces the georeference, the scorer
follows the compiler, since both call the same function.

## 3. The rules (mission JSON, `"training"`)
Each figure has a source in the mission's `sources` (`"training.time_budget_s"` …), checked by the compiler
([data-formats.md](data-formats.md) §5).

| field | start-up | take-off | default | source |
|---|---|---|---|---|
| `kind` | `"startup"` | `"takeoff"` | — | — |
| `time_budget_s` | idle with avionics up by then | airborne, gear up, on heading by then | 120 s / 900 s | inferred |
| `heading_tolerance_deg` | — | ± from the runway heading | 10° | inferred |
| `empty_kg` | — | gross weight = this + the recorded fuel | F-16: 8,573 kg; F-35I: 13,290 kg | F-16C Block 50 / 52[^w-f16]; F-35A[^w-f35]; the IAF jets' own weights inferred the same |
| `takeoff_kt` | — | reference take-off speed by gross weight: `[[kg, kt], …]`, linear between, held at the ends | F-16: [[9072, 130], [21772, 214]]; F-35I: [[13290, 165]] | F-16: 70 kt + 3 kt per 1000 lb[^bms]; F-35: about 165 kt[^wn] |

The two take-off speed sources are weak (a forum post quoting a pilot's rule, a news photo page); no public flight
manual gives the F-16's or the F-35's take-off speeds by weight (open). Checked once more against them on
2026-11-02: at 30,000 lb the rule gives 160 kt, and the forum's figures (rotate at 170 kt with an air-to-air load,
180 kt heavy[^bms]) lie 10–20 kt above it, as the rotation 10–15 kt before the take-off speed implies (inferred). The
reference speed is a debrief number only; no rule fails on it.

### 3.1 Start-up: pass
- The engine started (the recorder's `engine` column turns true), and
- the engine at idle and the avionics up within `time_budget_s` of the flight's start.

The recorder has no RPM or avionics column yet. Until it does:
- **idle** = the engine start + 4 s: the model's ground start winds the RPM up from 0 at 15 %/s to the 60 % idle
  ([../../docs/flight-model.md](../../docs/flight-model.md) §10.2). With an `rpm` column the scorer takes the first
  sample at 60 % or more instead;
- **avionics up** = idle (inferred: once the F-16's engine is self-sustaining, at about 52 % RPM, below idle, it
  drives the main and standby generators[^f16net]). With an `avionics` column the scorer takes its first true sample.

### 3.2 Take-off: pass
All of:
- no `crash` event;
- a lift-off (the first sample off the ground after one on it that stays off it for 1 s, or to the recording's end; inferred);
- the roll started on the mission's runway (inside its length and width) and ran toward the far end;
- every sample of the roll stayed on the runway (else: excursion);
- some sample after the lift-off is airborne, gear up, heading within `heading_tolerance_deg` of the runway's, and
  within `time_budget_s`.

The roll starts at the slowest sample on the runway between the jet's entry onto it and its last sample below
30 kt before the lift-off: the stop on the lineup point, or the entry of a rolling take-off (inferred). The lineup
heading is the heading at that stop, or, in a rolling take-off, where the roll passes 30 kt. The rotation is the first sample of the roll
with the pitch 2° above the roll's first sample (inferred). "On the runway" is the jet's centre within half the
runway's width of the centreline (inferred).

Fail reasons, in the order checked: `no_start`, `over_time` (start-up); `crash`, `no_liftoff`, `wrong_runway`,
`excursion`, `gear_down`, `over_time`, `off_heading` (take-off).

## 4. The debrief record
`Debrief::to_json` (`iaf-training score … --json`): `mission`, `kind`, `pass`, `reasons` (ids), `items` (each `id`,
`value` rounded to 0.1 or null, `unit`, optional `note` id) and `strings` `{"en": {id: text}, "he": {id: text}}`
with every id the record names. The CLI prints the English summary.

| id | unit | meaning |
|---|---|---|
| `time_to_idle` | s | from the flight's start; note `from_spool` while the recorder has no RPM column |
| `time_to_avionics` | s | note `with_idle` while it has no avionics column |
| `throttle_moves` | — | runs of samples in which the lever moves more than 0.005 |
| `faults` | — | note `none_modelled`: the flight model has no hot or hung start |
| `taxi_time` | s | from the first sample above 1 kt to the roll's start |
| `lineup_heading_error` | deg | the lineup heading (§3.2) − the runway's |
| `roll_start_from_runway_start` | m | along the centreline from the runway start (100 m from the lineup point) |
| `roll_length` | m | the roll's start to the lift-off, along the centreline |
| `runway_left` | m | from the lift-off to the far end's runway start |
| `rotation_speed`, `liftoff_speed` | kt | true airspeed (the recorder's) |
| `gross_weight`, `reference_speed` | kg, kt | `empty_kg` + fuel at the lift-off; `takeoff_kt` at that weight |
| `gear_up_height`, `gear_up_time` | m, s | the first airborne sample with the gear up: height above the terrain, time after the lift-off |
| `roll_heading_deviation`, `max_centreline_offset` | deg, m | the largest over the roll |
| `tower_calls` | — | the `radio` events; note `not_recorded` while there are none |
| `cut_lines` | — | only when the recording's last line was cut off mid-write (the game stopped while writing) and skipped; a bad line elsewhere refuses the recording |

## 5. Checks
`cargo test -p iaf-tools --lib training`: three synthetic take-offs from Ramon 25R built in the test (a clean one, a
gear-down climb-out, a runway excursion; also a rolling take-off, a one-sample glitch off the ground while
taxiing, a rotation on the lift-off sample, a recording cut mid-line at its end), a synthetic start-up (pass, over the budget, never started), and the
newest real recording in the flights folder (`user://flights`: `~/.local/share/godot/app_userdata/iaf-reborn/flights`
on Linux, `~/Library/Application Support/Godot/app_userdata/iaf-reborn/flights` on macOS, or `IAF_FLIGHTS`) scored
against Ramon's take-off, skipped with a message when there is none. `IAF_TRAINING_WRITE=<dir>` keeps the synthetic
flights as JSONL. `cargo test -p iaf-tools --test training_cli`: the CLI from another working folder, a missing
airbases folder and a `--json` without a file. `sim::tests::training_rules_are_checked`: a training figure without a source and an unknown kind
are refused, and every take-off mission's runway is an end of its base's airbase file.

## 6. Open until E3b
- The recorder's columns for RPM and avionics power, and `radio` events (the tower calls); the scorer reads them
  once they exist.
- Scoring at run time (an `iaf-godot` class over `training::score`) and the debrief page (E2).
- The F-16I's, F-16D's and F-35I's own empty weights and take-off speeds by weight (open).
- A start-up fault model (hot / hung start): none in the flight model.
- The roll's start and rotation thresholds checked against a real flight of each mission by the user.

[^w-f16]: Wikipedia, "General Dynamics F-16 Fighting Falcon", Specifications (F-16C Block 50 / 52): empty weight 18,900 lb (8,573 kg), https://en.wikipedia.org/wiki/General_Dynamics_F-16_Fighting_Falcon
[^w-f35]: Wikipedia, "Lockheed Martin F-35 Lightning II", Specifications (F-35A): empty weight 29,300 lb (13,290 kg), https://en.wikipedia.org/wiki/Lockheed_Martin_F-35_Lightning_II
[^bms]: Falcon BMS forum, "Rotation speed" (the take-off speed 70 kt plus 3 kt per 1000 lb of gross weight; rotate at 170 kt with an air-to-air load, 180 kt heavy), https://forum.falcon-bms.com/post/314659
[^wn]: WION, the F-35's minimum lift-off speed about 165 kt (weak), https://www.wionews.com/photos/how-does-the-f-35-fighter-jet-stand-out-in-takeoff-speed-and-design-here-s-its-minimum-lift-off-speed-1752767093279
[^f16net]: F-16.net forum, "Main PWR on the F-16", Davis83, 7 December 2010 (the engine self-sustaining at about 52 % RPM, the JFS disengaged, the engine driving the hydraulic pumps and the main and standby generators), https://www.f-16.net/forum/viewtopic.php?p=186672
