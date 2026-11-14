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
cargo run -p iaf-tools --bin iaf-training -- score <flight.jsonl> modern-iaf/data/missions/ramon_takeoff.json [airbases-dir] [--json debrief.json]
```

The airbases folder defaults to `airbases` beside the mission file's folder (`modern-iaf/data/airbases`), from any
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
| `end_hold_s` | a fail shows its reason this long before the debrief (a pass: the flight goes on, §9) | the same | 5 s | inferred: time to see the result before the debrief |
| `goals` | the debrief items the sheet shows, in order (§4) | the same | `[]` / `["runway", "liftoff_speed", "reference_speed", "max_centreline_offset", "tower_calls"]` | — (not a figure) |
| `heading_tolerance_deg` | — | ± from the runway heading | 10° | inferred |
| `empty_kg` | — | gross weight = this + the recorded fuel | F-16: 8,573 kg; F-35I: 13,290 kg | F-16C Block 50 / 52[^w-f16]; F-35A[^w-f35]; the IAF jets' own weights inferred the same |
| `takeoff_kt` | — | reference take-off speed by gross weight: `[[kg, kt], …]`, linear between, held at the ends | F-16: [[9072, 130], [21772, 214]]; F-35I: [[13290, 165]] | F-16: 70 kt + 3 kt per 1000 lb[^bms]; F-35: about 165 kt[^wn] |

The two take-off speed sources are weak (a forum post quoting a pilot's rule, a news photo page); no public flight
manual gives the F-16's or the F-35's take-off speeds by weight (open). Checked once more against them on
2026-11-02: at 30,000 lb the rule gives 160 kt, and the forum's figures (rotate at 170 kt with an air-to-air load,
180 kt heavy[^bms]) lie 10–20 kt above it, as the rotation 10–15 kt before the take-off speed implies (inferred). The
reference speed is a debrief number only; no rule fails on it.

### 3.0 Every mission: fail at once
Since 2026-11-08 (the user's Mac play test: a crash in the start-up still passed) any of these ends a training
mission at once as a Fail, with its reason first in the debrief:

| reason | the recording's event | the game's live check (`Watch::check`, `IafTraining.check`) |
|---|---|---|
| `ejected` | `eject` | the pilot ejected |
| `crash` | `crash` | the jet crashed |
| `damage` | `hit` (any damage to the jet) | the player's unit's damage above 0 |
| `off_pavement` | `surface` with `paved` false | on the ground with the jet's centre off the base's pavement |
| a phase without clearance, `wrong_runway` (§3.3) | `clearance` with its `reason` | `Watch::check`'s clearance and runway rules |

The pavement is the mission's base from its airbase file (`sim_bases::Base::paved`), the same shapes the paved
mask is drawn from ([data-formats.md](data-formats.md) §12): within half the width of a runway's, stopway's or
taxiway's centreline (a taxiway without an OSM width: 23 m), or inside an apron or a shelter's pad, with a 5 m
margin past every edge (`PAVEMENT_MARGIN_M`, inferred: OSM draws centrelines and outlines, not the paved fillets
where a taxiway meets a runway or turns; the probe's Sufa, cutting a corner onto runway 07R at Ramon, passed its edge
by 0.05 m). The jet's centre is checked, not each wheel (inferred: a centre off the edge puts a main wheel off it; a wheel-by-wheel check would
fail a jet on the OSM shapes' rough edges). The live check writes the `surface` event, so the recording carries the
reason.

### 3.1 Start-up: pass
- The engine started (the recorder's `engine` column turns true),
- the engine at idle and the avionics up within `time_budget_s` of the flight's start, and
- nothing failed (§3.0) up to the goal; the pass is kept, whatever follows.

Modern IAF's recorder (version 2, §9) has an `rpm` and an `avionics` column, and the scorer reads them:
- **idle** = the first sample with the engine running at 60 % RPM or more (the 6-DoF's idle, §7);
- **avionics up** = the first sample whose `avionics` is true.

A recording without those columns (version 1, the original game's recorder) is scored from the model instead: idle
= the engine start + 4 s (the original model's ground start winds the RPM up from 0 at 15 %/s to the 60 % idle,
[../../docs/flight-model.md](../../docs/flight-model.md) §10.2), avionics up = idle (inferred: once the F-16's engine
is self-sustaining, at about 52 % RPM, it drives the main and standby generators[^f16net]); the debrief notes both.

### 3.2 Take-off: pass
All of:
- nothing failed (§3.0) to the mission's end;
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

Fail reasons, in the order checked: the §3.0 reason first (the earliest event); then `no_start`, `not_done` (the
engine never at idle with the avionics up), `over_time` (start-up); `no_liftoff`, `wrong_runway`, `excursion`,
`gear_down`, `over_time`, `off_heading` (take-off; after a §3.0 fail the climb-out is not judged).

### 3.3 The tower's clearances and the runway
Since 2026-11-13 (the user: "missions should fail if I start without tower permissions"; "I need to be able to call
tower to align and for take off") a mission's `training.clearances` (mission data, the three take-off missions:
`["startup", "taxi", "takeoff"]`; the start-up missions have no tower call in their design and name none) makes each
phase wait for its clearance. Doing it first fails the mission at once (§3.0's pattern: the banner with the reason,
the debrief 5 s later), the tower says so once (sound.md §3) and the recording gets `{"event": "clearance",
"reason": …}`. `Watch::check` in `crates/iaf-tools/src/training.rs` decides; the clearances come from the tower's
answers so far (`Cleared::of`, the same state the radio menu lists its calls from):

| phase | detected when | cleared by | reason | the tower |
|---|---|---|---|---|
| `startup` | the engine turning: RPM 5 % or more (`ENGINE_TURNING_RPM`; a cold engine reads 0, the starter cranks it to 20 %) | "cleared to start" | `no_start_clearance` | "Alpha, engine start without clearance" / "Alpha, התנעה ללא אישור" |
| `taxi` | on the ground, the jet's centre more than 10 m from where it first stood (`TAXI_MOVED_M`, inferred: more than brake creep or the start's jolt) | "taxi to runway …" | `no_taxi_clearance` | "Alpha, taxi without clearance" / "Alpha, הסעה ללא אישור" |
| `takeoff`: entering the runway | on the ground, the centre within half the width of the mission's runway's centreline (the airbase file) | "line up …" or "cleared for take-off" | `no_runway_clearance` | "Alpha, runway entry without clearance" / "Alpha, כניסה למסלול ללא אישור" |
| `takeoff`: the roll | on that runway faster than 30 kt (`ROLL_START_KT`, the roll's start in §3.2) | "cleared for take-off" | `no_takeoff_clearance` | "Alpha, take-off without clearance" / "Alpha, המראה ללא אישור" |

A call asked and answered "hold position" clears nothing; the answer is decided at the pick, so no call is pending.
A clearance stays valid afterwards (a restart needs no new start-up call). No readback is modelled. A flight that
starts with the engine running holds the start, taxi and line-up clearances.

**The wrong runway.** In a take-off mission the jet on the ground, on a runway of the base and lined up within 30°
(`LINED_UP_DEG`, inferred: a jet crossing at 90° is not lined up) of an end other than the mission's
(`Watch::wrong_runway`; the designators are the airbase file's, the ones the tower names) gets a warning: the tower
says once per end "Alpha, you are on runway 7 left, the assigned runway is 25 right" ("Alpha, על מסלול 7 שמאלי,
המסלול שהוקצה 25 ימני") and the panel shows "Wrong runway: this is 07L, the assigned one is 25R." while it lasts. Lining
up there only warns; the roll there (faster than 30 kt) fails at once with `wrong_runway`.

## 4. The debrief record
`Debrief::to_json` (`iaf-training score … --json`): `mission`, `kind`, `pass`, `reasons` (ids), `items` (each `id`,
`value` rounded to 0.1 or null, `unit`, optional `text` (a name in place of the value) and `note` id), `goals` (the
rules' `goals`) and `strings` `{"en": {id: text}, "he": {id: text}}` with every id the record names. The CLI prints
the English summary.

The record keeps every item; the debrief sheet ([front-end.md](front-end.md)) shows only the `goals` (the user,
2026-11-08: "no one cares how long it took to start or how many times I moved the throttle unless it is a goal"):

| mission | the sheet shows |
|---|---|
| start-up | pass / fail and the reason (no goals) |
| take-off | the runway used, the lift-off speed and the reference speed, the max offset from the centreline, the tower calls |

| id | unit | meaning |
|---|---|---|
| `time_to_idle` | s | from the flight's start; note `from_spool` while the recorder has no RPM column |
| `time_to_avionics` | s | note `with_idle` while it has no avionics column |
| `throttle_moves` | — | runs of samples in which the lever moves more than 0.005 |
| `faults` | — | note `none_modelled`: the flight model has no hot or hung start |
| `taxi_time` | s | from the first sample above 1 kt to the roll's start |
| `runway` | — | `text`: the runway end the roll ran on ("25R"), from the base's runways; note `not_reached` off every runway |
| `lineup_heading_error` | deg | the lineup heading (§3.2) − the runway's |
| `roll_start_from_runway_start` | m | along the centreline from the runway start (100 m from the lineup point) |
| `roll_length` | m | the roll's start to the lift-off, along the centreline |
| `runway_left` | m | from the lift-off to the far end's runway start |
| `rotation_speed`, `liftoff_speed` | kt | true airspeed (the recorder's) |
| `gross_weight`, `reference_speed` | kg, kt | `empty_kg` + fuel at the lift-off; `takeoff_kt` at that weight |
| `gear_up_height`, `gear_up_time` | m, s | the first airborne sample with the gear up: height above the terrain, time after the lift-off |
| `roll_heading_deviation`, `max_centreline_offset` | deg, m | the largest over the roll |
| `tower_calls` | — | the `radio` events |
| `cut_lines` | — | only when the recording's last line was cut off mid-write (the game stopped while writing) and skipped; a bad line elsewhere refuses the recording |

## 5. Checks
`cargo test -p iaf-tools --lib training`: three synthetic take-offs from Ramon 25R built in the test (a clean one, a
gear-down climb-out, a runway excursion, a crash on the roll (fails at once, the crash first), damage, the wheels
off the pavement (the live check: the parking spot and the lineup paved, 200 m beside the runway not); also a rolling take-off, a one-sample glitch off the ground while
taxiing, a rotation on the lift-off sample, a recording cut mid-line at its end), a synthetic start-up (a pass at its end with no goals, a crash with the crash first, over the budget, never started), and the
newest real recording in the flights folder (`user://flights`: `~/.local/share/godot/app_userdata/iaf-reborn/flights`
on Linux, `~/Library/Application Support/Godot/app_userdata/iaf-reborn/flights` on macOS, or `IAF_FLIGHTS`) scored
against Ramon's take-off, skipped with a message when there is none. `IAF_TRAINING_WRITE=<dir>` keeps the synthetic
flights as JSONL. `cargo test -p iaf-tools --test training_cli`: the CLI from another working folder, a missing
airbases folder and a `--json` without a file. `sim::tests::training_rules_are_checked`: a training figure without a source and an unknown kind
are refused, an unknown goal is refused, and every take-off mission's runway is an end of its base's airbase file.

