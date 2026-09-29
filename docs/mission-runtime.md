# Mission runtime — what the engine does with a loaded .mis

File format: [formats/mis.md](formats/mis.md). This document covers the runtime side: entity event slots,
radius checks, events, scripts, and mission end. It applies to every mission. `takeoff.mis` is the worked
example (§7). Addresses are in `iafjets.exe`. Most of the code referenced here is **not** in
`assets/ghidra/iafjets.c`, because Ghidra did not find those functions: they are reached only through vtables
or indirect calls. Re-decompile them with a headless script, `DecompAt`-style: create the function at the
address, then decompile it.

**Main finding: nothing runs per frame.** Everything is driven by:

- entity state changes (hit, destroyed);
- periodic 4-second radius-check timers;
- one-shot script-entry timers;
- events fired by the above.

A re-implementation needs only a timer queue and hooks for the entity state changes.

## 1. Runtime objects

| object | where | built by |
|---|---|---|
| Scenario manager | global `DAT_00694934`, ctor `FUN_004ba146` | loads events (`FUN_004b9488`), spawns entities (`FUN_004b6bd3` → `FUN_004b6d17`), audio map at +0x58, entity map at +0xd4 |
| Debrief unit (`debriefUnit.cpp`) | global `DAT_0069494c`, ctor `FUN_00597020` | per-mission init `FUN_00597350`, entity-death hook `FUN_00597730`, end-of-flight compile `FUN_00597a80` |
| Entity status (`MStatus`) | entity+0x1c | +0x0c state (1 alive, 3 damaged, 4 destroyed, 5 exploded/final), +0x14 control mode, +0x18 **role**, `FUN_004a8600` = switchControlStatus |
| Entity scenario object | entity+0x20 | fields listed in §2. Initialised from the spawn descriptor by `FUN_004a5c40`. Ctor part at `0x5986b9`: all slots 0, sensor flag +0xdc = **1** |
| Script lists | scenario+0x08 (motion = `scripts0`), scenario+0x48 (trigger = `scripts1`) | `FUN_004b789a` / `FUN_004b847a` |

Registry `[Scenario] LoadScripts` (default 1; `FUN_00588d80` → `DAT_0066aa04`): when it is 0,
`FUN_0058cb50` zeroes every slot, the radius and both script counts, so the mission runs with no scenario logic.

### Control mode (entity 0x320 bit 0) — `FUN_004b6d17` @`0x4b70b1`, activation `FUN_004a8890`
- `0x320 & 1 = 1`: status+0x14 = 2, **MISSION_CONTROLLED**. At activation `FUN_004a5960` runs. It jumps both
  script lists to **entry index 1** (scenario +0xe0/+0xe4, set to 1 in `FUN_004a5c40`). It then arms the radius
  check (§2.2).
- `0x320 & 1 = 0`: 1 = **BRAIN_CONTROLLED**. The AI brain drives the entity. Scripts do **not** auto-start and
  radius checks are **not** armed. Event actions (§3.4) can still jump its scripts.
- Players are switched to 3 = PLAYER_CONTROLLED. Leaving MISSION_CONTROLLED kills the scenario (`FUN_004a58b0`,
  "killScenario(): … is dead"). This sets scenario+0x88 = 1, which blocks further script jumps.

### Role (entity 0x32a) → status+0x18 (`FUN_004bedb0` @`0x4b7126`)
This field decides win and loss (§6). Distribution over all missions: 2 = 3.8k entities, 1 = 445, 0 = 223.

| 0x32a | meaning |
|---|---|
| 0 | **must survive**: its destruction fails the mission |
| 1 | **target**: the mission succeeds when *all* role-1 entities are destroyed |
| 2 | neutral |

- Only in network play is the role of `PlayerN` forced to 2 (when `DAT_0082e07c` != 0 and option +0x59c == 0,
  `FUN_0058cb50`). In single player the file value is used.
- Named sensors confirm the rule: "Win sensor" and "sucsess sensor" are 1, "Loose sensor" and "Red win sensor" are 0.

