# Radio: tower, wingman commands, flight-controller reports

This doc specifies the in-flight radio: how phrases are built from word files, what the tower says, how the wingman
answers your commands, and the flight controller's reports.

Addresses are `IAFJets.exe` **v1.1** (`assets/ghidra_v11/iafjets.c`; argument orders checked in the disassembly).
Related: [controls.md](controls.md) (records 47, 98–103), [ai.md](ai.md) (brain, condition 29, §10),
[autopilot.md](autopilot.md) §2.2 (waypoint sequencing), [sound.md](sound.md) (speech volume, phrase channel),
[mission-runtime.md](mission-runtime.md) §3.3 (subtitle console). Port: `game/audio/radio.gd`.

## How it sounds in the game
- **The tower talks on its own.** It talks when you are on the ground within 18.54 km of one of the four Israeli
  towers (Ramon, Ramat David, Tel Nof, Refidim):
  - at a hangar: "taxi to runway NN";
  - on the way to the runway: "clear to line up" / "hold position";
  - lined up on the runway: "clear to take-off".

  Your pilot answers "Roger". If you stand still for 30 s, the tower repeats.
- **Ctrl+T (Contact tower) is for landing.** In the air near an Israeli tower it answers "proceed to runway NN".
  From then on, as you fly down the runway's approach corridor, it says one of:
  - "cleared to land" (gear down);
  - "your gear is not down";
  - "go around, runway is not clear" (a stopped aircraft on the runway).

  After the roll-out it says "nice to have you back, taxi to hangar". On the ground at an Israeli base Ctrl+T does
  nothing (the tower already talks). Near no tower, or near an Arab base, you hear only a radio click (`kch2.wav`).
- **Wingman commands (Alt+P/B/E/W/T/C).** Your pilot says the command ("Close formation." …). The wingman's brain
  (bdb rules: the AI rule database) reacts: its "Roger, …" reply and manoeuvre come from the mission database. If
  the wingman cannot comply, it answers "I'm afraid that's a negative, sir!" 3 s later. It cannot comply while it is
  still on the ground, or when there is no threat / no locked enemy / nothing to engage.
- **Waypoint reports.** 3 s after a friendly flight (or you) moves on to the next waypoint, the radio says
  "Alpha leader is passing waypoint 2".
- **Flight reports.** For your side's jets the radio says "Bravo leader airborne" (an AI jet's take-off),
  "Alpha wingman landed" (a landing roll stopped), "Alpha wingman crashed" (destroyed with no one to blame) and
  "Alpha leader ejected".
- **Kill calls.** 5 s after a kill: "Alpha leader shot down MiG 29", "Alpha wingman was shot down by SAM",
  "Alpha leader destroyed tank", "Alpha leader shot friendly F-16". The same call within 3 s is not repeated.
- **AWACS.** From 60 s into the flight, every 12 s, the controller calls enemy aircraft within 35 nm (65 km):
  "Alpha, bearing 090, 15 miles, target, heading 270, free to engage". An aircraft your radar has never seen is
  "unidentified contacts, please identify". A contact already called is called again after 60 s, or at once after it
  moved more than 5 nm; the repeat is short ("Bearing 090, 15 miles, target") unless it is at 10, 20 or 30 miles.
  The controller is silent while you are less than 50 m above the ground.
- **Subtitles.** Every radio phrase is spoken from word files and printed in the subtitle console, in English only
  (docs/packs.md).

## 1. Phrases (`phrasetemplates.trx`, `phraseparticalsdata.trx`)
A phrase is a template of tokens; each token names a particle (one wav file plus its text). Both files are in
`resource/soundfiles`:
- template line: `NAME  token token …`;
- particle line: `KEY  WAV  text…`.

**Expand** (`FUN_004c66a0(name, args)`; phrase object: CString text +0, 20 entries (wav, text) +4, count +0xa4):
1. Clear the text and the entries (`4c63f0`).
2. Split the tokens on blanks (`4d56a0`).
3. Resolve each token (`4c64b0`): `%Sn` takes the n-th string argument; `%Dn` takes the n-th int argument, printed
   with `%d`; any other token is a key.
