# Modern IAF training: pass / fail rules and the debrief

**Terms:** blackbox = the flight recorder's JSON Lines file ([../../docs/blackbox.schema.json](../../docs/blackbox.schema.json));
engine frame = the game's world metres (X east, Y north, [../../docs/georef.md](../../docs/georef.md)); runway start = where the
declared runway begins ([airbases.md](airbases.md) §4); "inferred" = our own reasoning; "open" = no source found.

The scoring core (item E3a, plan.md) reads a recorded flight and a training mission and says pass or fail, with the
debrief's numbers. It is pure Rust. Since item E3b (2026-11-03) the game runs both training missions without the front
end: the jet parked cold, one start command (§7), the radio menu and the tower (§8), scoring at the mission's end with
the debrief record and the pilot log (§9), and a probe that flies both missions for each jet (§10). The front end
(item E2, [front-end.md](front-end.md)) shows the record as its debrief sheet.

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

Modern IAF's recorder (version 2, §9) has an `rpm` and an `avionics` column, and the scorer reads them:
- **idle** = the first sample with the engine running at 60 % RPM or more (the 6-DoF's idle, §7);
- **avionics up** = the first sample whose `avionics` is true.

A recording without those columns (version 1, the original game's recorder) is scored from the model instead: idle
= the engine start + 4 s (the original model's ground start winds the RPM up from 0 at 15 %/s to the 60 % idle,
[../../docs/flight-model.md](../../docs/flight-model.md) §10.2), avionics up = idle (inferred: once the F-16's engine
is self-sustaining, at about 52 % RPM, it drives the main and standby generators[^f16net]); the debrief notes both.

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

## 6. Open
- The checklist card (after the MVP, plan.md "start-up").
- The F-16I's, F-16D's and F-35I's own empty weights and take-off speeds by weight (open).
- A start-up fault model (hot / hung start): none in the flight model.
- The roll's start and rotation thresholds checked against a real flight of each mission by the user.
- The 6-DoF's take-off roll is short (flight-model.md §9.6): the probe's Sufa lifts off after about 465 m at 180 kt.

## 7. The start in the game
The sim's jet starts parked cold: on its spot (airbases.md §9), engine off, no RPM, no electrical power, every screen,
the HUD and the lamps dark (`cockpit.power` 0). The throttle starts nothing (`Settings.throttle_starts_engine`, false
in the sim; in the original game any throttle command starts the engine at once, as before, on either flight model).
One command, **Start engine** (Ctrl+E, record 117 of the sim's own `keys.json`, command 200, `IafFlight.start_engine`),
runs the jet's start sequence
(`crates/iaf-flight/src/sixdof/start.rs`), which the flight model steps every frame:

| step | F-16I Sufa, F-16D Barak (JFS) | F-35I Adir (IPP) | source |
|---|---|---|---|
| the command | battery on: the lamps and engine gauges live (`power` 1) | the same | inferred |
| starter | the JFS cranks the engine at once | the IPP runs 10 s, then cranks | F-35: three selections, battery, IPP, engine[^ayton]; the 10 s inferred |
| crank | 0 → 20 % RPM in 15 s | the same | 20 %: the throttle to idle at 20 % RPM minimum[^chk]; the 15 s inferred |
| light-off | 5 s after the fuel on | the same | inferred (open: no light-off time found in a primary source) |
| to idle | 20 → 60 % in 15 s, then the engine runs (thrust, fuel flow) | the same | 60 %: the 6-DoF's idle (flight-model.md §9.7); the 15 s inferred |
| main generator | at 52 % RPM: the engine self-sustaining, the JFS off | — | about 52 %[^f16net], the JFS cut at 50–54 %[^jfs50] |
| displays and HUD up (`power` 2) | 3 s after the generator | 3 s after the IPP runs | the 3 s warm-up inferred |
| avionics up (`avionics`) | with the displays | 90 s after the command | F-35: "after 90 seconds … ready"[^ayton] |
| sum | idle and avionics at 35 s | displays 13 s, idle 45 s, avionics 90 s | |
| engine stopped (`set_engine_on(false)`, the ejection) | no RPM; the power as it was; a new command starts from the beginning | the same | inferred |

The F-15I's (no mission flies it yet) is the F-16's (inferred). The F-35I's engine steps are the F-16's: no public
figure (inferred). The sound is the engine clip of E1b (`SFX_START_ENGINE`) pitched by the RPM from the crank on
(`flight_sounds.gd`, unchanged); the starter's own whine has no clip (sound.md §7). The probe measures 37 s to idle
for the F-16s and 47 s / 92 s for the F-35I (the recorder samples 10 times a second; the scene takes a few frames).

## 8. The radio menu and the tower
The **Call the tower** key (Ctrl+T) opens a numbered list over the view; 1–4 pick, any other key closes it:

| # | English | Hebrew | the tower answers |
|---|---|---|---|
| 1 | Request start-up | בקשת התנעה | "Alpha, cleared to start" (`ACFT_CLEAR_TO_START`) |
| 2 | Request taxi | בקשת הסעה | with the engine running: "Alpha, good morning, taxi to runway 25 right" (`ACFT_TAXI_TO_RUNWAY`); else "hold position" |
| 3 | Request take-off | בקשת המראה | the original tower's rule on the ground (docs/radio.md §2 `ground()`): lined up in the lineup zone: "cleared for take-off"; 200–400 m from the lineup point with the runway clear: "line up runway 25 right, wind calm"; else "hold position" |
| 4 | Contact tower (landing) | קריאה למגדל (נחיתה) | the original's Ctrl+T (docs/radio.md §2): "proceed to runway …" in the air |

The pilot's call is printed ("Ramon tower, Alpha, request taxi"), the tower's answer printed and spoken by the English
TTS tower of E1b (sound.md §3), then the pilot's "Roger". The Hebrew labels show in Hebrew (right to left, in the sim's
Heebo font); the Hebrew voice waits for the user's licence decision (sound.md §5). The
tower is the base within 18.54 km: every base of the own `iaf.ibx` talks (Ramon, Ramat David, Hatzerim, Nevatim;
`Settings.tower_bases`); the mission's base's tower names the mission's runway (`"runway"`), the others their own. A request leaves the tower's
state machine as it is. In the menu the tower no longer talks on
its own on the ground (the original game's tower is unchanged). Each pick is a `radio` event in the recording (§9),
which the debrief counts as `tower_calls`. The scorer has no rule on the calls (a take-off without them still passes).

Taxi: the jet taxis on the base's taxiways to the lineup (the probe follows the own `iaf.ibx`'s taxi path). The
take-off passes by §3.2.

## 9. Scoring in the game, the debrief record and the pilot log
`iaf-2026/flight/sim_flight.gd` (the sim's part of the flight scene, `Settings.flight_addon`) scores a mission whose
compiled file has `sim.training`:
- a start-up once the engine idles with the avionics up, a take-off once airborne with the gear up (then every 3 s
  until it passes), either at a crash or 5 s past its time budget;
- `IafTraining.score(recording, mission, airbases)` (crates/iaf-godot/src/training.rs) runs `training::score_files`
  on the recording so far, the readable mission `iaf-2026/data/missions/<id>.json` and the airbase files;
- the debrief record (§4, plus `flight`: the recording's path, `date`: the end, `elapsed_s`: the flight's length) goes
  to `user://debriefs/debrief-<date>-<id>.json`, compact, and `Settings.flown_debrief` names it for the front end;
- the attempt goes to the pilot log `user://pilots/<pilot id>.json` (the default pilot 14 until E2's pilot list) in the
  original game's shape (`iaf-reborn/menu/pilots.gd`): `{"missions": [{"id": <menu id>, "attempts": [{"result": 1 | 0,
  "mult": 1.0, "bonus": 0, "kills": [], "losses": [], "debrief": <file>, "date": …}]}]}`, newest mission first;
- the result and its numbers show over the view (in the game's language); ending the flight (Esc → End the flight, or
  Ctrl+Q → Debrief) opens the front end's debrief sheet.

Scoring needs the recorder (Extras, on by default): with it off the flight is not scored (a warning in the log). Tests
record beside the debrief, in a temporary folder. The recorder's version 2 (`Settings.blackbox_version`, [data-formats.md](data-formats.md) §13) adds `rpm`
(%) and `avionics`.

`tools/flight_timeline.py <recording> --debrief <debrief.json> [--html f.html]` shows the debrief with the flight's
timeline (the radio calls, the lift-off) and the start's steps from the RPM column.

## 10. The probe and a real run
`iaf-2026/tests/test_mvp.gd` (item F's probe, started here) flies both missions for the Sufa (Ramon), the Barak
(Ramat David) and the F-35I (Nevatim) headless with scripted inputs at 6× time: the start-up (cold, the throttle
starts nothing, the start command, the columns, the debrief file, the pilot log) and the take-off (the three radio
calls and their answers, a taxi along the base's taxi path to the lineup, the roll on the centreline, the rotation,
gear up), each ending in Pass. `-- --jet f16i` / `-- --only startup` narrow it. Item F adds the front end, Hebrew, the
temp-root run and the other platforms.

`./modern-iaf -- --mission <id>` flies one mission at once (`iaf-2026/flight/fly.gd`), then shows its debrief: 2011 / 2012 Ramon
start-up / take-off, 2021 / 2022 Ramat David, 2031 / 2032 Nevatim.
`iaf-2026/tests/_training_shot.gd` takes the pictures in a real render (its header).

[^w-f16]: Wikipedia, "General Dynamics F-16 Fighting Falcon", Specifications (F-16C Block 50 / 52): empty weight 18,900 lb (8,573 kg), https://en.wikipedia.org/wiki/General_Dynamics_F-16_Fighting_Falcon
[^w-f35]: Wikipedia, "Lockheed Martin F-35 Lightning II", Specifications (F-35A): empty weight 29,300 lb (13,290 kg), https://en.wikipedia.org/wiki/Lockheed_Martin_F-35_Lightning_II
[^bms]: Falcon BMS forum, "Rotation speed" (the take-off speed 70 kt plus 3 kt per 1000 lb of gross weight; rotate at 170 kt with an air-to-air load, 180 kt heavy), https://forum.falcon-bms.com/post/314659
[^wn]: WION, the F-35's minimum lift-off speed about 165 kt (weak), https://www.wionews.com/photos/how-does-the-f-35-fighter-jet-stand-out-in-takeoff-speed-and-design-here-s-its-minimum-lift-off-speed-1752767093279
[^ayton]: Mark Ayton, "Blue Sky OPS", AIR International, 26 April 2012, quoted on F-16.net, "Engine start up procedure" (three switch selections: battery, IPP, engine; "After 90 seconds, if there are no problems, the aircraft declares itself ready for flight"), https://www.f-16.net/forum/viewtopic.php?p=317934
[^chk]: F-16 checklist (sim community, after the T.O. checklist; weak): "THROTTLE – Advance to IDLE (20% RPM Min)", https://www.scribd.com/document/38303072/Checklist-Main
[^jfs50]: F-16.net forum, "JFS and avionics question" (the flight manual: "As the engine accelerates through 50 % rpm, a sensor causes the JFS to shut down automatically"; about 50 % on a P&W and 54 % on a GE engine), https://www.f-16.net/forum/viewtopic.php?p=13518
[^f16net]: F-16.net forum, "Main PWR on the F-16", Davis83, 7 December 2010 (the engine self-sustaining at about 52 % RPM, the JFS disengaged, the engine driving the hydraulic pumps and the main and standby generators), https://www.f-16.net/forum/viewtopic.php?p=186672