## 2. Entity event slots (0x334 name / 0x33e id / 0x348 / 0x352)

Copy path:

- entity item +0x34+16i = {0x33e, 0x334, 0x348, 0x352};
- `FUN_0058fc50`: local +0x28+16i;
- `FUN_0058cb50`: spawn descriptor (`@0x58d8ab`);
- `FUN_004a5c40`: scenario.

`0x334` is only the editor's display copy of the event name. `0x352` is never read.

| slot | descriptor | scenario | runtime meaning |
|---|---|---|---|
| 0 | +0xd0 | +0x8c | **evHit**: fires event `0x33e` when the entity goes alive→damaged (state 1→3, `FUN_004a8280` → `FUN_004a7880` → `FUN_004a59c0`) |
| 1 | +0xd4 | +0x90 | **evDestroy**: fires event `0x33e` when the entity reaches state 4 or 5 (`FUN_004a7a00` / `FUN_004a7ba0` → `FUN_004a5a90`), then killScenario |
| 2 | +0xe4 | +0x94 | **evNotDestroy**: at end of flight, for every entity that is not destroyed and still has a live scenario, `FUN_00597a80` → `FUN_004a5b40` shows **debrief item id `0x33e`**. The id is looked up in the debrief map, not the event map. The editor stores event names here (244 of 246 uses), so the data and code disagree. Implement what the code does. |
| 3 | +0xe0 | +0x98 | stored; **no reader found** (3 uses in the data, all named "…Combat") — UNCERTAIN |
| 4 | +0xe8, `0x348`→(float)+0xf0 | +0x9c, radius +0xa4 | **evLeft** event id = `0x33e`. **`0x348` = the radius used by the reached and left checks** (world units ≈ m) |
| 5 | +0xec | +0xa0 | **evReached**: event id `0x33e` |
| 6 | — | — | unused |

- Hit and destroy events fire only if the **sensor flag** (scenario+0xdc, initialised to 1) is on. Otherwise the
  engine only logs "will not send scenario event due to sensor off!".
- Trigger ops 16 and 17 set the flag to 1 and 0.
- Every fire goes through `FUN_004b9e84(&id,0)`. Id 0 (and any id not in the event map) does nothing.

### 2.1 Watched entity (entity item `+0xac`)
Descriptor +0xf4..+0x104 = the 5-dword runtime key of the entity whose id equals `+0xac` (`@0x58d917`). The
scenario stores it at +0xc4. `-1` means no key: the check finds no target and is never armed (`FUN_004a5d10`
leaves +0xc0 = 0).

### 2.2 Reached / left check (`FUN_004a5d10`, `FUN_004a5ee0`, `FUN_004a6480`)
1. At activation (MISSION_CONTROLLED only), if the reached id (+0xa0) or the left id (+0x9c) is non-zero, and
   the watched entity exists:
   - schedule `MScenarioEntityReachedTimer` (vtbl `0x5ff188`);
   - first run now, **period 4.0 s** (`FUN_004ceab0(ev,&now,&4.0)`).
2. On each tick:
   - own position → +0xb4..+0xbc (`FUN_004a5e50`, this entity's *current* position, so markers moved by Path
     count);
   - read the watched entity's position;
   - test **3-D distance² < radius²** (`FUN_004a6310`, altitude included).
3. On the first hit:
   - log "evReached(): Entity A within reach of entity B";
   - **cancel the timer**;
   - if the sensor flag is on, fire the reached id.
   - Then, if the left id != 0, schedule `MScenarioEntityLeftTimer` (vtbl `0x5ff198`, period 4.0 s).
4. Left tick: when distance² ≥ radius², fire the left id once and cancel. Both reached and left fire at most
   once per activation.

**Where the audio-marker radii (70/85/500/1300 m) come from:** each marker's slot 4 `0x348`. The watched entity
is `+0xac` = 1 = Player1.

