# The player's autopilot

The A key ("Autopilot level/navigation/off", key record 18, GEV 0x10) cycles the autopilot off → **level** → **NAV** →
off. The autopilot flies the jet through the same control loops as the AI ("control loops", `atp.ControlLoop.h`,
[ai.md](ai.md) §8). The control law is shared: `crates/iaf-flight/src/autopilot.rs` runs both. The player's loops
run with the FM mode left at 0, so the jet keeps the player's flight-model rules (stall, crash checks, afterburner).
Addresses are v1.1.

## 1. Mode and lamp (player controller `FUN_0044a240`)

`ctl+0x974` holds the mode: 0 off, 1 level, 2 NAV. Lamp 8 (`LIGHT008`, [cockpit.md](cockpit.md) panel lights) is on
while the mode is not 0. Every change posts FM motion 0xf `(mode, waypoint index)`, where the waypoint index is the
NAV object's current waypoint (`FUN_00594c10`, +0x44).

| event | rule |
|---|---|
| flight start (@4483d7) | **airborne start → mode 1** (lamp on); ground start → 0 |
| GEV 0x10 (A key, lamp click, the landing's StopPlane) (@44d13a) | refused while system 6 (autopilot) is damaged (`FUN_00450d40(6)`). On the ground the mode is first forced to 2, so the press always goes to off. 0 → 1 (lamp on); 1 → 2; 2 → 0 (lamp off, throttle re-sync) |
| GEV 1 stick (@44bd0e) | lamp on and the event's x and y both within ±51 (of ±100): the stick is **not posted** (the autopilot keeps it). Otherwise the lamp goes off, mode 0, motion 0xf (0), throttle re-sync unless the old mode was 1, then the stick is posted |
| GEV 10 rudder (case 0xa) | always posted; lamp on and \|x\| ≥ 51: lamp off, mode 0, motion 0xf (0) (no re-sync) |
| GEV 4 / 9 throttle, 5 / 6 RPM ± 5 % | dropped while the mode is 2 (NAV holds the throttle) |
| damage 6 (`FUN_0044d760` case 6) | lamp on: lamp off and motion 0xf (0). `ctl+0x974` keeps its value (as coded), but the A key is refused from now on anyway |
| ejection (`FUN_005485a0`) | motion 0xf (0) |

The keyboard sends ±100, so any roll or pitch key press disengages the autopilot. A key release sends 0 and is
dropped. The keys build one GEV 1 from both axes (`FUN_004e0b80`: the other axis's last value), so the ±51 test
sees both.

**Throttle re-sync** (`FUN_005a29d0`, when leaving NAV): motion 2 with the throttle axis × 0.01. Without a throttle
axis (`FUN_004e0f40` returns −1: THROTTLE keyboard on the Devices page, or no joystick) the value is 0.74
(military), and it is posted only when airborne. With one, the throttle goes back to the lever (the axis's last
value, docs/controls.md §5); the port does the same (`Joystick.throttle_axis()`). UNCERTAIN: the
controller gates this on a vehicle getter (vtbl+0x6c) == 0x1e that was not traced. The port re-syncs on every exit
from NAV.

**HUD** (`FUN_0052efd3`): the G readout line shows `AP LVL` (mode 1) or `AP NAV` (mode 2) in its place
(strings 0x65d50c / 0x65d514). There is no sound: the hook `FUN_0058a330` is empty. The damage MFD page has the
A/P row (system 6).

## 2. FM motion 0xf (`FUN_005a1e40`)

| arg | call | loop (control-loop manager offset) |
|---|---|---|
| 0 | `5c8800` | cancel the root loop (the stick stays where it was) |
| 1 | `5c82c0` | **LevelFlightCL** (+0x4528, vtable 0x612c30, Init `5cd8c0`) |
| 2, waypoint action 7 (land) | `5c7d80` | **GoHomeCL** (+0x1ed0): the AI's go-home and landing, [ai.md](ai.md) §8.3. Also sets `DAT_00843dec` = 1 (reader not found) |
| 2, other waypoint | `5c7bc0` | **Fly2WayPt** (+0x4f8) to the waypoint with its ETA (record +0x10). Without a route, the loop starts uninitialised (UNCERTAIN; the port flies nothing) |

The loop's first tick comes 0.5 s later (`5c9a90`).

### 2.1 Level (LevelFlightCL)
1. **LevelWingsPitch0** (`5d2140`, vtable 0x613340) with the pitch tolerance set to **0.0035 rad** (+0x1d0): wings
   level and flight-path pitch 0. Done when \|pitch\| ≤ 0.0035 rad and \|roll\| ≤ 1° (`0x8455d0` = π/180).
2. **KeepOrientation** (`5d9d30`, vtable 0x612d60). FirstRun `5da010` stores the flight-path pitch, the heading and the
   speed at that moment. Each tick:
   - roll target = clamp(wrap(stored heading − heading), ±30°) (`0x84562c` = `0x845634` = π/6);
   - pitch law to the stored pitch;
   - throttle: the speed law to the stored speed only in an AI mode (`5c89f0` ≠ 0). The player gets **no
     autothrottle**: the throttle is posted only when the ground watch takes over (UNCERTAIN: its slot is not
     initialised for the player; the port starts it at 0, so the watch's 250 m/s law applies).
   - It never ends.

So level mode holds the heading and a level flight path (about the altitude at levelling), at the player's
throttle.

### 2.2 NAV
**Fly2WayPt** ([ai.md](ai.md) §8.4) flies to the current waypoint with the ETA speed law, so NAV holds the throttle.
In FM mode 0 its FirstRun (`5d6fb0`) keeps the 1852 m PassWaypoint radius: the larger start-inside radii apply in AI
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
(docs/radio.md §4); not built: the `440e90(index)` call of `4532a0` (its target object was not traced).

### 2.3 Landing (GoHomeCL in FM mode 0)
- Gear and flaps go down at landing step 7, as for the AI. The commands reach the levers through the controller.
  The port mirrors them on the cockpit levers, so the gear's 300 kt rule and the flaps damage still apply.
- The pitch law's "gear / flaps / brakes in above 150 m/s" clean-up is skipped in modes 0 and 8.
- No ground watch in the ChangeHeading2PtAcu legs (modes 0 and 8).
- LandingCL Init (`5d36d2`): the stop condition is **1.0295 m/s** in FM mode 0 (25.736 m/s in mode 8). The children
  end with StopPlane: TaxiCL and ParkInHangar are added only in mode 8 (`5d43e0`).
- StopPlane done (`5d4b22`): mode 0 has no landed handler. Instead it posts **GEV 0x10 forced** (the A key), which
  turns the autopilot off from NAV.

## 3. Landing training 312 "Eagle Baby"
The player starts at 2000 m, heading 270°, east of Ramat David. The start is airborne, so the autopilot is on in level
mode. The first message (audio 256, `LANDING1.WAV`): "Press the "A" key to engage the autopilot, and I'll demonstrate
a landing circuit." One press gives NAV. The route's only waypoint, "Approach" (351083, 602383, 1500 m, action 7),
makes this **GoHomeCL**:
1. Fly2WayPt over the runway to the waypoint, 5.4 km beyond the lineup.
2. LandingCL's left-hand circuit: crosswind to P1, downwind to P2 (gear and flaps), base to P3, the turns to P4 and P5,
   the 6° final, the roll-out.

The mission's markers sit on these corners: "Point 2" (start of downwind), "Point 3" (green point), "Point 4"
(base), "Point 5" (P4) and "Point 6" (the lineup). Their radius slots fire the instructor's lines.

**The turn onto final.** The pattern points are f32 in the original (LandingCL Init `5d2b30`, [ai.md](ai.md) §8.3),
so for runway 270 the downwind P1 → P2, the base P2 → P3 and the final P3 → P4 → P5 are exactly horizontal /
vertical lines. ChangeHeading2PtAcu's tangent search then takes its axis-parallel branches and banks the jet on the
circle tangent to the centreline (23° if the base were flown at KA3's 87.5 m/s; the jet arrives at ~110 m/s, so
30–37°, from the KeepAttitude's end 1852 m before P3). CH4 ends on
the centreline and CH5 at once; FinalApproach starts about 5.5 km out at about 400 m above the runway, below the 6°
path. The F-16 crosses the threshold a few metres high, StopPlane's flare (throttle 0, flight-path pitch 0) floats it,
and it touches down on the centreline (about 1 m off) 1–2 km down the runway and stops.

**How the original flies it (checked against the disassembly, step by step).** The circuit is fast and steep by
design of the loops, not by a port error:
- GoHome's Fly2WayPt gets ETA = now − (−60 s) (`5cd53b` fld the time, `fsub 0x612ff0` = −60.0), so its ETA law asks
  for 275–300 m/s until the slow-down to 180.15 m/s (350 kt) within 6 km of G: the circuit starts at about 350–380 kt.
- LevelWingsPitch0Accel (LW1 250 kt, LW2 200 kt) is done when the jet is *faster* than its speed
  (`5d2400`: `+0xec < V || |V − +0xec| ≤ 3`), so it never slows the jet; only the KeepAttitude legs' speed law does,
  and that law is proportional (`0.7 + 0.03·ΔV`): the downwind settles near 230 kt, the base near 210 kt, the final at
  Vmin + 20 kt ≈ 170 kt (the briefing's 200 / 165 / 165 kt).
- Bank limits: CH1 / CH2 keep the ctor default 80° (`5dce70`: +0xf0 = π·0.4444 from 0x613834), CH3 / CH4 get 60° and
  CH5 20° (LandingCL Init, +0x4c0 / +0x5e8 / +0x710). ChangeHeadK = 3 (bd.ibx) makes the plain law saturate above
  ~10° of heading error, so CH1 (no line) always turns at 80°. CH2–CH5 (`5d68b0` sets their line, +0x124) bank to
  the circle tangent to the leg (the "Acu" search, checked instruction by instruction: centre = pos + R·sgn(bank)·right
  via `5ba740` / `5ba600` / `5ba690`, the line `5ada30`, `bank += gap·0.01·(π/180)`); at 350 kt and the 1000 m that
  KA1 stops short of P1 that circle needs 70–80°, and when the search runs past the limit it is switched off for the
  leg (`5dc82f`) and the 80° law finishes the turn. CH3 (base) then needs 55–60°, CH4 (onto final) 30–37°, CH5 ~10°.
- ChangeAlt (CA1 from G's 1500 m down to 700 m AGL, and GoHome's own descent to G) pitches
  `clamp(Δz·6·(π/12)·0.001 − 0.005·vz, −30°, +15°)` (`5cf320`, limits π·−1/6 and π/12 from 0x613138 / 0x613134):
  the 25–30° dives.
- Fly2WayPt's ChangeHeading2Pt banks ±80° (`5ddef0`, 0x613938; C-130 30°): a NAV engaged while flying away turns
  round at 80°.
- CH1 has no line: it turns the short way to P1 (right when G is reached flying east), and is done on one tick with
  |e| ≤ 1° (the roll test ≤ 0.2° is signed, so any left bank passes), still banked: the roll-out overshoots a few
  degrees.

Ground tracks of the port (flat ground at the lineup height; km from the lineup L, x east, y north), from the 312
start: G (−5.4, 0) at 375 kt → crosswind 80° left turn to heading 165 → CA dive −30° to 700 m → CH2 80° left at
(−5.6, −4.6) → downwind east at y ≈ −5.6 / −6.6, gear and flaps at x ≈ −1 → CH3 left at ~58° from (5.9, −5.6) → base
north at x = 7.4 → CH4 left at ~36° from (7.4, −1.8) onto the centreline at (5.8, 0) → final 6° at 172 kt → touchdown
at x ≈ −1.8 (1.8 km down the runway), 4 m off the centreline. From 5 / 15 km N, E, S, W, toward and away, 500 and 3000 m
AGL (32 starts) and with Flight data Real + every Physics option (Godot), the same corners within ~1 km, every step
in order, all landings on the centreline. Test: `player_circuit_312_from_engage_points`.

**The cockpit cues.** NAV's HUD steering caret and waypoint marker point at the route's waypoint G ("Approach"),
not at the circuit's corners (the NAV object, `FUN_00452e60`): after G the caret points back at it while the jet
flies the circuit, as in the original. The ILS (gear handle down, so from the downwind on) is the lineup's 5°
reference (the landing flies 6°, from below it): localizer pegged right (+19°, the centreline is north) on the
downwind and the base, moving from about 2.3 km before the centreline on the base, as the briefing says ("final when
the localizer moves"), centred when CH4 rolls out; the glideslope line above the centre (low: the final starts at
~4°) and crossing to below it at about 4 km. Checked in the Godot run (caret, ILS values logged every 3 s).

(The port rounds in world coordinates even though the Godot host shifts the bases by the terrain origin:
`Autopilot::origin`. An earlier port built the points in f64: P3 and P4 then differed by ~4·10⁻⁵ m, the search took its general branch
with a ~10⁻⁸ slope, diverged and switched itself off. The turn onto final ended ~1 km off the centreline and the
final approach began 600 m short at 400 m: the dive into the ground.)

## 4. Port
- `crates/iaf-flight/src/autopilot.rs`: `Autopilot::player_mode` (motion 0xf), `player_active`, the `Level` / `Fly`
  loops, `keep_orientation`, the mode-0 rules of Fly2WayPt / LandingCL / StopPlane. `step` returns the posted commands
  (`Out`, with `ap_key`).
- `crates/iaf-godot/src/flight.rs`: `ap_player_mode`, `ap_stage`. `ap_step` returns the commands.
- `game/controls/autopilot.gd`: the mode, the lamp, the A key, stick / rudder break-out, throttle drop and re-sync,
  damage, waypoint sequencing, and the commands mirrored on the levers. `terrain_view.gd` wires it in.
  `hud.gd` draws `AP LVL` / `AP NAV`.
- Tests: `crates/iaf-flight/tests/autopilot.rs` (`player_level_mode_…`, `player_nav_…`, `player_approach_mission_312`)
  `player_circuit_312_from_engage_points` (every step in order, the corners, turn directions and bank limits, the
  gear on the downwind, the touchdown, from six engage points)
  and `tests/godot/test_autopilot.gd` (312: start in level mode, A cycle, stick break-out, NAV throttle drop, the
  circuit with gear and flaps on the levers, touchdown on the runway centreline, StopPlane's A key).