4. Upper-case the key (`5e06d1`) and look it up (`4c6580`). A miss logs "Error: key … was not found in map".

**Text** (`4c6410`): when the phrase is non-empty and the token is other than `,`, append a blank; otherwise
upper-case the part's first letter. Then append the part's text. Example: "%S1 , %S2 , TAXI_TO_RUNWAY %D1" with
ALPHA_T, MORNING, 27 → "Alpha, good morning, taxi to runway 27".

**Play** (`FUN_004c5750`): every entry's `<SoundFilesPath><wav>.wav` (`.wav` at 0x6430cc) goes to the phrase channel
(`FUN_005448b0`) at the speech volume (manager +0x4c). The parts play one after another. Missing files are silent.
The install lacks:
- `Pause.wav` (the `,` / `.` particle), `Null`, `Bear000`, `Head000` and the three `…Twr` files;
- most `NumNNN`. It ships 3, 5, 9, 15, 18, 21, 23, 27, 33, which include the runway numbers of the four Israeli bases.
  (It also has `num36.wav`, which `Num036` does not name.) Only World scale Real's real runway numbers and the runway into the wind need the others
  (deviations.md §2). The port fills them from `game/extra/tower_numbers/` (01-36): `sound_table.gd` reads our clip
  only for a name the install lacks. The clips say the digits like the originals ("zero four") in Piper TTS's
  public-domain voice en_US-john-medium, matched to the originals' format (22050 Hz, 16-bit, mono), radio band
  (300-3000 Hz), loudness and trimmed silence. `tools/tower_numbers.py` regenerates them; the folder's README names
  the voice and its licence.
- any runway letter. Ours: in World scale Real the tower adds the real main runway's letter after its number
  ("runway 25 left"): the particles `RWY_L` / `RWY_R` / `RWY_C` ("left", "right", "center"), our clips
  `rwyl` / `rwyr` / `rwyc.wav` in the same folder, made by the same tool (`radio.gd` `LETTERS`).

**Subtitle**: the callers push the text with `FUN_0044a060` (the console, mission-runtime.md §3.3).

## 2. Tower (TowersManager `DAT_00699344`, ctor `54eb30`)
The TowersManager runs the tower's state machine for the base nearest the player.

**Bases** (iaf.ibx sections, in this order): 0 Ramon, 1 David, 2 TelNof, 3 Refidim, 4 Inshas, 5 Damescuss,
6 Kuzeir, 7 Bley, 8 Ryak, 9 Aman. Bases 0–3 are the Israeli ones. Each base record is 0x51c bytes:

| offset | field                                                     |
|--------|-----------------------------------------------------------|
| +0     | TowerLoc                                                  |
| +0xc   | LineupLoc                                                 |
| +0x18  | TwrCubeLoc                                                |
| +0x24  | to-taxi                                                   |
| +0x114 | from-taxi                                                 |
| +0x204 | hangars (x, y, hdg, turn x, y, hdg; 0x18 each)            |
| +0x4d8 | greeting                                                  |
| +0x4dc | wind (kt)                                                 |
| +0x4e0 | RunwayNumber (int degrees)                                |
| +0x4f0 | hangar count                                              |
| +0x4f4 | hangar taken flags                                        |

**Zones** (`5bea90(r, nx, ny, nz, pose)`): nx·ny·nz spheres of radius r, centres 2r apart about the pose, local y
along the heading. Both zones sit at the LineupLoc, heading = RunwayNumber wrapped to (−180, 180]:
- runway zone +0x331c: r 1500, 1 × 30 × 1 → centres ±43.5 km along the runway (`550850`);
- lineup zone +0x3344: r 100, 1 × 4 × 1 → centres ±300 m along the runway (`550b20`).

The zone query (`4d2580` → `43d020`) lists the registered objects whose bounding sphere meets a cell. Aircraft leave
the list at state 5 (`4a86b0`). The sphere's radius ro is the collision radius, 0.25 · the model's extents. The test
is **|p − c|² < (r + ro)² · 3** (0x6006b8 = 3.0), so each cell reaches (r + ro)·√3. For an F-16 (ro ≈ 18.8 m)
that is ≈ 205 m around the lineup cells and ≈ 2.6 km around the runway corridor's.