### 2.3 "Sensor" entities
- bdb Objects id 130 `sensor` spawns runtime class **0x12 `FireSensor`** (class name table `FUN_004a4230`).
- It senses nothing special. It is an invisible entity that uses the same generic slots, radius checks and
  scripts as any other entity. Its collision radius is 5.0 (`FUN_004b6d17`: desc+0x108 = 0 → 5.0).
- Designers use sensors as logic nodes:
  - a radius sensor (slot 4/5 around the player, or around another watched unit);
  - a script holder;
  - a **win/lose token**.
- **"Explode" on a sensor** is trigger op 5, which destroys the sensor (state 5). This runs evDestroy and then
  the role rule (§6). A role-1 sensor exploding counts as a destroyed target (success once all role-1 entities
  are gone). A role-0 sensor exploding fails the mission.

## 3. Events (`CDMEEventItem`)

### 3.1 Build (`FUN_004b9488` → `FUN_004b9656`; record from doc vtbl+0xc0 `FUN_0058e590`)

| event object E (0x3c B) | source |
|---|---|
| +0x00 id | 0x1e |
| +0x04 debrief id | 0x38e |
| +0x08 audio id | 0x3ac |
| +0x0c text | bdb Audio **0x140 subtitle** of 0x3ac if 0x3ac != -1, else 0x3a2. No reader of E+0xc was found; the text shown on screen comes from the audio record (§3.3) |
| +0x10 condition | cond0 AND cond1 (`FUN_004bb4d0`) or whichever exists, else NULL |
| +0x14 counter action | cond2 |
| +0x18 **executions left** | **0x398** |
| +0x1c/+0x20 action count / list | CList actions |

Condition `k`: `{0x3de counter id, 0x3d4 operator code, 0x3ca value}`. The strings 0x3b6 and 0x3c0 are
editor-only. The record copies cond1's operator from an uninitialised slot (+0x20), which is a bug.

- `FUN_004b9a0f` (cond 0/1): builds a comparison only if `1 ≤ counter id ≤ #counters`.
  - Counters: `DAT_0083f0d0` (max id+1), 0x14-byte integer vars, initial value 0.
  - Operator codes (`FUN_004b554d`, var = counter, v = value): **0 `==`**, 1 var>v, 2 var<v, **3 `>=`**, 4 var≤v, 5 `!=`.
- `FUN_004b9ae0` (cond 2 = action on a counter; `FUN_004b9bb1`): 6 var=v, 7 var+=v, 8 var-=v, 9 var--, **10 `++`**.

**In all 131 shipped missions every counter id `0x3de` is unset** (0xCDCDCDCD or -1). So no event has a
condition or a counter action, and "COUNT", "NUMOFLAUNCHERS", `==`/`++`/`>=` never take effect. They are
listed above for completeness only.

### 3.2 Fire (`FUN_004b9e84` → `FUN_004c2b25`)
1. If E+0x18 == 0, or the condition is present and false, stop.
2. Run the counter action (if any). Then **E+0x18 -= 1**. With 0x398 = 1 the event fires once. N means the first
   N triggers. 0 means it never fires (6 events).
3. If the audio id is not 0 or -1: `manager->PlayMessage(audio)` (`FUN_004ba7ee`, §3.3).
4. If the debrief id is not 0 or -1: `debrief->Add(id)` (`FUN_00597680`).
   - Look up the debrief item. If not yet shown, append `"\n\n" + 0x26c`.
   - Flag `0x262` == 0 → append to unit+0x3c. Flag 1 → append to unit+0x40.
   - The final debrief text is +0x3c followed by +0x40.
5. If single player (`DAT_00694990[1]==0`) or host: for each action run `FUN_004c2cd6` (§3.4).

