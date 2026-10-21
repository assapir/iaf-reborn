# The player's autopilot

This doc specifies the player's autopilot as the original v1.1 exe runs it: its modes, what engages and disengages it,
the loops it flies and the landing training mission 312. It is for developers who port or maintain
`crates/iaf-flight/src/autopilot.rs` and `game/controls/autopilot.gd`. All addresses are v1.1.

**Terms**
- **AI**: the computer-flown aircraft. **FM**: flight model ([flight-model.md](flight-model.md)).
- **GEV**: a game event, the code a key or control posts to the player controller (`ctl`).
- **Control loop** (suffix **CL**): one step of an AI flight behaviour, such as LevelFlightCL or LandingCL
  (`atp.ControlLoop.h`, [ai.md](ai.md) §8).
- **NAV**: navigation mode, which flies the route's waypoints. **ETA**: estimated time of arrival.
- **HUD**: head-up display. **MFD**: multi-function display. **ILS**: instrument landing system.
- **AGL**: above ground level. **KA**, **CH**, **CA**, **LW**: the KeepAttitude, ChangeHeading, ChangeAlt and
  LevelWingsPitch0Accel legs of the landing circuit, numbered in flying order.

The A key ("Autopilot level/navigation/off", key record 18, GEV 0x10) cycles the autopilot off → **level** → **NAV** →
off. The autopilot flies the jet through the AI's control loops ([ai.md](ai.md) §8), with the same control law:
`crates/iaf-flight/src/autopilot.rs` runs both. The player's loops run with the FM mode left at 0, so the jet keeps
the player's flight-model rules (stall, crash checks, afterburner).

## 1. Mode and lamp (player controller `FUN_0044a240`)

`ctl+0x974` holds the mode: 0 off, 1 level, 2 NAV. Lamp 8 (`LIGHT008`, [cockpit.md](cockpit.md) panel lights) is on
while the mode is 1 or 2. Every change posts FM motion 0xf `(mode, waypoint index)`, where the waypoint index is the
NAV object's current waypoint (`FUN_00594c10`, +0x44).