## 6. Open
- The F-16I's, F-16D's and F-35I's own empty weights and take-off speeds by weight (open).
- A start-up fault model (hot / hung start): none in the flight model.
- The roll's start and rotation thresholds checked against a real flight of each mission by the user.
- The 6-DoF's take-off roll is short (flight-model.md §9.6): the probe's Sufa lifts off after about 465 m at 180 kt.

## 7. The start in the game
A flight starts with a clean view, the flight running (the user, 2026-11-13; [front-end.md](front-end.md) §8). The
objective is in the briefing ([front-end.md](front-end.md) §10). A start-up flight starts with the pilot's notebook raised at its START-UP
page (§11; 2026-11-13, in place of the checklist card of the Mac play test, 2026-11-11).

The sim's jet starts parked cold: on its spot (airbases.md §9), engine off, no RPM, no electrical power, every screen,
the HUD and the lamps dark (`cockpit.power` 0). The throttle starts nothing (`Settings.throttle_starts_engine`, false
in the sim; in the original game any throttle command starts the engine at once, as before, on either flight model).
The start-up checklist by keys (§7.1) runs the jet's start sequence step by step; one command, **Start engine**
(Ctrl+E, record 117 of the sim's own `keys.json`, command 200, `IafFlight.start_engine`, a hidden developer shortcut
since 2026-11-08: not in the key list), runs it all at once
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
| throttle to OFF (§7.2) | the fuel cut: the engine winds down, the generators off at 52 %, stopped after about a minute | the same | §7.2 |
| engine stopped (`set_engine_on(false)`, the ejection) | no RPM; the power as it was; a new command starts from the beginning | the same | inferred |

