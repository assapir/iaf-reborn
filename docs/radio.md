# Radio: tower, wingman commands, flight-controller reports

Addresses are `IAFJets.exe` **v1.1** (`assets/ghidra_v11/iafjets.c`; argument orders checked in the disassembly).
Related: [controls.md](controls.md) (records 47, 98–103), [ai.md](ai.md) (brain, condition 29, §10),
[autopilot.md](autopilot.md) §2.2 (waypoint sequencing), [sound.md](sound.md) (speech volume, phrase channel),
[mission-runtime.md](mission-runtime.md) §3.3 (subtitle console). Port: `game/audio/radio.gd`.

## How it sounds in the game (plain language)
- **The tower talks on its own.** Within 18.54 km of one of the four Israeli towers (Ramon, Ramat David, Tel Nof,
  Refidim) and on the ground, the tower says "taxi to runway NN" while you stand at a hangar, "clear to line up" /
  "hold position" on the way to the runway, "clear to take-off" when you are lined up on the runway; your pilot
  answers "Roger". Standing still for 30 s makes it repeat.
- **Ctrl+T (Contact tower) is for landing.** In the air near an Israeli tower it answers "proceed to runway NN".
  From then on, flying down the runway's approach corridor, it says "cleared to land" (gear down), "your gear is
  not down", or "go around, runway is not clear" (a stopped aircraft on the runway), and after the roll-out "nice to
  have you back, taxi to hangar". On the ground at an Israeli base Ctrl+T does nothing (the tower already talks);
  near no tower or near an Arab base you only hear a radio click (`kch2.wav`).
- **Wingman commands (Alt+P/B/E/W/T/C).** Your pilot says the command ("Close formation." …) and the wingman's
  brain (bdb rules) reacts: its "Roger, …" reply and manoeuvre come from the mission database. If the wingman
  cannot comply (still on the ground, no threat / no locked enemy / nothing to engage) it answers "I'm afraid
  that's a negative, sir!" 3 s later.
- **Waypoint reports.** 3 s after a friendly flight (or you) moves on to the next waypoint the radio says
  "Alpha leader is passing waypoint 2".
- Every radio phrase is spoken from word files and printed in the subtitle console (the English text of the data:
  there is no Hebrew radio text, docs/packs.md).

## 1. Phrases (`phrasetemplates.trx`, `phraseparticalsdata.trx`)
Both in `resource/soundfiles`. A template line is `NAME  token token …`; a particle line is `KEY  WAV  text…`.
- Expand (`FUN_004c66a0(name, args)`, phrase object: CString text +0, 20 entries (wav, text) +4, count +0xa4):
  the text and the entries are cleared (`4c63f0`); tokens are split on blanks (`4d56a0`). A token `%Sn` takes the
  n-th string argument, `%Dn` the n-th int argument printed with `%d` (`4c64b0`); any other token is a key. The key is
  upper-cased (`5e06d1`) and looked up (`4c6580`; a miss logs "Error: key … was not found in map").
- Text (`4c6410`): unless the phrase is empty or the token is `,`, a blank is appended; otherwise the part's first
  letter is upper-cased. Then the part's text is appended. "%S1 , %S2 , TAXI_TO_RUNWAY %D1" with ALPHA_T, MORNING, 27
  → "Alpha, good morning, taxi to runway 27".
- Play (`FUN_004c5750`): every entry's `<SoundFilesPath><wav>.wav` (`.wav` at 0x6430cc) goes to the phrase channel
  (`FUN_005448b0`) at the speech volume (manager +0x4c); the parts play one after another. Missing files are silent:
  the install lacks `Pause.wav` (the `,` / `.` particle), `Null`, `Bear000`, `Head000`, the three `…Twr` files and
  most `NumNNN` (it ships 3, 5, 9, 15, 18, 21, 23, 27, 33: the runway numbers of the four Israeli bases are there).
- Subtitle: the callers push the text with `FUN_0044a060` (the console, mission-runtime.md §3.3).