Manager fields: +0x3318 current base (−1 none), +0x336c state, +0x3370 timer, +0x3374 timer period, +0x337c runway
clear, +0x3388 last message (0xb = none).

**Wind** (`551320`, set at mission load from misc **0x46a**): 0, 10, 15 or 20 kt is used as is; any other value
becomes a random one of these (`rand() % 4`). All bases share it. The tower says "wind is NN knots" / "no wind".
Misc 0x474 (the direction, inferred) has no reader. Better physics "Wind and turbulence" flies the air mass at this
speed from `radio.gd` `wind_from` (0x474, or 0x46a above 60: a swapped pair; flight-model.md §10). With
that switch the wind is picked with the mission (`Settings.runway_wind`, the same rule), and a base whose main runway
has the wind from behind is flown from that runway's other end: the tower's `rwy` is then that end's number
([autopilot.md](autopilot.md) §2.4).

**Timer** (`550e40(period)`): a repeating event "TowersManagerTimer" every `period` s. Each call restarts it.

**Flight start** (`54f8f0`, called from the flight start next to the FlightController's `54af40`): timer 1 s,
state 0, last 0xb.

**Tick** (`550ed0`; s = player, t = now, `onground` = FM getter 0x1a, `speed` = FM vtbl +0x3c):
```
base = first base (0..9) whose TowerLoc is within 18540 m (2-D) of s           // 54fbf0
if none: base = −1, timer(4), state = 2
state 1:  if speed > 1: idle_t = t;  if t ≥ idle_t + 30: last = 0xb, idle_t = t;  ground()
state 2:  idle_t = t;  if onground: state = 1                                    // 54fca0
state 3:  idle_t = t;  approach()                                                // 54fd00
else:     idle_t = t;  state = onground ? 1 : 2                                  // 54f980
```
(`idle_t` is a function static at 0x83ff88, 0 at start.)

**ground()** (`54fef0`):
1. Off the ground → state 2 (period field 4; the timer keeps running unrestarted).
2. On the ground: h = the nearest hangar of the base within 1000 m (`5521c0`; −1 = none). With −1 the original reads
   the entry before the table, which is uninitialised memory; we take it as "no hangar".
3. If the player's landed flag (brain +0xe0, set at a landing; v1.1 clears it at lift-off) is 0:
```
if dist2(s, hangar[h]) < 100:  timer(1) unless already 1;  if last ∉ {0, 9}: say 0;  state = 1;  return
busy = last ∈ {10, 6, 8}
if not lineup(base) or busy:                       // 5504e0
   d = dist2(s, LineupLoc)
   if 200 < d < 400 and not busy:
      if runway_clear: if last ∉ {1, 4}: say 1;  return
      if last ∉ {3, 4}: say 3
elif last != 4: say 4
```
**lineup(b)** (`5504e0`):
1. Set runway_clear = 1.
2. For every object in the lineup zone: the player sets in = 1; an aircraft (class 0x1c) slower than 1 m/s, other
   than the player's formation leader / wingman, sets runway_clear = 0.
3. Return `in` only if |ftol(runway heading − player heading)| ≤ 45 (both in degrees, (−180, 180]; the difference
   is left unwrapped).

**runway(b)** (`550240`): the same with the runway zone, but it computes runway_clear only when aligned.

**approach()** (`54fd00`): r = runway(base).
```
if onground and speed < 20 and last == 6:  say 9;  state = 1;  return
if not r:  if last == 6 and not onground: state = 2;  return
code = runway_clear ? (gear down (getter 0x19) ? 6 : 10) : 8
if code == 6: if last != 6: say 6;  return
if last != code: say code
last = code
```
**Ctrl+T** (command 107 → `54fb40`, only with a TowersManager):
```
if 0 ≤ base ≤ 3 and state == 2:  timer(1);  say 5;  state = 3;  last = 5
elif base == −1 or base > 3:     say 0xb (click);  timer(4);  state = 2;  last = 0xb
(an Israeli base on the ground, or state 3: nothing)
```
**say(code)** (`551c20`, on the base) fills three arguments:
- callsign = the player's formation name (`5513c0`: kinds 2–6, 9, 10 by name, else "Alpha") + `_t`;
- rwy = RunwayNumber / 10;
- wind = `WI_KNOTS%02d` or none.

| code | template | args |
|---|---|---|
| 0 | ACFT_TAXI_TO_RUNWAY | callsign, greeting (MORNING; hour 12–16 AFTERNOON; 17–21 EVENING; time of day = misc 0x460 + sim time), rwy |
| 1 | ACFT_CLEAR_TO_LINEUP / …_NW | callsign, rwy, wind |
| 3 | ACFT_HOLD_POS | callsign |
| 4 | ACFT_CLEAR_TO_TAKEOFF | callsign |
| 5 | ACFT_PROCEED_TO_RUNWAY | callsign, rwy |
| 6 | ACFT_CLEAR_TO_LAND / …_NW | callsign, rwy, wind |
| 8 | ACFT_GO_AROUND_RUNWAY | callsign |
| 9 | ACFT_TAXI_TO_PARK | callsign |
| 10 | ACFT_GEARS_NOT_OPEN | callsign |
| 0xb | `KCH2.WAV` on the phrase channel, no text, no reply | — |
| 2, 7, other | nothing | — |

Codes 0–10: the phrase is printed (`FUN_0044a060`) and played. Then **ACFT_ROGER** ("Roger", the pilot) plays after
it, unprinted. The tower names (TI_RAMON_TWR …) and ACFT_PROCEED_TO_RUNWAY's "this is … tower" variant are
commented out / unused.

No mission trigger or condition reads the tower or the radio state (mission-runtime.md §4).

## 3. Wingman commands (records 98–103 → command 108, p1 = command → `FUN_0043f8d0(p1)` on the player's brain)
| p1 | key | particle (text) | condition 29 value |
|---|---|---|---|
| 1 | Alt+P Protect me | WINGMAN_PROTECTME "get this guy off me." | ProtectMe |
| 2 | Alt+B Go home | WINGMAN_BUGOUT "bug out." | BugOut |
| 3 | Alt+E Engage my target | WINGMAN_ENGAGEDESIGNATETARGET "engage my target." | EngageDesignated |
| 4 | Alt+W Engage other target | WINGMAN_ENGAGEANYTARGETIMNOT "engage." | EngageAny |
| 5 | Alt+T Tactical formation | WINGMAN_TACTICALFORMATION "tactical formation." | Tactical |
| 6 | Alt+C Close formation | WINGMAN_CLOSEFORMATION "close formation." | Close |

```
W = brain+0x44 (else getWingman(player), else the formation leader); none → return
W destroyed (status 4 / 5) or W's control mode (status+0x14) 0 → return
spoke = brain+0xb8 timer fires (period 1.5 s, not random: at most one call per 1.5 s)
if spoke: say WINGMAN_COMMAND (%S1 = the command particle), printed and played          // 441080
if W on the ground (getter 0x1a) and spoke: NEGATIVE at +3 s; return
1: t = the RWR's nearest emitter (451f70, ≤ 370.8 km); t and |t − player| ≤ 18540 and t an aircraft
   (class 2, 3, 0x1c) → apply(t); else NEGATIVE
3: T = the radar target (44e430, radar locked); T hostile (not the player's side) → apply(T); else NEGATIVE
4: t = engage_any() (440860); t → apply(t); else NEGATIVE
2, 5, 6: apply(none)
apply(t) (43fee0 on W's brain): cmd ∈ {1, 3, 4} and t: W.brain+0x70 = t (target selector told);
   W.brain+0x48 = cmd
NEGATIVE (only if spoke): an event at now + 3 s → WINGMAN_REPLY_NEGATIVE %S1 = NEGATIVE
   ("I'm afraid that's a negative, sir!"), printed and played                            // 441310
```
Kept quirk: if the wingman is on the ground but the 1.5 s timer did not fire, the command is applied.
The network branch (a remote wingman: message 0x21) is not ported.

**engage_any** (`440860`):
1. If the radar holds a target T and T is an aircraft: return its formation partner (`5bcb90`, else the formation
   leader), if alive.
2. Else, with a target T: search around T for T's class.
3. Without a target: search around the player, any class.

The search returns the nearest unit that is:
- within 9270 m;
- other than the player and W;
- alive;
- of class ∈ {0x1c, 2, 3, 1, 10, 9, 8, 0xb, 0xd, 0x1d, 0x1e, 5, 6, 0xf, 0x10} (around T: the same class as T,
  other than T itself);
- hostile.

Only a hostile result is returned.

**Original quirks kept:**
- "Engage other target" takes the nearest unit of *another side* (`4a4cf0`). Near your own base it can pick a side-0
  object (mission 221: the Ramon tower).
- A sub-brain that answers a new command by going back to the base list (`setRules(0, 1)`, `440790`) keeps +0x48.
  The base list then answers the command (e.g. bug out while in close formation).

**What the wingman does** is in its bdb brain. Condition 29 (own brain +0x48) rules switch to a sub-brain (action
1000, which clears +0x48) and fire a type-7 response with the reply audio. Example, the "AA wing command" brains
49–52 / 60:

| command | sub-brain | reply (audio)                       |
|---------|-----------|-------------------------------------|
| 6       | 40        | "Roger, closing formation." (250)   |
| 5       | 44        | "Roger, going tactical." (251)      |
| 2       | 41        | "Roger, bugging out." (252)         |
| 1       | 39        | "Roger, I'm on my way." (255)       |
| 3       | 46 / 39   | "Roger, engaging target." (253)     |
| 4       | 46 / 39   | "Roger, engaging." (254)            |

The manoeuvres are the brain actions (190 close formation, 200 tactical, 250 go home …, ai.md §5).

## 4. FlightController reports (`DAT_00699348`, ctor `54acc0`)
The FlightController posts one-shot radio reports. Each says `%S1 …`, with S1 = the unit's callsign (`54ccb0`):
- formation name + "Leader" (member 0) or "Wingman", upper-cased;
- empty for "Other", so that unit gets no report;
- "<name> - No formation" for a unit without a formation (literal text, not a particle key).

A report is printed and played only when all hold:
- the game is outside a network game;
- the unit is on the **player's side** (`4a4cf0`; without a player, sides 2 / 3 are skipped);
- the unit has a callsign.

| event | posted by | delay | template |
|---|---|---|---|
| WayptReport (`453740` → `54dc00(unit, wp)`) | the player's waypoint sequencing (`452960`, after `4532a0`: wp = the new current waypoint) and an AI WayPtSet moving on (`5d7450`, wp = the new index ≠ brain+0x88) | 3 s (0x600e00) | PASS_WAYPT_PHRASE, S2 = `G%d` (G1…G25); wp 0: none |
| AirborneReport (`54e310`) | TakeoffCL above 100 m AGL (`5cdb5d`, 0x613018; delay 0x613030) | 3 s | AIRBORNE_PHRASE |
| LandedReport (`54de90`) | StopPlaneCL's stop (`5d44d0`, delay 0x613410), also the player's autopilot landing | 3 s | LANDED_PHRASE |
| CrashedReport (`54e0e0`) | `4a9e70` → `4aa2b0`: a class-0x1c unit now in state 4 / 5 with no killer key | 2.5 s (0x603120) | CRASHED_PHRASE |
| EjectReport (`54e560`) | ejection `5485a0` | 4.5 s | EJECTED_PHRASE |
| kill calls (`54c2a0(victim, killer)`) | `4a9e70` → `4aa160`: a unit now in state 4 / 5 with a killer key | 5 s (0x603118) | see below |

`4a9e70` runs at the end of every damage-level change (docs/damage.md §3.1 step 5).

**Airborne / landed filters:** the report is said unless its callsign was the last airborne (+0x38c) or the last
landed (+0x388) callsign; then that field takes it. Neither checks for a network game.

**Kill calls** (`54c2a0`). The terms:
- *air*: class 1, 2, 3 or 0x1c;
- *enemy*: on another side than the player (`4a4cf0`);
- *differ*: victim and killer are on different sides.

Before the cases, the gate at +0x318 (`4d4100`, `4d3fa0(0, 3.0, 0)`) is tested: it *fires* when now is outside
[last, next], then [last, next] = [now, now + 3].

| case | template | S1 | S2 |
|---|---|---|---|
| differ, both air, victim enemy, killer class 0x1c | SHOT_ENEMY | killer's callsign | victim's air name |
| differ, both air, victim not enemy and class 0x1c | SHOT_BY_ENEMY | victim's callsign | killer's air name |
| differ, killer air and not enemy, class 0x1c, victim not air | SHOT_GROUND_TARGET | killer's callsign | victim's ground name |
| differ, killer not air and enemy, victim class 0x1c | SHOT_BY_GROUND_TARGET | victim's callsign | killer's ground name |
| same side, killer not enemy, class 0x1c | SHOT_FRIENDLY_PHRASE | killer's callsign | victim's air / ground name |
| other | nothing (an enemy's own-side kill only builds ":Enemy shot its own side target") | | |

Then:
1. SHOT_GROUND_TARGET only (+0x390 counter): when the gate fired, the counter is 1. Otherwise, with the same S1 as
   the last call and another S2, S2 becomes MULTITARGET ("ground targets") at counter 2 and empty above; the counter
   goes up.
2. S1 empty → nothing.
3. Without the gate firing, a call equal to the last one (S1, S2, S3, template at +0x378..+0x384) is dropped.
4. Printed, played, and stored as the last call.

**Air names** (`54ce80`; *name* = the unit's name, unit +0x20; the tests are case-blind on its first 3 / 4 / 5
characters):
- classes 1, 2: MI24 / MI-24, MI8 / MI-8, UH60 / UH-60, CH53 / CH-53, else AIRTARGET;
- by type code: 100 F16, 110 F15, 120 F4, 130 KFIR, 140 LAVI, 150 MIG21, 160 SU22 (by name) or MIG23, 170 MIG25,
  180 MIG29, 190 MIRAGE, 200 PHANTOM2000, 210 MIG17, 220 SU24 / SU22 / TU22 by name or AIRTARGET, 225 C130 / B707 /
  IL76 by name or LARGEAIRCRAFT, other C130 / B707 / IL76 by name or AIRTARGET.

**Ground names** (`54d8d0`): class 9 IRSAM; by type code 250 TANK, 260 TRUCK, 270 SCUD (by name) or
ARMOREDVEHICLE, 280 SOFTVEHICLE, 290–340 SAM, 350 AAA, 360 GUNDISH, 370 SHIP, 380 PATROLSHIP, 390 MISSILESHIP,
400 BUILDING, 410 NUCLEARREACTOR, 420 BRIDGE, 450 RUNWAY, else GROUNDTARGET.

**AWACS contact calls** (AWACS: the airborne early-warning controller):
1. **Timer** (`54af40` at the flight start): FlightControllerTimer every 12 s in single player. The counter +0x310
   = 50 / 12 = 4 skips the first four ticks (`54b130`), so the first scan is 60 s into the flight.
2. **Player gate**: alive, controlled, and |z − terrain| ≥ 50 m (0x60ca90).
3. **Query** (`4d2620`): sphere r = 55 620 m (`54ba10`) around the player; a unit is in when
   |p − c|² < (r + ro)² · 3 (0x604e6c), a reach of about 96 km.
4. **Units**: classes 0x1c, 2, 3; other than the player and the wingman (`5c8cd0`); alive and controlled; higher
   than terrain + 175 m (0x60ca80).
5. **Values** from the player: distance (3-D); bearing (`54bc40`); heading (the unit's yaw in degrees, +360 below
   0). The bearing is acos of the direction's north component, 6.28 − that west of north, times 57.3248
   (180 / 3.14): due west is 269.95.
6. **Code**: a same-side unit (`4a4cd0`) is taken only within 10 m (0x60caa0), as code 0. Others are code 1;
   `rand() % 9 == 6` makes it 2 (`54bc20`); not known to the player (status +0x44) makes it 3.
7. **Table** (`54b790`, 24 slots of key, distance, delta, life, seen, callsign). Each scan first clears the seen flags
   (`54b980`) and at the end empties the unseen slots (`54b9a0`). For one unit:
   - another slot holds the same callsign (`5513c0`, case-blind) → nothing, the unit is not marked seen;
   - its own slot: seen; miles none → nothing; *long* = on the FlyTSD (+0x314, `4e3dc0`) or miles ∈ {10, 20, 30};
     the change test (`54ac20`): life −= 12, and it passes when life ≤ 0 or the delta moved more than 5 nm
     (integer metres / 1854 > 5); then delta and life 60 are stored and the call is long or short;
   - a new slot: stored with life 60; called long if miles exist.
   - *miles* (`54bb60`): metres × 0.000539374, truncated; above 35 none; above 10 down to a multiple of 5; below 1
     none. Bearing and heading (`54bbf0`): truncated to tens; 0 becomes 360.
8. **Call** (`54be80`): ACFT_FCTRL_LONG = player's callsign + `_r`, BEARING%03d, MILES%02d, description,
   HEADING%03d, instruction; ACFT_FCTRL_SHORT = bearing, miles, description. Printed and played.

| code | description | instruction |
|---|---|---|
| 0 | DESC_FRIENDS "friendlies" | NULL (no text, no file) |
| 1 | DESC_TARGET "target" | FREE_TO_ENGAGE |
| 2 | DESC_TARGET | TRGT_ALRDY_ENGAGE "targets are already engaged" |
| 3 | DESC_UNID_CONTACT "unidentified contacts" | PLEASE_IDENTIFY |

The callsign is `5513c0` (§2), so every enemy formation (kind 7) is "Alpha" and only one of them is in the table at
a time (kept quirk).

## 5. Port (`game/audio/radio.gd`)
- `Radio.expand()` / `say()`: the phrase engine from the two .trx files; the parts queue on the phrase channel
  (`flight_sounds.gd` channel 101, speech bus); the text goes to the subtitle console (`terrain_view._on_subtitle`).
- Tower: §2 literally (bases from iaf.ibx, the two zones as sphere chains, the timer on the flight's sim time).
- Wingman commands: §3 on the AI wingman's brain (`brain.gd` `wingman_command` / `target`); NEGATIVE after 3 s.
- Waypoint reports: the player's (`controls/autopilot.gd` sequencing) and the AI's (`ai_flights.gd`, the autopilot's
  waypoint index moving on) at +3 s; the ejection's "<callsign> ejected" uses EJECTED_PHRASE.
- The FlightController's tables and filters are `iaf_avionics::fctrl` (`IafFlightController`): the AWACS table, the
  kill calls, the airborne / landed filters. `radio.gd` gathers the units and speaks.
- Airborne / landed: the AI autopilot's TakeoffCL / StopPlaneCL flags (`ap_airborne`, `ap_landed`) in
  `ai_flights.gd`; the player's autopilot landing in `controls/autopilot.gd`. Crashed / kill: posted by
  `mission_runtime.gd` `_set_damage` (`4a9e70`).

## UNCERTAIN
- The phrase channel queues, because the parts of one phrase must follow each other. Whether a new phrase waits for
  or cuts a running one is not traced; here it queues. Mission voices (`_voice`) still replace each other.
- The hangar entry −1 (uninitialised memory) read as "no hangar".
- The tower's object lists: the port tests the player and the mission's class-0x1c units (AI jets at their flight
  model positions and speeds, others standing) against the zones; static wrecks (state 4) still count.
- The zone frame's local y along the runway heading (the chains are symmetric, so only the axis matters).
- A missing particle key: the entry keeps its previous wav / text (stale); here the part is skipped.
- The AWACS bearing's east / west test in `54bc40` (the frame is the identity; the sign test is read as east of
  north = the acos).
- The FlyTSD flag +0x314: the port's FlyTSD freezes the sim and this timer, so it is never seen; passed as false.
- The AWACS query leaves the units' collision radius out of its 96 km reach (at most 20 m).
- A jet shot to state 3 explodes later on the ground with no killer key in the port, so it gets "… crashed", not a
  kill call. Which key the original's ground contact passes is not traced.