| event | rule |
|---|---|
| flight start (@4483d7) | **airborne start → mode 1** (lamp on); ground start → 0 |
| GEV 0x10 (A key, lamp click, the landing's StopPlane) (@44d13a) | refused while system 6 (autopilot) is damaged (`FUN_00450d40(6)`). On the ground the mode is first forced to 2, so the press always goes to off. 0 → 1 (lamp on); 1 → 2; 2 → 0 (lamp off, throttle re-sync) |
| GEV 1 stick (@44bd0e) | lamp on and the event's x and y both within ±51 (of ±100): the autopilot **keeps the stick** (the event is dropped). Otherwise the lamp goes off, mode 0, motion 0xf (0), throttle re-sync unless the old mode was 1, then the stick is posted |
| GEV 10 rudder (case 0xa) | always posted; lamp on and \|x\| ≥ 51: lamp off, mode 0, motion 0xf (0) (no re-sync) |
| GEV 4 / 9 throttle, 5 / 6 RPM ± 5 % | dropped while the mode is 2 (NAV holds the throttle) |
| damage 6 (`FUN_0044d760` case 6) | lamp on: lamp off and motion 0xf (0). `ctl+0x974` keeps its value (as coded), but the A key is refused from now on anyway |
| ejection (`FUN_005485a0`) | motion 0xf (0) |

The keyboard sends ±100, so any roll or pitch key press disengages the autopilot. A key release sends 0, which is
dropped. The keys build one GEV 1 from both axes (`FUN_004e0b80` adds the other axis's last value), so the ±51 test
sees both axes.

**Throttle re-sync** (`FUN_005a29d0`, when leaving NAV) posts motion 2 with the throttle axis × 0.01:
- With a throttle axis, the throttle goes back to the lever (the axis's last value, docs/controls.md §5;
  port: `Joystick.throttle_axis()`).
- When `FUN_004e0f40` returns −1 (THROTTLE set to keyboard on the Devices page, or no joystick), the value is 0.74
  (military), posted only when airborne.

UNCERTAIN: the controller gates this on a vehicle getter (vtbl+0x6c) == 0x1e, which was not traced. The port re-syncs
on every exit from NAV.

**HUD** (`FUN_0052ef20` @52efd3): the G readout line shows `AP LVL` (mode 1) or `AP NAV` (mode 2) in place of the G
value (strings 0x65d50c / 0x65d514). The autopilot is silent: its sound hook `FUN_0058a330` is empty. The damage MFD
page has the A/P row (system 6).

## 2. FM motion 0xf (`FUN_005a1e40`)

| arg | call | loop (control-loop manager offset) |
|---|---|---|
| 0 | `5c8800` | cancel the root loop (the stick stays where it was) |
| 1 | `5c82c0` | **LevelFlightCL** (+0x4528, vtable 0x612c30, Init `5cd8c0`) |
| 2, waypoint action 7 (land) | `5c7d80` | **GoHomeCL** (+0x1ed0): the AI's go-home and landing, [ai.md](ai.md) §8.3. Also sets `DAT_00843dec` = 1 (reader not found) |
| 2, other waypoint | `5c7bc0` | **Fly2WayPt** (+0x4f8) to the waypoint with its ETA (record +0x10). With an empty route, the loop starts uninitialised (UNCERTAIN; the port then flies nothing) |

The loop's first tick comes 0.5 s later (`5c9a90`).

### 2.1 Level (LevelFlightCL)
1. **LevelWingsPitch0** (`5d2140`, vtable 0x613340) with the pitch tolerance set to **0.0035 rad** (+0x1d0): wings
   level and flight-path pitch 0. Done when \|pitch\| ≤ 0.0035 rad and \|roll\| ≤ 1° (`0x8455d0` = π/180).
2. **KeepOrientation** (`5d9d30`, vtable 0x612d60). FirstRun `5da010` stores the flight-path pitch, the heading and the
   speed at that moment. Each tick:
   - roll target = clamp(wrap(stored heading − heading), ±30°) (`0x84562c` = `0x845634` = π/6);
   - pitch law to the stored pitch;
   - throttle: the speed law to the stored speed runs only in an AI mode (`5c89f0` ≠ 0). For the player the
     **throttle stays manual**: the loop posts a throttle only when the ground watch takes over (UNCERTAIN: that
     slot is left uninitialised for the player; the port starts it at 0, so the watch's 250 m/s law
     applies).
   - It never ends.

So level mode holds the heading and a level flight path (about the altitude at levelling), at the player's
throttle.

### 2.2 NAV
**Fly2WayPt** ([ai.md](ai.md) §8.4) flies to the current waypoint with the ETA speed law, so NAV holds the throttle.
In FM mode 0 its FirstRun (`5d6fb0`) keeps the 1852 m PassWaypoint radius; the larger start-inside radii apply in AI
modes only. Once the waypoint is passed, the stick is centred. The sequencing below then posts the next waypoint.

**Waypoint sequencing** (`FUN_00452960`, every controller update `FUN_0044a1a0`). The NAV object holds +0x44 (the
current waypoint), +0x48 (the "inside" flag) and +0x40 (the closest distance so far):
```
w = route[+0x44]; act5 = w.action == 5; d = |pos − w| (2-D); near = act5 && d < 18540
inside = |x − w.x| ≤ 1854 && y ≥ w.y − 1854          // no northern edge: as coded
if !+0x48:  if inside: +0x48 = 1;  return
if !inside && (!act5 || near): return
if d < +0x40: +0x40 = d; return                      // still closing
if near && mode != 2: return
if +0x44 + 1 < count:  next waypoint (4532a0); +0x40 = distance to it; event "FlightControllerWayptReport" at +3 s
```
Next / previous waypoint (`4532a0` / `453370`, also the W / Shift+W keys) wraps the index, clears +0x48, sets +0x40 =
1112400, and in NAV posts motion 0xf (2, new index). The waypoint-report radio (`54dc00`, 3 s later) is built
(docs/radio.md §4). `4532a0` then calls `440e90(index)` on the jet's brain (`S+0x2c`): it sets the brain's waypoint
index +0x88 (docs/ai.md §7.2) and re-selects the same index on this NAV object (`453450` on controller +0x380).
The port sets the flight's brain index (`IafFlight.ap_set_waypoint_index`) in `set_waypoint`, so after Fly
(docs/views.md §1) the old jet's brain flies on from the player's waypoint. The brain index also feeds the
leader-death hand-over (`440eb0` → `440ed0`: the wingman takes the dead leader's index, docs/ai.md §7.2).

World scale Real ([world-scale.md](world-scale.md) §3.3): the bases the autopilot reads (lineup, RunwayNumber, taxi
points, hangars) are the moved ones; RunwayNumber is the real heading as a float, so the circuit, the final approach
and the take-off roll follow the real runway. The pattern's sizes stay the exe's fixed metres. In Real only, the final
approach and the float before touchdown steer to the centreline with a damped law (`align_final`, world-scale.md
§4.3) instead of FinalApproach's underdamped one.

### 2.3 Landing (GoHomeCL in FM mode 0)
- Gear and flaps go down at landing step 7, as for the AI. The commands reach the levers through the controller.
  The port mirrors them on the cockpit levers, so the gear's 300 kt rule and the flaps damage still apply.
  Step 7 comes when LW2 ends, and LW2 ends at any speed above its 102.944 m/s target. So a jet still faster than
  300 kt there keeps its gear up and lands on its belly (with Original rules, an F-35I at mission 214's Home
  waypoint: 369 kt at step 7); the mission's own jet slows to 220 kt first and lands on its gear.
- Ours, Flight data = Real (`Params::gear_speed_wait`; the F-35I always flies it): in the player's landing, LW2 also
  waits for 150 m/s (292 kt), at idle and wings level, so step 7's gear command comes under the 300 kt limit. The
  Real jets enter faster (the F-16 Real: 371 kt at LW2 from 312's start at 550 kt). The AI's gear has no lever limit
  and is unchanged.
- The pitch law's "gear / flaps / brakes in above 150 m/s" clean-up is skipped in modes 0 and 8.
- The ChangeHeading2PtAcu legs run without the ground watch (modes 0 and 8).
- LandingCL Init (`5d36d2`): the stop condition is **1.0295 m/s** in FM mode 0 (25.736 m/s in mode 8). The children
  end with StopPlane: TaxiCL and ParkInHangar are added only in mode 8 (`5d43e0`).
- StopPlane done (`5d4b22`): in mode 0 it posts **GEV 0x10 forced** (the A key), which turns the autopilot off from
  NAV. (Mode 0 lacks a landed handler.)

### 2.4 Runway into the wind (ours, Better physics "Wind and turbulence")
**The original** flies every base one way, whatever the wind:
- Each iaf.ibx base has one lineup point and one `RunwayNumber` (`54eda0`). The AI's take-off taxi ends at that lineup
  (TaxiCL), the landing circuit lands at it on that heading (LandingCL `5d2b30`, FinalApproach `5d4c50`), and the HUD
  ILS points down it (`460130`).
- The tower speaks `RunwayNumber / 10` in every call (`551c20`, [radio.md](radio.md) §2). The wind (`551320`) only
  changes "wind is NN knots" / "no wind".
- A ground start is where the mission places the jet: the entity's position and heading (`5a5820`, the engine runs
  within 100 m of the lineup point). Missions place lined-up jets at the lineup, others at hangars and shelters.

**Ours**, with the switch on, the tower picks the runway end into the wind:
- **The rule** (`airbase::wind_reverses`): a wind of at least 5 kt (`INTO_WIND_KT`) blowing from more than 90° off the
  main runway's true heading turns the base to that runway's other end. That end's heading is then nearest the wind's
  "from" direction. At exactly 90° the base keeps its own. The missions' winds are 0, 10, 15 or 20 kt, so every
  announced wind counts and a calm never does. The wind and its direction are radio.md §2's, picked once per flight
  with the mission (`Settings.runway_wind`).
- **Only runways that exist and have the base's data.** The tower picks between the two ends of the main runway: the
  runway through the lineup point (airbases.json's first runway; World scale Real: the real runway the base sits on,
  [world-scale.md](world-scale.md) §3.3). The crossing runways of Ramon, David, TelNof, Kuzeir and Bley have no lineup,
  taxi path or approach in iaf.ibx, so the tower never picks them.
- **The other end** (`Airbase::reversed`, the game frame, then World scale Real's move): the lineup point mirrored about
  the runway's middle (as far from the far threshold as the original lineup is from its own), heading + 180°.
  Without measured ends: 3000 m ahead.
- **Departure:** the hangars' path to the old lineup, then down the runway to the new lineup (a backtrack), where the
  jet turns round.
- **Arrival:** the departure path backwards, from the old lineup's end to the hangar turn point and the hangar.
- **Ground starts:** a mission jet lined up on a turned runway (within 400 m of the lineup, within 45° of its heading,
  on the ground) starts at the other end's lineup, its offset turned 180° (a wingman behind the leader stays behind
  it), heading + 180° (`Airbase::to_reversed_lineup`, `MissionRuntime._into_wind`). The original puts lined-up starts
  on the lineup point, so ours puts them on the chosen end's. A jet at a hangar or shelter stays there and taxis.
- **The tower** names the chosen end in every call. In World scale Real it adds a parallel runway's letter
  ("taxi to runway 7 right"; radio.md §1).
- **Taxi signs:** a sign of the turned runway shows the chosen end's number ("09"; Real: "07R"), so the signs lead to
  the end the tower names (`IafBases.sign_label`).
- **The autopilot, the AI, the HUD ILS** read the turned bases (`bases::map_airbases`). The player's circuit, the AI's
  take-offs and landings and the ILS all fly the chosen end, in both world scales.
- **Training missions keep their runway** (`Settings.TRAINING_MISSIONS`: 311–315, 321–326). Their instructor markers
  and circuits are laid out for it (§3). Every one of them has a calm wind (misc 0x46a = 0), so they also fly calm.
- Tests: `ramat_david_into_the_wind` (autopilot.rs: the rule, the turned lineup, an AI jet's backtrack and take-off on
  09, a landing on 09 and the taxi back to a hangar), base_move.rs `the_moved_lineup_is_on_runway_ground` (every
  moved base's other end on runway ground, on the real reciprocal heading), `…_into_the_wind_…_moved_ramon` (take-off
  and landing on Ramon's 07R), `tests/godot/test_wind_runway.gd` (the tower's calls, the signs, the starts, the
  cases without a turn, World scale Real's letter).

### 2.5 Unbalanced stores (ours, Better physics "Asymmetric stores")
- The switch adds the stores' rolling moment to the roll command as a stick deflection
  ([flight-model.md](flight-model.md) §10). The roll laws (`5c9bc0`, `5cb4d0`) are proportional only, so against
  that bias they hold a steady bank and the jet drifts sideways. The bias grows as the speed falls, most in the float
  before touchdown.
- So while a loop runs (`Aircraft::stores_trim`, set by `Autopilot::step` and `player_mode`), the flight model
  adds the stick that cancels the moment, within full stick: `p_cmd = MaxRollRate · clamp(clamp(stick − s, −1, 1) +
  s, −1, 1)`, s the stores' stick. The autopilot's own stick on the levers is unchanged.
- Example: 312's F-16 carries a balanced load, but the model's pylons sit 9 mm further out on the left
  (MK-84 at −1.735 / +1.726 m, MK-83 at −2.986 / +2.977 m), a 22 kg·m moment. Without the trim the demonstration
  touched down 10–33 m left of the centreline with every switch on; with it, within 2 m, as with the switch off.
  An AI jet with one MK-82 left on the right wing (680 kg·m) circles without the trim and lands on the centreline
  with it (test `lands_at_ramat_david_with_unbalanced_stores`).

## 3. Landing training 312 "Eagle Baby"
The player starts at 2000 m, heading 270°, east of Ramat David. The start is airborne, so the autopilot is on in level
mode. The first message (audio 256, `LANDING1.WAV`): "Press the "A" key to engage the autopilot, and I'll demonstrate
a landing circuit." One press gives NAV. The route's only waypoint, "Approach" (351083, 602383, 1500 m, action 7),
makes this **GoHomeCL**:
1. Fly2WayPt over the runway to the waypoint, 5.4 km beyond the lineup.
2. LandingCL's left-hand circuit: crosswind to P1, downwind to P2 (gear and flaps), base to P3, the turns to P4 and P5,
   the 6° final, the roll-out.

**The instructor** (landing.json). A marker fires its reached event when the player comes within its radius, and its
left event (marked "left") when the player then leaves it (3-D, checked every 4 s, docs/mission-runtime.md §2.2).
Each event fires once and plays its audio and subtitle:

| marker (position from the lineup L, km) | radius (m) | event: audio | the instructor says (subtitle, short) |
|---|---|---|---|
| Point 1 (G, −5.4, 0) | 2700 | 6 Cross wing turn: 257 | turn 90° left to the crosswind leg |
| Point 2 - B (P1, −5.4, −5.4) | 2300 | 7 Down wing turn: 385 | the turning point to the downwind leg |
| Point 2 (P1) | 2200, left | 1 Down wind audio: 215 | the downwind checklist; gear and flaps |
| Point 2.5 (−1.8, −5.4) | 2000, left | 8 Down wing distance: 259 | the downwind distance; ask the tower (CTRL-T) |
| Point 3 (P2, 7.2, −5.4) | 2500 | 9 Base leg turn: 260; moves Point 4 - B from (1, 1) onto P3 (Path, 1 s) | remember where the runway is for the base turn |
| Point 4 - B (P3, 7.2, 0) | 2200 | 10 Final leg turn: 261 | watch the ILS localizer move: the turning point to final |
| Point 4 (P3) | 1200, left | 3 Final start audio: 216 | 165 kt, a 4° approach, stay on the centreline |
| Point 6 (L, the touchdown zone sensor) | 200 | 4 Go around: 217; starts "Second point 5mark" | disengage the autopilot, full power, take off, fly it yourself |
| Second point 5mark (after 60 s on P4, 3.6, 0) | 500 | 5 Final land audio: 218; starts the end markers | this time a full landing |
| End of runway, the win sensors (on the runway / hangars, after 30–60 s) | 120–200 | 11 End mission: 219; the Win sensor explodes | good work: the mission is won |

So the demonstration ends at the touchdown marker with the touch-and-go call: the script has no "stop" line. The
autopilot lands and stops anyway (StopPlane), and the mission goes on only when the player takes off, flies the
second final over P4 and lands. Player flown or autopilot flown, the markers are the same. Tests:
`test_autopilot.gd` and `test_autopilot_real.gd` (events 9, 10, 3, 4 in order with their subtitles).

In World scale Real the markers, the route's waypoint G and the airborne start move with Ramat David (zone B,
docs/world-scale.md §3.3): the start stays lined up 9.8 km out on the real heading 266.6°, so NAV flies straight
down the centreline as in Original, and every marker sits on the circuit's corner. The radii keep their size.

**The turn onto final.** The pattern points are f32 in the original (LandingCL Init `5d2b30`, [ai.md](ai.md) §8.3),
so for runway 270 the downwind P1 → P2, the base P2 → P3 and the final P3 → P4 → P5 are exactly horizontal /
vertical lines. ChangeHeading2PtAcu's tangent search then takes its axis-parallel branches and banks the jet on the
circle tangent to the centreline (23° if the base were flown at KA3's 87.5 m/s; the jet arrives at ~110 m/s, so
30–37°, from the KeepAttitude's end 1852 m before P3). CH4 ends on
the centreline and CH5 at once; FinalApproach starts about 5.5 km out at about 400 m above the runway, below the 6°
path. The F-16 crosses the threshold a few metres high, StopPlane's flare (throttle 0, flight-path pitch 0) floats it,
and it touches down on the centreline (about 1 m off) 1–2 km down the runway and stops.

**How the original flies it (checked against the disassembly).** The loops make the circuit fast and steep; the
port reproduces this:
- GoHome's Fly2WayPt gets ETA = now − (−60 s) (`5cd53b` fld the time, `fsub 0x612ff0` = −60.0), so its ETA law asks
  for 275–300 m/s until the slow-down to 180.15 m/s (350 kt) within 6 km of G: the circuit starts at about 350–380 kt.
- LevelWingsPitch0Accel (LW1 250 kt, LW2 200 kt) is done when the jet is *faster* than its speed
  (`5d2400`: `+0xec < V || |V − +0xec| ≤ 3`), so it never slows the jet. Only the KeepAttitude legs' speed law slows
  it, and that law is proportional (`0.7 + 0.03·ΔV`): the downwind settles near 230 kt, the base near 210 kt, the final at
  Vmin + 20 kt ≈ 170 kt (the briefing's 200 / 165 / 165 kt).
- Bank limits: CH1 / CH2 keep the ctor default 80° (`5dce70`: +0xf0 = π·0.4444 from 0x613834), CH3 / CH4 get 60° and
  CH5 20° (LandingCL Init, +0x4c0 / +0x5e8 / +0x710). ChangeHeadK = 3 (bd.ibx) makes the plain law saturate above
  ~10° of heading error, so CH1 (which has no line) always turns at 80°. CH2–CH5 (`5d68b0` sets their line, +0x124) bank to
  the circle tangent to the leg (the "Acu" search, checked instruction by instruction: centre = pos + R·sgn(bank)·right
  via `5ba740` / `5ba600` / `5ba690`, the line `5ada30`, `bank += gap·0.01·(π/180)`); at 350 kt and the 1000 m that
  KA1 stops short of P1 that circle needs 70–80°, and when the search runs past the limit it is switched off for the
  leg (`5dc82f`) and the 80° law finishes the turn. CH3 (base) then needs 55–60°, CH4 (onto final) 30–37°, CH5 ~10°.
- ChangeAlt (CA1 from G's 1500 m down to 700 m AGL, and GoHome's own descent to G) pitches
  `clamp(Δz·6·(π/12)·0.001 − 0.005·vz, −30°, +15°)` (`5cf320`, limits π·−1/6 and π/12 from 0x613138 / 0x613134):
  the 25–30° dives.
- Fly2WayPt's ChangeHeading2Pt banks ±80° (`5ddef0`, 0x613938; C-130 30°): a NAV engaged while flying away turns
  round at 80°.
- CH1 flies without a line: it turns the short way to P1 (right when G is reached flying east), and is done on one tick with
  |e| ≤ 1° (the roll test ≤ 0.2° is signed, so any left bank passes), still banked: the roll-out overshoots a few
  degrees.

Ground tracks of the port (flat ground at the lineup height; km from the lineup L, x east, y north), from the 312
start: G (−5.4, 0) at 375 kt → crosswind 80° left turn to heading 165 → CA dive −30° to 700 m → CH2 80° left at
(−5.6, −4.6) → downwind east at y ≈ −5.6 / −6.6, gear and flaps at x ≈ −1 → CH3 left at ~58° from (5.9, −5.6) → base
north at x = 7.4 → CH4 left at ~36° from (7.4, −1.8) onto the centreline at (5.8, 0) → final 6° at 172 kt → touchdown
at x ≈ −1.8 (1.8 km down the runway), 4 m off the centreline. From 5 / 15 km N, E, S, W, toward and away, 500 and 3000 m
AGL (32 starts) and with Flight data Real + every Physics option (Godot), the same corners within ~1 km, every step
in order, all landings on the centreline. Test: `player_circuit_312_from_engage_points`.

**The cockpit cues.** NAV's HUD steering caret and waypoint marker point at the route's waypoint G ("Approach"), set
by the NAV object (`FUN_00452e60`). After G the caret points back at G while the jet flies the circuit's corners, as
in the original. The ILS (gear handle down, so from the downwind on) is the lineup's 5°
reference (the landing flies 6°, from below it): localizer pegged right (+19°, the centreline is north) on the
downwind and the base, moving from about 2.3 km before the centreline on the base, as the briefing says ("final when
the localizer moves"), centred when CH4 rolls out; the glideslope line above the centre (low: the final starts at
~4°) and crossing to below it at about 4 km. Checked in the Godot run (caret, ILS values logged every 3 s).

The port rounds the points to f32 in world coordinates, although the Godot host shifts the bases by the terrain
origin (`Autopilot::origin`). In f64, P3 and P4 differ by ~4·10⁻⁵ m: the search takes its general branch with a
~10⁻⁸ slope, diverges and switches itself off, and the turn onto final ends ~1 km off the centreline.

## 4. Port
- `crates/iaf-flight/src/autopilot.rs`: `Autopilot::player_mode` (motion 0xf), `player_active`, the `Level` / `Fly`
  loops, `keep_orientation`, the mode-0 rules of Fly2WayPt / LandingCL / StopPlane. `step` returns the posted commands
  (`Out`, with `ap_key`).
- `crates/iaf-godot/src/flight.rs`: `ap_player_mode`, `ap_stage`. `ap_step` returns the commands.
- `game/controls/autopilot.gd`: the mode, the lamp, the A key, stick / rudder break-out, throttle drop and re-sync,
  damage, waypoint sequencing, and the commands mirrored on the levers. `terrain_view.gd` wires it in.
  `hud.gd` draws `AP LVL` / `AP NAV`.
- Tests: `crates/iaf-flight/tests/autopilot.rs` (`player_level_mode_…`, `player_nav_…`, `player_approach_mission_312`,
  `player_circuit_312_from_engage_points`: every step in order, the corners, turn directions and bank limits, the
  gear on the downwind, the touchdown, from six engage points); `tests/godot/test_autopilot.gd` (312: start in level mode, A cycle, stick
  break-out, NAV throttle drop, the circuit with gear and flaps on the levers, touchdown on the centreline,
  StopPlane's A key, the instructor's events) and `test_autopilot_real.gd` (the same in World scale Real).