## 2. Tower (TowersManager `DAT_00699344`, ctor `54eb30`)
Bases (iaf.ibx sections, this order): 0 Ramon, 1 David, 2 TelNof, 3 Refidim, 4 Inshas, 5 Damescuss, 6 Kuzeir,
7 Bley, 8 Ryak, 9 Aman (0x51c bytes each): +0 TowerLoc, +0xc LineupLoc, +0x18 TwrCubeLoc, +0x24 to-taxi, +0x114
from-taxi, +0x204 hangars (x, y, hdg, turn x, y, hdg; 0x18 each), +0x4d8 greeting, +0x4dc wind (kt), +0x4e0
RunwayNumber (int degrees), +0x4f0 hangar count, +0x4f4 hangar taken flags.

Zones (`5bea90(r, nx, ny, nz, pose)`: nx·ny·nz spheres of radius r, centres 2r apart about the pose, local y along the
heading). Both at the LineupLoc, heading = RunwayNumber wrapped to (−180, 180]:
- runway zone +0x331c: r 1500, 1 × 30 × 1 → a corridor ±43.5 km (+r) along the runway, 3 km wide and high
  (`550850`);
- lineup zone +0x3344: r 100, 1 × 4 × 1 → ±400 m along the runway, 200 m wide (`550b20`).

Manager fields: +0x3318 current base (−1 none), +0x336c state, +0x3370 timer, +0x3374 timer period, +0x337c runway
clear, +0x3388 last message (0xb = none).

**Wind** (`551320`, at mission load from misc **0x46a**): 0, 10, 15 or 20 kt as is, anything else a random one of
{0, 10, 15, 20} (`rand() % 4`), the same for all bases. The tower says "wind is NN knots" / "no wind".

**Timer** (`550e40(period)`): a repeating event "TowersManagerTimer" every `period` s (restarted at each call).
Flight start (`54f8f0`, from the flight start next to the FlightController's `54af40`): timer 1 s, state 0, last 0xb.

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

**ground()** (`54fef0`): not on the ground → state 2 (period field 4, the timer is not restarted). Else h = the
nearest hangar of the base within 1000 m (`5521c0`, −1 none: the original then reads the entry before the table,
uninitialised memory — taken as "no hangar"). If the player's landed flag (brain +0xe0, set at a landing, v1.1
cleared at lift-off) is 0:
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
**lineup(b)** (`5504e0`): runway_clear = 1; for every object in the lineup zone: the player → in = 1; an aircraft
(class 0x1c) slower than 1 m/s that is not the player's formation leader / wingman → runway_clear = 0. Returns `in`
only if |ftol(runway heading − player heading)| ≤ 45 (both in degrees, (−180, 180], the difference not wrapped).
**runway(b)** (`550240`): the same with the runway zone, but runway_clear is computed only when aligned.

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
**say(code)** (`551c20`, on the base): callsign = the player's formation name (`5513c0`: kinds 2–6, 9, 10 by name,
else "Alpha") + `_t`; rwy = RunwayNumber / 10; wind = `WI_KNOTS%02d` or none.

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

Codes 0–10: the phrase is printed (`FUN_0044a060`) and played, then **ACFT_ROGER** ("Roger", the pilot) is played
after it (not printed). The tower names (TI_RAMON_TWR …) and ACFT_PROCEED_TO_RUNWAY's "this is … tower" variant are
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
(If the wingman is on the ground but the 1.5 s timer did not fire, the command is applied: kept.)
The network branch (a remote wingman: message 0x21) is not ported.

**engage_any** (`440860`): if the radar holds a target T: an aircraft T → its formation partner (`5bcb90`, else the
formation leader), if alive; else search around T for its class. Without a target: search around the player, any
class. Search: within 9270 m, not the player nor W, alive, class ∈ {0x1c, 2, 3, 1, 10, 9, 8, 0xb, 0xd, 0x1d, 0x1e,
5, 6, 0xf, 0x10}, (around T: the same class as T, not T), hostile; the nearest. Only a hostile result is returned.

**What the wingman does** is in its bdb brain: condition 29 (own brain +0x48) rules switch to a sub-brain (action
1000, which clears +0x48) and fire a type-7 response with the reply audio, e.g. "AA wing command" brains 49–52 / 60:
6 → sub-brain 40 + "Roger, closing formation." (audio 250), 5 → 44 + "Roger, going tactical." (251), 2 → 41 +
"Roger, bugging out." (252), 1 → 39 + "Roger, I'm on my way." (255), 3 → 46 / 39 + "Roger, engaging target." (253),
4 → 46 / 39 + "Roger, engaging." (254). The manoeuvres are the brain actions (190 close formation, 200 tactical, 250
go home …, ai.md §5).