The F-15I's (no mission flies it yet) is the F-16's (inferred). The F-35I's engine steps are the F-16's: no public
figure (inferred). The sound: the JFS's (the IPP's) whine, the engine clip of E1b (`SFX_START_ENGINE`) with its
pitch and level by the RPM, a light-off thump, and the JFS winding down at the generators ([sound.md](sound.md) §1.4). The probe measures 37 s to idle
for the F-16s and 47 s / 92 s for the F-35I (the recorder samples 10 times a second; the scene takes a few frames).

### 7.1 The start-up checklist by keys
Since 2026-11-08 (the user: "the first mission, which is just one click, is pointless") the start-up mission is the
real start by keys, step by step. The pilot's notebook (§11) shows the steps on its START-UP page, in English and
Hebrew: each step with its switch's name and place and the state to wait for, the steps taken ticked, the step to take
now marked, and a fault in red under it. Since 2026-11-13 it names no key (the user: "lets remove the kb hints"): the
briefing's How and the Keys screen list the keys. Each step but the idle is a key of the sim's own `keys.json` (records 119–124,
commands 210–215; `iaf-sim own` refuses a key bound twice) and a click on its switch in the 3D cockpit
([cockpit.md](cockpit.md) §5.2). The flight model takes each step
(`Start::press` in `crates/iaf-flight/src/sixdof/start.rs`, `IafFlight.start_step`); a step out of order has its
consequence and returns a fault, which ends the mission at once as a Fail with that fault first (§3.0).

The idle step has no key (the user, 2026-11-09): moving the throttle up from OFF, by its keys or the axis, is the step,
as the real throttle's idle-cutoff detent, once the starter step (JFS / IPP) is done (before it the throttle moves
alone and starts nothing). OFF is the throttle's bottom (2 % allowed for a lever's noise); a lever already up goes to OFF first. The briefing's How names the Throttle idle key (record 7, the 1 key) on that line (the user, 2026-11-09: "we have 1 for throttle"); the axis, the 0 key (Throttle up 5 %), the 1 key and a click on the throttle grip all make the step (the 1 key sets the throttle to idle, which is OFF, so the key itself takes the step at OFF);
The step reaches the flight model and the recording as the key did (`sim_flight.gd _throttle_step`), so the scorer
reads the same `checklist` event. The throttle goes back to OFF by its own key, Throttle OFF (§7.2).

| # | F-16I Sufa, F-16D Barak | key | timing | out of order | source |
|---|---|---|---|---|---|
| 1 | Main power: MAIN (the battery on) | Ctrl+B | at once | — | the checklist's order[^chk] |
| 2 | JFS: START 2 | Ctrl+J | cranks the engine to 20 % RPM in 15 s, then holds there | before main power: nothing runs, `no_power` | [^chk]; the 15 s inferred |
| 3 | Throttle to idle at 20 % RPM | the throttle up from OFF | light-off 5 s later, idle 15 s after it; the main generator at 52 %, the JFS off | below 20 %: a hot start, the engine shut down, `hot_start`; no rotation: no light-off, `no_rotation`; never: the JFS holds at 20 % | 20 % minimum[^chk]; 52 %[^f16net]; the times inferred |
| 4 | Avionics power: the four AVIONIC POWER switches ON, after the generators | Ctrl+A (or a click on each) | each switch's system 3 s later ([cockpit.md](cockpit.md) §5.2 "One by one") | before the generators: no power, `avionics_early` | inferred (the avionics go on after the engine start in the checklist[^chk]) |
| 5 | INS: stored-heading alignment | Ctrl+N | aligned 90 s later: the avionics up | without main power: `ins_no_power` | 90 s[^ins] (a full alignment takes about 8 minutes[^ins]) |
| 6 | Canopy: close and lock | Ctrl+K | at once; the canopy, up 30° at the cold start, comes down over 10 s | any time; taxiing with it up has no consequence | [^chk]; 30° and 10 s[^fgcanopy] |