### 3.3 PlayMessage (`FUN_004ba7ee`) — audio and subtitle
- Look up the bdb Audio record (manager+0x58, filled from bdb Audio `0x12c/0x136/0x140`).
- **Sound:** `DAT_0069495c->FUN_004c4c40(wav,0,1)`.
  - Path = registry `[Sound] SoundFilesPath` (default `.\SoundFiles\`) + `0x136`, with `.wav` appended if there is
    no dot. In the install this is `resource/soundfiles/`, lower-case, so match case-insensitively.
  - The last argument 1 routes it to the speech channel (handle kept at +0x38).
- **Subtitle:** `FUN_004491c0(0x140)` pushes lines into a 40-line console (`DAT_00832100/04/88`, 128-byte slots).
  - Word-wrapped at the last space before 40 chars, recursively (`FUN_00450eb0`). The first char is
    upper-cased.
  - Skipped entirely when text messages are off (`DAT_0062b05c`, cheat "Text messages off").
- **Drawing:** `FUN_0051e6a0`, from the cockpit renderer `FUN_0051df10`.
  - The newest ≤14 non-empty lines, oldest first, `TextOutA` at **x=4, y=10+15·n** (640×480 cockpit
    coordinates). The same console holds the chat input line at y=220.
  - Font = cockpit +0x580 = `CreateFontA(12,4,…,"ARIAL")`.
  - Colour = current HUD colour, table +0x285c[+0x2888] (see mfd.md; default green).
  - No expiry timer was found: lines stay until scrolled out (UNCERTAIN).

### 3.4 Actions (`FUN_004c2cd6`)
- Each record `{entity id, s0, s1}` is resolved to the entity key (doc vtbl+0xc4 `FUN_0058e920`).
- `s0` ≠ 0/-1 → `scenario->JumpMotion(s0)` (`FUN_004c3110`). `s1` → `JumpTrigger(s1)` (`FUN_004c3140`).
- The index is the script's **list index** (the `+0x10` / "raw10" value in the JSON), not its 0x1e id.
- A jump is ignored if scenario+0x88 is set (killScenario). It works in any control mode.

## 4. Scripts

`ScriptList::Jump(i)` (`FUN_004a4740`): current := i, start := now.
- **Execute** entry i on the owner entity.
- If the entry's duration ≠ -1.0 (`DAT_0082d718`), schedule its end timer at now+duration (`FUN_004a5060`).

On the end timer (`FUN_004a4d90`): current := entry.next (0x898). If that is 0 or -1, the list stops. Otherwise
execute that entry and schedule its end timer.

- Record builders: `FUN_0058e360` → `FUN_0058e130` (trigger), `FUN_0058de90` → `FUN_0058dc30` (motion).
- Factories: `FUN_004b85ec` (trigger, switch on the opcode) and `FUN_004b7a09` (motion).
- Both set **duration = (double)`0x87a` seconds** (sim clock, `DAT_00694910+0x38`).
  - Motion adds TimeVar `0x884` seconds when `0x884` ≥ 1 (`FUN_0058de50`).
- `Wait N` is a no-op entry whose duration is N. Every entry, not only Wait, holds the list for `0x87a` seconds
  before the next one runs. For example, "Visible off" with `0x87a`=7 waits 7 s.
- Duration 0 means the next entry runs on the next timer dispatch.

**The two lists have separate opcode spaces.**

### Trigger list (scripts1). Execute = vtbl[0] of the class built for the opcode.

| op | editor name | Execute | effect |
|---|---|---|---|
| 1 | Launch at location | `0x5c0d30` | fire weapon at point (floats 0x852/0x85c…) — UNCERTAIN args |
| 2 | Launch at target | `0x5c0ec0` | `FUN_004aa5b0(target key from 0x8ac entity id, …)` |
| 3, 4, 15, 18, 19, 23, 26 | (15 = **Wait**, 19 = "Destroy entity") | `0x5c0ee0` | **no-op** (only the duration). Op 19 is a no-op in this build |
| 5 | **Explode** | `0x5c0ef0` | `FUN_004a8280(0,5,…)`: set damage level 5, entity destroyed. Skipped for the player when `FUN_004d7040()` is true (UNCERTAIN) |
| 6 | — | `0x5c0f20` | fire scenario event (arg) |
| 7 | **Play message** | `0x5c0f40` | `PlayMessage(0x8ac)` (§3.3); 0 = none |
| 8 | — | `0x5c0f60` | subtitle console `FUN_004491c0(string 0x848)` |
| 9 | — | `0x5c0f80` | `FUN_0044ca90(arg)` — UNCERTAIN |
| 10 | — | `0x5c0fa0` | killScenario |
| 11 / 12 | Shield on / off | `0x5c0fb0` / `0x5c0fd0` | entity+0x10 → +8 = 1 / 0 (invulnerable) |
| 13 / 14 | **Visible on / off** | `0x5c0ff0` / `0x5c1000` | `FUN_00463300` / `FUN_004632b0` (show / hide model) |
| 16 / 17 | — | `0x5c1010` / `0x5c1030` | sensor flag on / off (scenario+0xdc) |
| 20 | — | `0x5c1050` | `FUN_004baaec(arg)` + `FUN_004a8600(1)` (back to brain control) — UNCERTAIN |
| 21 / 22 | Enable / Disable combat | `0x5c1090` / `0x5c10a0` | `FUN_004407e0` / `FUN_00440790` |
| 24, 25, 27, 28 | — | `0x5c10b0`… | status+0x1c = 0, 1, 2, 3 — UNCERTAIN |

### Motion list (scripts0)

| op | name | Execute | effect |
|---|---|---|---|
| 1 | **Hover** | `0x5c04c0` | motion mode 1: hold position |
| 5 | Turn | `0x5c0550` | motion mode 5 with arg (heading?) — UNCERTAIN |
| 11 | Yaw to target | `0x5c05f0` | turn toward the target entity. Helicopter model ids use a 1 s re-aim timer. Otherwise mode 9 |
| 16 | **Path** | `0x5c0910` | mode 0xe, `FUN_0047aed9(path, …)`: follow CDMEPathsItem `0x8ac` (details below) |

Path details:
- The traverse time is the entry's duration. Duration -1 gives the default 1e7.
- Offset flag from floats 0x85c/0x866/0x870. `0x884 == -1` selects variant 2.
- Exact kinematics UNCERTAIN. With a 1 s duration the entity effectively jumps to the path's last point.

Opcodes absent from the data (motion 2–4, 6–10, 12–15; trigger 6, 8–10, 16–18, 20, 23–28) exist in the
factories. They are listed only where the Execute was read.

## 5. Mission end

### 5.1 Role accounting — `FUN_00597730(entity)`
Called from the entity final-status path `FUN_004a7e30` (after destroy) and from `FUN_005464f0` (player crash).
Mission start (`FUN_00597350`) sets `unit+0x6618 = #entities with role 1` (`FUN_005981b0`), and clears passed
(+0x34), failed (+0x35) and result (+0x6615).

**Rule 1 — all players dead.** For player slots 1..4 (1..2 in campaign), `FUN_00598250` checks whether a player
entity exists with state ≠ 4/5. If none does:
- result := 0;
- post game event **0x82** at now + **5.0 s** (`DAT_0083f0e8`).

**Rule 2 — role of the dying entity:**
- **role 0**, not already failed (single player ignores "already passed"):
  - `PlayMessage(misc 0x4c4)`;
  - failed := 1, result := 0;
  - post **0x81** at now + **10.0 s** (`DAT_0083f0d8`).
- **role 1**:
  - `--unit+0x6618`;
  - when it reaches 0 and the mission is neither passed nor failed: `PlayMessage(misc 0x4ce)`;
  - passed := 1, **result := 1**;
  - post **0x80** at now + 10.0 s.
- **role 2**: nothing.

There is **no** landing, time or waypoint end condition. The landed/crashed/drowned classification in
`FUN_00471bdd` is flight-model only. A mission with no role-1 entity can never succeed automatically.

### 5.2 Message box — `CIAFWindow::OnGameEvent` `FUN_004e1c20`

Single player:

| event | box | text (`txt/msgs.trx` line) | buttons |
|---|---|---|---|
| 0x80 | `FUN_004e2790(13, reply, 0, 0x10000)` | 13 "Mission Accomplished! " | DEBRIEF, CONTINUE (`mbgfly`) |
| 0x81 | `FUN_004e2790(14, reply, 0, 0x20000)` | 14 "Mission failed." | DEBRIEF, CONTINUE, EXIT |
| 0x82 | no box: `FUN_004e1a90` ends the flight at once (game events 0x76, 0x7e), then the debrief | — | — |

- The box text is **fixed** from msgs.trx. The misc texts are *not* shown in it.
- In network play the text ids are 0x35/0x36 when `DAT_00836c88 == 0x213` or `FUN_004efe30()`.
- Button results (`FUN_004e3830`): DEBRIEF = 100, CONTINUE = 101, EXIT = 102. They are sent as
  `SendMessage(IAFWnd, 0x559, 3, result)`.
- Handler `FUN_004e1a10`:
  - 100 (or 6 = YES from the Esc "quit mission?" box) → flight window +0x150 = 3, `FUN_004e1a90`: **end the flight
    and go to the debrief**;
  - 101 → close the box and **keep flying** (the mission stays passed or failed);
  - 102 → `FUN_004ecd90`, flight window +0x150 = 8, `FUN_004d7670(1)`: leave the flight **without** the debrief
    (back to the menus).

**Player dead (single player):**
- The player is normally role 0. At the moment of death both 0x81 (+10 s) and 0x82 (+5 s) are posted.
- The 0x82 handler ends the flight after 5 s, so the "Mission failed." box normally never appears (UNCERTAIN: the
  queue is flushed when the flight ends).
- The player's slot-1 event (for example "Player dead") fires first and adds its debrief text.

### 5.3 Debrief compile — `FUN_00597a80`, at flight shutdown (`FUN_004ba427`)
1. Each surviving entity with a scenario → evNotDestroy (slot-2 debrief, §2).
2. Destroyed entities → kill lists (+0x1f90, +0x3ecc).
3. Single player:
   - result +0x1f84 := passed (+0x6615);
   - headline text +0x5e0c := **misc 0x47e if passed, else misc 0x492**;
   - notes +0x620c := unit+0x3c + unit+0x40.

Misc fields as the engine uses them (via doc vtbl+0x90 `FUN_0058b160` → unit fields in `FUN_00597350`):

| misc | unit | used |
|---|---|---|
| 0x47e text | +0x1c | debrief headline when passed (default "Mission passed") |
| 0x4ba audio | +0x20 | **no reader found** |
| 0x492 text | +0x24 | debrief headline when not passed (default "Mission failed") |
| 0x4c4 audio | +0x28 | played at the role-0 failure |
| 0x4a6 text | +0x2c | not used in single player (default "Passed") |
| 0x4ce audio | +0x30 | **played at success** (for example 43 "The terrorist attack on Haifa has failed.") |

mis.md's "second failure" labels for 0x4a6 and 0x4ce are wrong.

The start time (0x460) is overridden by option +0x584 (0..3 → 43200 / 21600 / 68400 / 79200 s).

## 6. Implementation checklist
1. Spawn entities. For `0x320&1` entities, start both script lists at list index 1 and arm the radius check
   (4 s period, 3-D).
2. Hook entity hit, destroy and death: fire slot 0 or 1 (if the sensor flag is on), then kill the scenario, then
   run the §5.1 rules.
3. Firing an event: executions-left, PlayMessage (wav + subtitle console), debrief append, script jumps.
4. Script entries run on enter and hold for `0x87a` seconds. The opcode tables are in §4.
5. End: 0x80/0x81 box after 10 s, 0x82 auto-end after 5 s. The debrief headline is 0x47e or 0x492, plus the notes.

## 7. Worked example — takeoff.mis ("Engines ON")

Entities: Player1 is role 0. "Win sensor" (6) is class 18, role 1, 0x320 = 0, so it is brain controlled and its
scripts do not auto-start. It is the only role-1 entity, so the success counter = 1.

| entity | pos | slot 4 / 5 | watched | scripts at start (index 1) |
|---|---|---|---|---|
| 2 First audio marker | 356585, 600001 (776 m, brg 152° from spawn) | r 70 / reached → ev 1 | Player1 | trig: Visible off (7 s) → Play Eagle1 |
| 4 Second audio | 356732, 600205 (251 m NE of #2) | r 85 / reached → ev 2 | Player1 | trig: Visible off |
| 5 Third audio | 1, 1 (off-map) | r 1300, **left → ev 3** / — | Player1 | motion: Hover; trig: Visible off |
| 3 Finish audio marker | 355071, 603101 | r 500 / none | -1 | trig: Visible off (inert) |

Sequence (the player spawns at 356226, 600689, heading 150):

| # | trigger | engine result |
|---|---|---|
| 1 | t = 0 | markers go invisible. The Win sensor is idle |
| 2 | t = 7 s | marker 2's second entry: **Eagle1** (211, `eagle 1.wav`): "Hi, my name is Jonathan… Start the engine by pressing 1, … B … 0 … taxi to the end of this taxi runway, and turn left." |
| 3 | player within 70 m (3-D) of marker 2, checked every 4 s | event 1: **Eagle2** (212): "Let's go over the pre-takeoff checklist… Line up on the runway and let's do it." |
| 4 | player within 85 m of marker 4 (runway threshold; runway runs ≈330° toward marker 3) | event 2: **Eagle3** (213): "Increase power to full afterburner… at 145 knots pull back gently". Action (5, s0 = 2): marker 5's motion jumps to **Path "Third audio jump"** with 1 s duration, which moves it from (1,1) to 356732, 600205, i.e. onto marker 4 |
| 5 | next 4 s tick | marker 5's reached check succeeds (reached id 0, so nothing plays). The left check is armed |
| 6 | player > 1300 m (3-D) from that point: the takeoff roll or climb-out | event 3: **Eagle4** (214): "Raise the landing gear by pressing G, retract the flaps by pressing F…". Action (6, s1 = 2): the Win sensor's trigger jumps to "Wait to win" |
| 7 | +15 s | "Play win message": **GOOD WORK** (audio 23, `o good work.wav`, subtitle "Good work.") |
| 8 | +1 s | "Sensor explode": the Win sensor is destroyed. It is role 1, so the counter reaches 0 and the mission passes (misc 0x4ce = -1, so no extra audio) |
| 9 | +10 s | box: "Mission Accomplished! " with DEBRIEF and CONTINUE. The debrief headline is 0x47e "Mission - successful. Congratulations, you took off successfully." |

The player needs only to reach marker 2 and marker 4, then get 1.3 km away from marker 4. Being airborne is not
checked.

Unused data in this mission:
- Event 4 "Finish audio" (text "Good work, you first mission is successful.") is referenced by no slot, so it
  never fires.
- The 0x3a2 texts of events 1–3 are never shown. The subtitles come from the bdb Audio 0x140 strings.

Failure: if Player1 is destroyed, event 5 fires and adds debrief 1 ("The first rule of success in every mission
- STAY ALIVE."). After 5 s the flight ends (0x82) and the debrief headline is 0x492 "Mission - failed. Better
try again."

## 8. Corrections to formats/mis.md and open items

Corrections:
- Slot meanings are in §2. Slot 2 is a debrief id, not a "landed" event. Slot 4 is left + radius, slot 5 is
  reached.
- 0x32a = role. 0x320 bit 0 = mission vs brain control.
- 0x398 = the maximum fire count.
- 0x3d4 = the operator code, 0x3de = the counter id.
- The misc audio pairing is in §5.3.
- Script opcodes: scripts0 and scripts1 have separate opcode spaces (§4).

UNCERTAIN / open:
- Slot 3 reader.
- Args of trigger ops 1, 2, 9, 20, 24–28.
- Exact Path kinematics.
- The player-exempt test in Explode (`FUN_004d7040`).
- Subtitle lifetime.
- Whether the 0x81 box can appear after 0x82 has ended the flight.
- Where the Deb screens draw +0x5e0c and +0x620c (front-end).