## 4. FlightController reports (`DAT_00699348`, ctor `54acc0`)
One-shot events; each says `%S1 …` with S1 = the unit's callsign (`54ccb0`: formation name + "Leader" (member 0) or
"Wingman", upper-cased; empty — no report — for "Other"; a unit without a formation gets "<name> - No formation", not
a key). Reported only outside network games and for units on the **player's side** (`4a4cf0`; without a player
sides 2 / 3 are skipped), and only with a callsign. Printed and played.

| event | posted by | delay | template |
|---|---|---|---|
| WayptReport (`453740` → `54dc00(unit, wp)`) | the player's waypoint sequencing (`452960`, after `4532a0`: wp = the new current waypoint) and an AI WayPtSet moving on (`5d7450`, wp = the new index ≠ brain+0x88) | 3 s (0x600e00) | PASS_WAYPT_PHRASE, S2 = `G%d` (G1…G25); wp 0: none |
| AirborneReport (`54e310`) | TakeoffCL above 100 m AGL (`5cdb5d`, 0x613018) | 3 s | AIRBORNE_PHRASE |
| LandedReport (`54de90`) | StopPlaneCL (`5d6900` area) | 3 s | LANDED_PHRASE |
| CrashedReport (`54e0e0`) | `4aa2b0` | 2.5 s | CRASHED_PHRASE |
| EjectReport (`54e560`) | ejection `5485a0` | 4.5 s | EJECTED_PHRASE |
| kill reports | weapons | 5 s | SHOT_ENEMY / SHOT_BY_ENEMY / SHOT_GROUND_TARGET (`54d8d0` ground names) / SHOT_FRIENDLY_PHRASE |

**AWACS contact calls** (FlightControllerTimer, `54af40` / `54b130`; traced in outline): every 12 s (single player),
the first after 4 more periods (`50 / 12`); a 55 620 m (30 nm) sphere around the player; every alive, controlled
aircraft in it other than the player and the wingman, flying higher than terrain + 175 m, gets bearing / range /
heading from the player; a 24-slot contact table (60-tick lifetime, `54b790`, `54ac20` change test) decides between
ACFT_FCTRL_LONG (`%S1` = callsign `_r`, BEARING%03d, MILES%02d (≤ 35, > 10 rounded down to 5), description, HEADING%03d,
instruction) and ACFT_FCTRL_SHORT; the description / instruction pairs are friendlies (0), target + free to engage
(1), target + already engaged (2, `rand() % 9 == 6`), unidentified + please identify (3). The hostility / range gate
(0x60caa0) and the change test are not fully read (UNCERTAIN).

## 5. Port (`game/audio/radio.gd`)
- `Radio.expand()` / `say()`: the phrase engine from the two .trx files; the parts queue on the phrase channel
  (`flight_sounds.gd` channel 101, speech bus); the text goes to the subtitle console (`terrain_view._on_subtitle`).
- Tower: §2 literally (bases from iaf.ibx, the two zones as sphere chains, the timer on the flight's sim time).
- Wingman commands: §3 on the AI wingman's brain (`brain.gd` `wingman_command` / `target`); NEGATIVE after 3 s.
- Waypoint reports: the player's (`controls/autopilot.gd` sequencing) and the AI's (`ai_flights.gd`, the autopilot's
  waypoint index moving on) at +3 s; the ejection's "<callsign> ejected" uses EJECTED_PHRASE.
- Not built: the AWACS contact calls, the airborne / landed / crashed / kill reports (they need the take-off /
  landing loop hooks and the combat job).

## UNCERTAIN
- The phrase channel queues (the parts of one phrase must follow each other); whether a new phrase waits for or cuts
  a running one is not traced (queued here). Mission voices (`_voice`) still replace each other.
- The hangar entry −1 (uninitialised memory) read as "no hangar".
- The zone frame's local y along the runway heading (the chains are symmetric, so only the axis matters).
- A missing particle key: the entry keeps its previous wav / text (stale); here the part is skipped.