| # | F-35I Adir | key | timing | out of order | source |
|---|---|---|---|---|---|
| 1 | Battery: ON | Ctrl+B | at once | — | battery, IPP, engine[^ayton] |
| 2 | IPP: START | Ctrl+J | runs 10 s, then holds | before the battery: `no_power` | [^ayton]; the 10 s inferred |
| 3 | Throttle to idle: the engine starts | the throttle up from OFF (in the 3D cockpit also the ENG switch or START, [cockpit.md](cockpit.md) §5.2) | cranks, lights and runs to idle by itself (the F-16's figures); the displays on the IPP's power | before the IPP: `no_ipp`; before the IPP is up to speed: `ipp_not_ready` | [^ayton]; inferred |
| 4 | Canopy: close and lock | Ctrl+K | at once; the canopy, its aft end up 30° about its front hinge at the cold start, comes down over 10 s | any time; taxiing with it up has no consequence | inferred (front-hinged: [f35i.md](../../docs/f35i.md) §4; the angle and time the F-16's) |

Each step's `wait` (mission data) says the state to wait for before the next step, in the table's figures (the JFS's
20 % RPM, the idle with the main generator, the displays, the INS's 90 s; the IPP's 10 s); the notebook and the
briefing's How show it under the step, the briefing beside a picture of the step's switch in the 3D cockpit
([front-end.md](front-end.md) §10).

The avionics of the F-35I report ready 90 s after the battery[^ayton].

### 7.2 The shutdown: the throttle to OFF
**Throttle OFF** (Shift+1, record 121 of the sim's `keys.json`, command 218) moves the throttle over the idle-cutoff
detent to OFF, which cuts the engine's fuel (T.O. checklist: "Retard THROTTLE to OFF"[^ep]). The 1 key and the axis
stop at idle: OFF takes its own key, as the real throttle's detent takes a deliberate move. In the 3D cockpit a
drag down on the throttle grip begun at idle sends the same command ([cockpit.md](cockpit.md) §5.2); the wheel and a
drag begun above idle stop at idle. The flight model
(`Start::cut_off` in `crates/iaf-flight/src/sixdof/start.rs`, `IafFlight.start_step("cutoff")`) then runs the
shutdown:

| what | when, from idle | source |
|---|---|---|
| thrust and fuel flow | none at once | the fuel cut |
| RPM | falls as e^(−t / 15 s): 52 % after 2 s, 20 % after 16 s, stopped (below 1 %) after 61 s | inferred: "about a minute"; with the fuel cut the RPM dies slowly[^bmshot] |
| main generator | off line below 52 %: the displays, the HUD and the avionics dark (`power` 1, the battery), the INS to align again | the generator's on-line RPM on the way up[^f16net], taken for the way down (inferred) |
| FTIT | falls with the RPM (`EngineTemps`, [cockpit.md](cockpit.md)) | inferred |
| sound | the engine loop pitches down and fades with the RPM, silent at the stop ([sound.md](sound.md) §1.4) | inferred |
| the F-35I | the same figures; its displays also drop at 52 % (the IPP is off once the engine runs) | inferred |

A restart is the start's own steps: the starter (Ctrl+J) once the RPM is below 20 % (the RPM it cranks to; before
that the key does nothing; inferred), then the throttle up from OFF at 20 % (§7.1), or Start engine (Ctrl+E) once
below 20 %; the starter above 20 % is the fault `starter_high` and the key is taken again later. An engine started by Start engine or running from the flight's start (an airborne start) lights from the starter
alone, as Start engine does (inferred: no checklist was flown to give the throttle's step). Before the starter step the
throttle moves alone. A cut-off with no fault (a cold or cranking engine) leaves the steps taken as they were.

The recording gets a `checklist` event with step `cutoff` and its fault: `shutdown` (the engine was running) or
`no_start` (it was lighting or accelerating to idle). A cold or cranking engine has nothing to cut: no fault. In a
training mission the fault fails it at once (§3.0) with "Engine shutdown: the throttle went to OFF with the engine
running." first in the debrief. Open: the air. In flight the real jet's emergency power unit and standby generator
keep the displays up, and the engine windmills rather than stopping; the sim models neither. The mission passes when every step is done
(`skip_<step>` names a step never taken), the engine idles and the avionics are up within the time budget (5 min,
inferred), and nothing failed, at its end. The steps and their notebook lines are mission data (`training.checklist`,
[data-formats.md](data-formats.md) §5); each key press is a `checklist` event in the recording (`step`, and `fault`
when it was refused). The take-off missions still start cold: the same keys start the jet there, the notebook stowed.

The notebook's pictures are in §11.

## 8. The radio menu and the tower
The **Call the tower** key (Ctrl+T) opens a numbered list over the view; a call's number picks it, any other key
closes the list. Since 2026-11-13 (the user: "all radio calls should always be available. on ground show only starting
calls, in the air show landing") the list holds every ground call on the ground (start-up, taxi, line-up, take-off,
always 1–4) and the landing call in the air (`training::radio_calls`). In a training mission the call the moment
expects is marked "(next)" / "(הבאה)" (`training::next_call`, the "marked when" column). A ground call made before
the clearance it follows (take-off before line-up, line-up before taxi, taxi before start-up;
`training::missing_before`) gets "Alpha, negative, hold position, request line-up first" ("Alpha, שלילי, המתנה במקום,
יש לבקש כניסה למסלול קודם"; `ACFT_NEGATIVE`) and clears nothing; a call repeated gets its answer again. A wrong call
alone never fails a mission; acting without the clearance does (§3.3). No "say again" or "radio check" call exists;
the air has only the landing call (open: the calls the landing and navigation lessons need, such as joining the
pattern, final and go-around, have no tower lines yet).

| call | English | Hebrew | marked when | the tower answers |
|---|---|---|---|---|
| start-up | Request start-up | בקשת התנעה | on the ground with the engine off | "Alpha, cleared to start" (`ACFT_CLEAR_TO_START`) |
| taxi | Request taxi | בקשת הסעה | on the ground with the engine running and the avionics up, taxi not yet (also after a start without start-up approval) | with the engine running: "Alpha, good morning, taxi to runway 25 right" (`ACFT_TAXI_TO_RUNWAY`); else "hold position" |
| line-up | Request line-up | בקשת כניסה למסלול | on the ground at the holding point or past it (no farther from the lineup point than the holding point plus 50 m, inferred; the holding point is the base's taxi-out path's last point before the lineup, `iaf.ibx` `FromTaxiPt`) with taxi approved, line-up not yet (since 2026-11-13) | within 400 m of the lineup point with the runway clear: "line up runway 25 right, wind calm" (`ACFT_CLEAR_TO_LINEUP_NW`; ours: the original's band starts 200 m out, which leaves out the holding point); else "hold position" |
| take-off | Request take-off | בקשת המראה | at the holding point or past it with line-up approved, take-off not yet | the original tower's rule on the ground (docs/radio.md §2 `ground()`): lined up in the lineup zone: "cleared for take-off"; 200–400 m from the lineup point with the runway clear: "line up runway 25 right, wind calm"; else "hold position" |
| landing | Contact tower (landing) | קריאה למגדל (נחיתה) | in the air | the original's Ctrl+T (docs/radio.md §2): "proceed to runway …" in the air |

A call is approved by the tower's answer named in its row; "hold position" or "line up" leaves it unapproved, to ask
again. The rules are in `crates/iaf-tools/src/training.rs` (`IafTraining.radio_calls`, `next_call`,
`missing_before`); `sim_flight.gd` lists their result. Between the calls (the engine starting, the taxi to the holding
point) no call is marked. A flight that starts on the ground with the engine running (at the lineup point) has taxi
and line-up approved, so take-off is marked at once.

The pilot's call is printed and spoken by the pilot's voice through the helmet chain ("Ramon tower, Alpha, request
taxi"; sound.md §5.2), then 0.6 s of quiet, then the tower's answer printed and spoken by the tower's voice (sound.md
§3), then the pilot's "Roger". The landing call is "request landing" to the radio's current base, then the
original's Ctrl+T. The taxi greeting follows the mission's clock (its start time plus the sim time): good
morning 05:00–12:00, good afternoon 12:00–17:00, good evening 17:00–05:00 (`Settings.tower_greeting` in
`modern-iaf/sim_settings.gd`; the original game keeps its own table, docs/radio.md §2 code 0;
`modern-iaf/tests/test_radio_calls.gd` at 04, 08, 14, 16, 20 and 23 h). The lines show in the sim's band over the flight
([front-end.md](front-end.md) §8), wholly in the game's language: in Hebrew the pilot's call ("מגדל רמון, Alpha,
בקשת הסעה") and the tower's answer from each phrase particle's Hebrew text (`text_he` in
`modern-iaf/data/sounds/voices.json`, compiled into `phraseparticles_he.trx`: "Alpha, בוקר טוב, הסעה למסלול 25 ימני");
only the callsigns and the runway numbers stay Latin and digits. The voice stays English until the Hebrew voice's
licence is decided (sound.md §5.4). The
tower is the base within 18.54 km: every base of the own `iaf.ibx` talks (Ramon, Ramat David, Hatzerim, Nevatim;
`Settings.tower_bases`); the mission's base's tower names the mission's runway (`"runway"`), the others their own. A request leaves the tower's
state machine as it is. In the menu the tower no longer talks on
its own on the ground (the original game's tower is unchanged). Each pick is a `radio` event in the recording (§9),
which the debrief counts as `tower_calls`. The scorer has no rule on the calls (a take-off without them still passes).

A take-off mission's `training.steps` (mission data) lists the pilot's sequence for the briefing's How: each call
on its own at its place (request start-up before the engine start, taxi once at idle with the avionics up, line-up at
the holding point, take-off once lined up), each with its key, the menu's pick and the answer to wait for (the table
above). The picks are the menu's fixed order: start-up 1, taxi 2, line-up 3, take-off 4.

Taxi: the jet taxis on the base's taxiways to the lineup (the probe follows the own `iaf.ibx`'s taxi path). The
take-off passes by §3.2.

## 9. Scoring in the game, the debrief record and the pilot log
`modern-iaf/flight/sim_flight.gd` (the sim's part of the flight scene, `Settings.flight_addon`) runs a mission whose
compiled file has `sim.training` with an `IafTraining` (crates/iaf-godot/src/training.rs) opened on the readable
mission `modern-iaf/data/missions/<id>.json` and the airbase files:
- every frame `IafTraining.check` (§3.0) decides whether the mission failed; on a fail the mission ends at once
  (off the pavement: a `surface` event first);
- a start-up is scored once the engine idles with the avionics up, a take-off once airborne (then every 3 s until it
  passes; since 2026-11-13 also with the gear down, the user: "why I didn't get completed mission … after I
  airborned?"). A goal still missing shows in the panel ("To complete: raise the gear." / "To complete: climb out on
  the runway heading with the gear up."); a take-off that cannot pass any more (`wrong_runway`, `excursion`,
  `over_time`) ends at once as a Fail; a pass is stored at once and kept, the flight going on until the player ends
  it (since 2026-11-13); 5 s past its time budget it ends as scored;
- the player ending the flight first (Esc → End the flight, Ctrl+Q) ends the mission there, scored as it stands;
- at the goal a banner in the front end's look (navy, Heebo) says "Mission complete" / "המשימה הושלמה" and "Fly on,
  or Esc → End the flight for the debrief" for 10 s; a fail shows "Fail" with the reason that ended it and 5 s later
  (real time, `end_hold_s`) the flight ends into the debrief;
- an ejection ends the sortie (`Settings.eject_ends_sortie`, the sim only): every sound and the radio stop at once
  (`flight_sounds.gd silence`, no radio menu), the view stays outside on the seat and the jet at any height (no
  FlyTSD), the recording gets an `eject` event and the mission fails with `ejected` first. The original game's
  ejection runs as before (tests/godot/test_eject.gd);
- `IafTraining.score(recording, mission, airbases)` runs `training::score_files` on the recording so far, with the
  live check's reason first;
- the debrief record (§4, plus `flight`: the recording's path, `date`: the end, `elapsed_s`: the flight's length) is
  stored as a sortie of the pilot (the default pilot 14 until E2's pilot list) in the records database
  `user://modern-iaf.sqlite` (`IafPilotLog.log_sortie`, [storage.md](storage.md) §5), and `Settings.flown_sortie`
  names it for the front end;
- ending the flight opens the front end's debrief sheet.

Scoring needs the recorder (Extras, on by default): with it off the flight is not scored (a warning in the log). Tests
record beside the records database, in a temporary folder. The recorder's version 2 (`Settings.blackbox_version`, [data-formats.md](data-formats.md) §13) adds `rpm`
(%) and `avionics`.

`tools/flight_timeline.py <recording> --debrief <debrief.json> [--html f.html]` (a record out of the database:
[storage.md](storage.md) §5) shows the debrief with the flight's
timeline (the radio calls, the lift-off) and the start's steps from the RPM column.

## 10. The probe and a real run
`modern-iaf/tests/test_mvp.gd` (item F's probe, started here; `-- --only clearance`: each §3.3 phase done without
its clearance, the Sufa, fails with its reason, the tower's line once and the recording's event) flies both missions for the Sufa (Ramon), the Barak
(Ramat David) and the F-35I (Nevatim) headless with scripted inputs at 6× time: the start-up (cold, the throttle
starts nothing, the checklist by its keys, the columns, the sortie's debrief, its pass in the pilot log; the JFS before the main
power fails at once) and the take-off (the four radio
calls and their answers, line-up at the holding point, a taxi along the base's taxi path to the lineup (on the taxi line, slowing to 2.5 m/s
through each turn: off the pavement fails, §3.0), the roll on the centreline, the rotation,
gear up, the debrief's goals), each ending in Pass, and a crash in the Sufa's start-up ending it at once in a Fail
with the crash first. `-- --jet f16i` / `-- --only startup` narrow it. Item F adds the front end, Hebrew, the
temp-root run and the other platforms.

`./start-modern-iaf -- --mission <id>` flies one mission at once (`modern-iaf/flight/fly.gd`), then shows its debrief: 2011 / 2012 Ramon
start-up / take-off, 2021 / 2022 Ramat David, 2031 / 2032 Nevatim.
`modern-iaf/tests/_training_shot.gd` takes the pictures in a real render (its header).

## 11. The pilot's checklist notebook
Since 2026-11-13 (the user's decisions: "a checklist notebook that opens on a key press, in every mission"; look A of
the second mock-up approved the same day) every flight of the sim carries a paper notebook on the pilot's right thigh.
`modern-iaf/flight/notebook.gd` draws the notebook; `modern-iaf/flight/kneeboard.gd` fills it from the flight and
places it; `sim_flight.gd` holds one and passes it the key and the checklist's steps.

**The key.** Checklist notebook, in Hebrew בד"ח (the user, 2026-11-13) (H; record 118 of the sim's `keys.json`, command 203; the Keys screen rebinds it as any
other) raises it and stows it again. The flight keeps running. The notebook itself names no key. On 2026-11-13 it moved
from K to its own key (the user: "Give notebook its own key"): K had shared it with the GPS bomb's PRE / VIS switch
([weapons.md](../../docs/weapons.md) §13.2), which has K to itself again.

**Stowed** it lies on the right thigh in the 3D cockpit, a 13 cm board (its place and tilt per cockpit model:
`stowed` in `data/notebook.json`). The notebook is drawn into a texture only when its page changes (a step taken, a
turn), so stowed it costs one textured quad.

**Raised** it is a 460 x 620 px panel (at the 1080-high canvas) at the screen's lower right, 26 px from the edge, in
Hebrew too (the thigh's side), never the screen's centre. A start-up mission starts with it raised at its START-UP
page; every other flight starts with it stowed. In Hebrew the page is mirrored: the tabs run down the board's left
edge, the text right to left.

**The tabs and the pages.**

| tab (English / Hebrew) | the page | from |
|---|---|---|
| START-UP / התנעה | the start-up checklist: each step's line, its switch and place (`where`), the state to wait for (`wait`); the steps whose switches are on ticked (a switch back off unticks its step, [cockpit.md](cockpit.md) "Both ways"), the step to take now on a yellow band with ▶ (◀ in Hebrew), a refused step's fault in red under it | the flight's own `training.checklist` (§7.1), else the one of the start-up mission of the flight's jet |
| TAXI / T-O / הסעה / המראה | the radio calls, the taxi and the take-off as numbered steps, the runway's designator, heading, length and elevation | the take-off mission's `training.steps` (§8) of the flight's base (else its jet); the base's airbase file |
| RADIO / קשר | the callsign, the base's frequencies (name, MHz, VHF / UHF), the four calls with the frequency to call on and the tower's answer | `data/notebook.json` `radio` and `calls`; the call names are the radio menu's (`sim_flight.gd` `ITEMS`) |
| LANDING / נחיתה | the call, the gear, the final's AOA, the touchdown, the throttle to OFF on the spot | `data/notebook.json` `pages.<f16 / f35i>.landing` |
| EMERGENCY / חירום (a red tab, a red strip down the page) | the hot start, an engine fire on the ground, the ejection | `pages.<family>.emergency` |
| DATA / נתונים | the mission, the base and its ICAO code, the time, the wind, the jet, the runway, the route's first point | the mission's readable file; the airbase file |

A section is cut into pages that fit the paper: its blocks (a step, a table, a heading) are measured at the page's
width and the page breaks between them. The pages turn by:
- a click on a tab: that section's first page;
- the page's own ‹ and › at its foot, with the section's page count between them ("1 / 2"; the user's "a clear way
  to move to the next page in the same section");
- the mouse wheel over the notebook, and PgUp / PgDn while it is raised.

Past a section's last page the next section's first page opens; back from its first page, the previous section's
last. ‹ dims on the notebook's first page, › on its last. On the START-UP tab the page follows the step to take now.

**No key hints, no title, no clip** (the user, 2026-11-13: "lets remove the kb hints"): the steps name the switch and
its place. In the pilot's first start-up mission only a help line stands over the raised notebook ("H stow · PgUp /
PgDn or wheel: page · click a tab", the key as bound); `notebook_help_seen` in the settings file's `[sim]` section
remembers it.

**The training highlight.** In a start-up training mission a ring (the sim's sky blue, 4 px with a glow) stands on the
current step's switch: the controls of the 3D cockpit that send its command (`<model>_controls.json`, the F-16's engine
step the throttle grip), their mesh bounds projected through the cockpit's camera every frame and the ring drawn 6 px
outside them (a control's `ring`, a radius in metres, overrides the bounds). A step may also watch a gauge (`gauges`
in `data/notebook.json`: the F-16's RPM needle for the idle step, its ring labelled "RPM · watch 20 %"). A part out of
the view (or behind the eye) gets a pointer at the screen's edge toward it, with the step's line ("▼ Throttle to idle
at 20 % RPM"). When the raised notebook would cover a ring, it slides down its side to 18 px below the ring (at least
220 px of it left on the screen), else up above it.

**Every checklist switch clickable.** With no key hints, each step's switch must answer the mouse. On the pages:

| page | step | clickable |
|---|---|---|
| START-UP | every step of the Sufa, the Barak and the Adir: MAIN PWR, JFS, the throttle, the four AVIONIC POWER switches, the INS knob, the canopy handle; BATT, IPP, ENG / START, the throttle, CANOPY | yes ([cockpit.md](cockpit.md) §5.2; `test_mvp.gd` clicks each, the F-35I's CANOPY included) |
| LANDING | the landing gear handle (both cockpits) | yes since 2026-11-13: the G key's command, refused on the ground |
| LANDING, EMERGENCY | the throttle to OFF over the idle detent | no: a click on the grip moves it up 5 %; OFF is Shift + 1 only (open) |
| LANDING | the wheel brakes (the rudder pedals) | no: no pedal part answers the mouse (open) |
| EMERGENCY | JFS OFF, MAIN PWR OFF, BATT OFF | no: a click turns these on only (open) |
| EMERGENCY | the ejection handle | no: no part of the seat answers the mouse (open) |
| not on the pages | FCR, RDR ALT | no: FlightGear's console has no part for them (cockpit.md §5.2); the start-up steps leave them out |

**The radio frequencies.** `data/notebook.json` `radio`, by base, in MHz. Published: Ramon APP 120.9[^oa-llrm],
Ramat David TWR 118.6 and APP 125.8[^oa-llrd], Nevatim APP 120.9[^oa-llnv]. Every other frequency (the ground and the
tower at Ramon and Nevatim, Ramat David's ground, all of Hatzerim's) is invented: no published military frequency was
found. The page shows them all alike. The calls' "on" (ground for the start-up and the taxi, the tower for the
take-off and the landing) is inferred: the sim has one tower voice for all four.

**The other pages' sources.** The F-16's hot start follows the T.O. checklist's steps[^ep] (weak); the fire on the
ground, the ejection and the F-35I's pages are inferred; the F-16's on-speed AOA of 13° is open (no primary source
checked).

**The frame cost** (`_notebook_shot.gd` with `NB_BENCH=1`, 1920 x 1080, this Linux laptop's Intel Iris Xe, 300 frames
each, the scripts' process time and the GPU's render time of the window and the cockpit's world):

NB_BENCH_TABLE

**The pictures** (`modern-iaf/tests/_notebook_shot.gd`, a real render, its header):

NB_PICTURES

**Checks.** `modern-iaf/tests/test_notebook.gd` (headless): the start-up mission raises it at START-UP with the first
step current and no key on the page, the help line once, H stows it into the thigh's texture and raises it (K leaves it), a step
ticks, a tab click, the wheel, PgUp / PgDn and the page's ‹ › turn it across the sections, every section has a page,
RADIO holds Ramon's frequencies, the board at the right edge, the JFS step's mark, Hebrew mirrored, a take-off flight
stowed with the Sufa's start-up checklist and runway 25R on TAXI / T-O. `test_mvp.gd` and `test_flight_ui.gd` read the
current step from the notebook.

**Open.** The GUIDE tab (the jet's pilot guide from one source shared with the original game's guides, and the front
end's Guides screen drawing the same pages) is the next part. Gauge rings for the other steps; the throttle OFF, the
brakes, the ejection handle and the switches' OFF positions by the mouse.

[^ins]: F-16.net forum, "INS alignment time and time to takeoff from cold start" (a normal alignment about 8 minutes, a stored-heading alignment about 90 s), https://www.f-16.net/forum/viewtopic.php?p=7943; Eagle Dynamics forum, "What is the difference between stored INS align and normal INS align in the F-16C Viper", https://forum.dcs.world/topic/267433-what-is-the-difference-between-stored-ins-align-and-normal-ins-align-in-the-f-16c-viper (both weak: forums)
[^w-f16]: Wikipedia, "General Dynamics F-16 Fighting Falcon", Specifications (F-16C Block 50 / 52): empty weight 18,900 lb (8,573 kg), https://en.wikipedia.org/wiki/General_Dynamics_F-16_Fighting_Falcon
[^w-f35]: Wikipedia, "Lockheed Martin F-35 Lightning II", Specifications (F-35A): empty weight 29,300 lb (13,290 kg), https://en.wikipedia.org/wiki/Lockheed_Martin_F-35_Lightning_II
[^bms]: Falcon BMS forum, "Rotation speed" (the take-off speed 70 kt plus 3 kt per 1000 lb of gross weight; rotate at 170 kt with an air-to-air load, 180 kt heavy), https://forum.falcon-bms.com/post/314659
[^wn]: WION, the F-35's minimum lift-off speed about 165 kt (weak), https://www.wionews.com/photos/how-does-the-f-35-fighter-jet-stand-out-in-takeoff-speed-and-design-here-s-its-minimum-lift-off-speed-1752767093279
[^ayton]: Mark Ayton, "Blue Sky OPS", AIR International, 26 April 2012, quoted on F-16.net, "Engine start up procedure" (three switch selections: battery, IPP, engine; "After 90 seconds, if there are no problems, the aircraft declares itself ready for flight"), https://www.f-16.net/forum/viewtopic.php?p=317934
[^ep]: F-16 emergency procedures flashcards (sim community, after the T.O.; weak): "Retard THROTTLE to OFF, MONITOR FTIT indicator, If FTIT remains above 500C, MOTOR ENGINE with JFS until FTIT is below 200C", https://m.brainscape.com/flashcards/6169806/packs/9535586
[^bmshot]: Falcon BMS forum, "Recover from hot start" (a player: after the throttle to cutoff the "RPM die slowly"; weak: a forum, a simulation), https://forum.falcon-bms.com/post/267868
[^fgcanopy]: FlightGear F-16 (github.com/NikolaiVChr/f16 at ef4f192, GPL-2.0-or-later): `Models/F-16.xml`, the canopy's rotate animation (`canopy/position-norm` × 30°, centred aft of the cockpit), and `Systems/jsb-controls.xml`, `fcs/canopy-control-1` (shut to open in 10 s), https://github.com/NikolaiVChr/f16/blob/ef4f192f06243cf4061c2be794511db0576ac2f9/Systems/jsb-controls.xml
[^chk]: F-16 checklist (sim community, after the T.O. checklist; weak): "THROTTLE – Advance to IDLE (20% RPM Min)", https://www.scribd.com/document/38303072/Checklist-Main
[^jfs50]: F-16.net forum, "JFS and avionics question" (the flight manual: "As the engine accelerates through 50 % rpm, a sensor causes the JFS to shut down automatically"; about 50 % on a P&W and 54 % on a GE engine), https://www.f-16.net/forum/viewtopic.php?p=13518
[^f16net]: F-16.net forum, "Main PWR on the F-16", Davis83, 7 December 2010 (the engine self-sustaining at about 52 % RPM, the JFS disengaged, the engine driving the hydraulic pumps and the main and standby generators), https://www.f-16.net/forum/viewtopic.php?p=186672
[^oa-llrm]: OurAirports, Ramon Airbase (LLRM), frequencies: APP 120.9 MHz, https://ourairports.com/airports/LLRM/
[^oa-llrd]: OurAirports, Ramat David Airbase (LLRD), frequencies: TWR 118.6 MHz, APP 125.8 MHz, https://ourairports.com/airports/LLRD/
[^oa-llnv]: OurAirports, Nevatim Airbase (LLNV), frequencies: APP 120.9 MHz, https://ourairports.com/airports/LLNV/
