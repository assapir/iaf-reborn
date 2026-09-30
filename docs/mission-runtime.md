# Mission runtime — what the engine does with a loaded .mis

Addresses are `IAFJets.exe` **v1.1** (the reference version); [v1.1.md](v1.1.md) maps them to v1.0 and lists what the patch changed.

File format: [formats/mis.md](formats/mis.md). This document covers the runtime side: entity event slots,
radius checks, events, scripts, and mission end. It applies to every mission. `takeoff.mis` is the worked
example (§7). Addresses are in `iafjets.exe`. Most of the code referenced here is **not** in
`assets/ghidra_v11/iafjets.c`, because Ghidra did not find those functions: they are reached only through vtables
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
| Scenario manager | global `DAT_006992f4`, ctor `FUN_004baa63` | loads events (`FUN_004b9da5`), spawns entities (`FUN_004b74f0` → `FUN_004b7634`), audio map at +0x58, entity map at +0xd4 |
| Debrief unit (`debriefUnit.cpp`) | global `DAT_0069930c`, ctor `FUN_00599650` | per-mission init `FUN_00599980`, entity-death hook `FUN_00599da0`, end-of-flight compile `FUN_0059a0f0` |
| Entity status (`MStatus`) | entity+0x1c | +0x0c state (1 alive, 3 damaged, 4 destroyed, 5 exploded/final), +0x14 control mode, +0x18 **role**, `FUN_004a8e70` = switchControlStatus |
| Entity scenario object | entity+0x20 | fields listed in §2. Initialised from the spawn descriptor by `FUN_004a64c0`. Ctor part at `0x59b229`: all slots 0, sensor flag +0xdc = **1** |
| Script lists | scenario+0x08 (motion = `scripts0`), scenario+0x48 (trigger = `scripts1`) | `FUN_004b81b7` / `FUN_004b8d97` |

Registry `[Scenario] LoadScripts` (default 1; `FUN_0058b340` → `DAT_0066f2cc`): when it is 0,
`FUN_0058f110` zeroes every slot, the radius and both script counts, so the mission runs with no scenario logic.

### 1.1 The player object (`FUN_004bb439`, at mission load)
- `DAT_00699320` (the player entity) = the flight map's leader of flight **1**, else of flight 2, 3, 4
  (`FUN_005bcb40(n)`). A flight is a formation with `0x3f2` = 1..4 of the main file; its leader is member 0
  if spawned, else member 1 (docs/front-end.md §8 flight table). The name does not matter: campaign and
  scramble missions have no `Player1` (e.g. 324 "Player", 221 "alpha_1").
- The TSD's default flight is the formation holding that object (`FUN_005bcd70`). Picking another flight
  (Alpha–Delta button + Fly, or double-clicking its leader) makes that flight's leader the player object
  (`FUN_005045b0` → `FUN_004d31f0`).
- The player's position, altitude and heading are the leader entity's; the ground / airborne start rules are
  docs/flight-model.md §15.6.4. The aircraft type is the leader's bdb type (`0x5b4`), except in the training
  missions entered through the Jet list.
- **Port:** `mission_runtime.gd` `player_flight(mission, wanted)`; `Settings.player_flight` carries the TSD
  choice; `terrain_view.gd` starts at that entity and hands its id to the runtime (the entity flagged
  `player`). Only the F-16 flies: another type is logged and flown as the F-16. Test: test_player_flight.

### Control mode (entity 0x320 bit 0) — `FUN_004b7634` @`0x4b79ce`, activation `FUN_004a9100`
- `0x320 & 1 = 1`: status+0x14 = 2, **MISSION_CONTROLLED**. At activation `FUN_004a61e0` runs. It jumps both
  script lists to **entry index 1** (scenario +0xe0/+0xe4, set to 1 in `FUN_004a64c0`). It then arms the radius
  check (§2.2).
- `0x320 & 1 = 0`: 1 = **BRAIN_CONTROLLED**. The AI brain drives the entity. Scripts do **not** auto-start and
  radius checks are **not** armed. Event actions (§3.4) can still jump its scripts.
- Players are switched to 3 = PLAYER_CONTROLLED. Leaving MISSION_CONTROLLED kills the scenario (`FUN_004a6130`,
  "killScenario(): … is dead"). This sets scenario+0x88 = 1, which blocks further script jumps.

### Role (entity 0x32a) → status+0x18 (`FUN_004bf5b0` @`0x4b7a43`)
This field decides win and loss (§6). Distribution over all missions: 2 = 3.8k entities, 1 = 445, 0 = 223.

| 0x32a | meaning |
|---|---|
| 0 | **must survive**: its destruction fails the mission |
| 1 | **target**: the mission succeeds when *all* role-1 entities are destroyed |
| 2 | neutral |

- Only in network play is the role of `PlayerN` forced to 2 (when `DAT_00832ad4` != 0 and option +0x59c == 0,
  `FUN_0058f110`). In single player the file value is used.
- Named sensors confirm the rule: "Win sensor" and "sucsess sensor" are 1, "Loose sensor" and "Red win sensor" are 0.

## 2. Entity event slots (0x334 name / 0x33e id / 0x348 / 0x352)

Copy path:

- entity item +0x34+16i = {0x33e, 0x334, 0x348, 0x352};
- `FUN_00592210`: local +0x28+16i;
- `FUN_0058f110`: spawn descriptor (`@0x58fe6b`);
- `FUN_004a64c0`: scenario.

`0x334` is only the editor's display copy of the event name. `0x352` is never read.

| slot | descriptor | scenario | runtime meaning |
|---|---|---|---|
| 0 | +0xd0 | +0x8c | **evHit**: fires event `0x33e` when the entity goes alive→damaged (state 1→3, `FUN_004a8ae0` → `FUN_004a8100` → `FUN_004a6240`) |
| 1 | +0xd4 | +0x90 | **evDestroy**: fires event `0x33e` when the entity reaches state 4 or 5 (`FUN_004a8280` / `FUN_004a8420` → `FUN_004a6310`), then killScenario |
| 2 | +0xe4 | +0x94 | **evNotDestroy**: at end of flight, for every entity that is not destroyed and still has a live scenario, `FUN_0059a0f0` → `FUN_004a63c0` shows **debrief item id `0x33e`**. The id is looked up in the debrief map, not the event map. The editor stores event names here (244 of 246 uses), so the data and code disagree. Implement what the code does. |
| 3 | +0xe0 | +0x98 | stored; **no reader found** (3 uses in the data, all named "…Combat") — UNCERTAIN |
| 4 | +0xe8, `0x348`→(float)+0xf0 | +0x9c, radius +0xa4 | **evLeft** event id = `0x33e`. **`0x348` = the radius used by the reached and left checks** (world units ≈ m) |
| 5 | +0xec | +0xa0 | **evReached**: event id `0x33e` |
| 6 | — | — | unused |

- Hit and destroy events fire only if the **sensor flag** (scenario+0xdc, initialised to 1) is on. Otherwise the
  engine only logs "will not send scenario event due to sensor off!".
- Trigger ops 16 and 17 set the flag to 1 and 0.
- Every fire goes through `FUN_004ba7a1(&id,0)`. Id 0 (and any id not in the event map) does nothing.

### 2.1 Watched entity (entity item `+0xac`)
Descriptor +0xf4..+0x104 = the 5-dword runtime key of the entity whose id equals `+0xac` (`@0x58fed7`). The
scenario stores it at +0xc4. `-1` means no key: the check finds no target and is never armed (`FUN_004a6590`
leaves +0xc0 = 0).

### 2.2 Reached / left check (`FUN_004a6590`, `FUN_004a6760`, `FUN_004a6d00`)
1. At activation (MISSION_CONTROLLED only), if the reached id (+0xa0) or the left id (+0x9c) is non-zero, and
   the watched entity exists:
   - schedule `MScenarioEntityReachedTimer` (vtbl `0x603050`);
   - first run now, **period 4.0 s** (`FUN_004cf270(ev,&now,&4.0)`).
2. On each tick:
   - own position → +0xb4..+0xbc (`FUN_004a66d0`, this entity's *current* position, so markers moved by Path
     count);
   - read the watched entity's position;
   - test **3-D distance² < radius²** (`FUN_004a6b90`, altitude included).
3. On the first hit:
   - log "evReached(): Entity A within reach of entity B";
   - **cancel the timer**;
   - if the sensor flag is on, fire the reached id.
   - Then, if the left id != 0, schedule `MScenarioEntityLeftTimer` (vtbl `0x603060`, period 4.0 s).
4. Left tick: when distance² ≥ radius², fire the left id once and cancel. Both reached and left fire at most
   once per activation.

**Where the audio-marker radii (70/85/500/1300 m) come from:** each marker's slot 4 `0x348`. The watched entity
is `+0xac` = 1 = Player1.

### 2.3 "Sensor" entities
- bdb Objects id 130 `sensor` spawns runtime class **0x12 `FireSensor`** (class name table `FUN_004a4d40`).
- It senses nothing special. It is an invisible entity that uses the same generic slots, radius checks and
  scripts as any other entity. Its collision radius is 5.0 (`FUN_004b7634`: desc+0x108 = 0 → 5.0).
- Designers use sensors as logic nodes:
  - a radius sensor (slot 4/5 around the player, or around another watched unit);
  - a script holder;
  - a **win/lose token**.
- **"Explode" on a sensor** is trigger op 5, which destroys the sensor (state 5). This runs evDestroy and then
  the role rule (§6). A role-1 sensor exploding counts as a destroyed target (success once all role-1 entities
  are gone). A role-0 sensor exploding fails the mission.

## 3. Events (`CDMEEventItem`)

### 3.1 Build (`FUN_004b9da5` → `FUN_004b9f73`; record from doc vtbl+0xc0 `FUN_00590b50`)

| event object E (0x3c B) | source |
|---|---|
| +0x00 id | 0x1e |
| +0x04 debrief id | 0x38e |
| +0x08 audio id | 0x3ac |
| +0x0c text | bdb Audio **0x140 subtitle** of 0x3ac if 0x3ac != -1, else 0x3a2. No reader of E+0xc was found; the text shown on screen comes from the audio record (§3.3) |
| +0x10 condition | cond0 AND cond1 (`FUN_004bbda0`) or whichever exists, else NULL |
| +0x14 counter action | cond2 |
| +0x18 **executions left** | **0x398** |
| +0x1c/+0x20 action count / list | CList actions |

Condition `k`: `{0x3de counter id, 0x3d4 operator code, 0x3ca value}`. The strings 0x3b6 and 0x3c0 are
editor-only. The record copies cond1's operator from an uninitialised slot (+0x20), which is a bug.

- `FUN_004ba32c` (cond 0/1): builds a comparison only if `1 ≤ counter id ≤ #counters`.
  - Counters: `DAT_00843c5c` (max id+1), 0x14-byte integer vars, initial value 0.
  - Operator codes (`FUN_004b5e6a`, var = counter, v = value): **0 `==`**, 1 var>v, 2 var<v, **3 `>=`**, 4 var≤v, 5 `!=`.
- `FUN_004ba3fd` (cond 2 = action on a counter; `FUN_004ba4ce`): 6 var=v, 7 var+=v, 8 var-=v, 9 var--, **10 `++`**.

**In all 131 shipped missions every counter id `0x3de` is unset** (0xCDCDCDCD or -1). So no event has a
condition or a counter action, and "COUNT", "NUMOFLAUNCHERS", `==`/`++`/`>=` never take effect. They are
listed above for completeness only. `DAT_00843c5c` (#counters) is the largest counter id any event names, + 1.
Port: `mission_runtime.gd` builds the counters, conditions and counter actions anyway (`counters`, `_condition`,
`_counter_action`); an operator code outside 0..5 in a condition (cond1's copied junk) is taken as false (UNCERTAIN).

### 3.2 Fire (`FUN_004ba7a1` → `FUN_004c3425`)
1. Run the counter action (if any), on **every** trigger (v1.1; v1.0 ran it in step 2, only when the event fired).
2. If E+0x18 == 0, or the condition is present and false, stop.
3. **E+0x18 -= 1**. With 0x398 = 1 the event fires once. N means the first N triggers that pass the condition. 0 means
   it never fires (6 events).
4. If the audio id is not 0 or -1: `manager->PlayMessage(audio)` (`FUN_004bb10b`, §3.3).
5. If the debrief id is not 0 or -1: `debrief->Add(id)` (`FUN_00599cf0`).
   - Look up the debrief item. If not yet shown, append `"\n\n" + 0x26c`.
   - Flag `0x262` == 0 → append to unit+0x3c. Flag 1 → append to unit+0x40.
   - The final debrief text is +0x3c followed by +0x40.
6. If single player (`DAT_00699350[1]==0`) or host: for each action run `FUN_004c35d6` (§3.4).

### 3.3 PlayMessage (`FUN_004bb10b`) — audio and subtitle
- Look up the bdb Audio record (manager+0x58, filled from bdb Audio `0x12c/0x136/0x140`).
- **Sound:** `DAT_0069931c->FUN_004c5470(wav,0,1)`.
  - Path = registry `[Sound] SoundFilesPath` (default `.\SoundFiles\`) + `0x136`, with `.wav` appended if there is
    no dot. In the install this is `resource/soundfiles/`, lower-case, so match case-insensitively.
  - The last argument 1 routes it to the speech channel (handle kept at +0x38).
- **Subtitle:** `FUN_0044a060(0x140)` pushes lines into a 40-line console (`DAT_00836b58/04/88`, 128-byte slots).
  - Word-wrapped at the last space before 40 chars, recursively (`FUN_004514b0`). The first char is
    upper-cased.
  - Skipped entirely when text messages are off (`DAT_0062f064`, cheat "Text messages off").
- **Drawing:** `FUN_005201b0`, from the cockpit renderer `FUN_0051fa20`.
  - The newest ≤14 non-empty lines, oldest first, `TextOutA` at **x=4, y=10+15·n** (640×480 cockpit
    coordinates). The same console holds the chat input line at y=220.
  - Font = cockpit +0x580 = `CreateFontA(12,4,…,"ARIAL")`.
  - Colour = current HUD colour, table +0x285c[+0x2888] (see mfd.md; default green).
  - No per-line expiry. Lines leave the window only by being scrolled out, and a 3 s ticker keeps
    scrolling (see "Subtitle lifetime" below).

#### Subtitle lifetime
**Console layout** (`DAT_00836b58`):
- `+0` = slot count, always 40. `+4` = the slot buffer, 40×128 bytes. `+8` = the 128-byte chat input line.
- `+0x88` = the ring, an array of 40 slot offsets. Its last entry is the newest line. `+0x8c` = chat-input
  flag.
- It is built by `FUN_004e2960` @`4e2c22`: `malloc(0x1400)` and `malloc(0xa0)`, every slot set to "".

**Push** (`FUN_0044a060` inline, `FUN_004514b0`, `FUN_004d9710`):
- Copy the text into the slot at ring[0], which is the oldest.
- Shift ring[1..39] down by one and put that slot at ring[39].
- Every push, including an empty one, ages all other lines by one position.

**Draw** (`FUN_005201b0`):
- Scans ring indices 39 down to 26. That is the **14 newest slots** (loop `esi > count-15`, collect array
  `0x83ddd8..0x83de10` = 14 entries).
- Keeps only non-empty strings. Draws them compacted (no gaps for empty slots), oldest at y=10, then +15 each.
- The chat line is drawn separately at y=220. Its `_` cursor toggles every 400 ms (`0x83de6c`/`0x65c6c0`).

**The 3 s ticker** (`FUN_004d95e0`, called first thing from the per-frame sim render `FUN_004d9080` @`4d908c`):
- Function-static timer `0x8338a8` (guard bit `0x8338c8`), created once by `FUN_004d3fe0(3.0f)`.
  - `+0` last and `+8` next are both initialised to 1.0e7 (`.rdata 0x604f58`). `+0x10` = 0, `+0x14` = 3.0,
    `+0x18` = 0 (not random).
- Each frame, `FUN_004d4100(&simtime)` runs with `simtime` = double at `DAT_006992d0+0x38`.
  - It fires when `now > next` **or** `now < last`. The second case covers the first poll and a sim clock
    that restarted.
  - On fire: `last = now`, `next = now + 3.0`. There is no catch-up, so it fires at most once per frame.
- On fire: `CharUpperBuffA(0x78dd44,1)`, `len = strlen(0x78dd44)`, then a push. If `len >= 40`, it is split
  at the last space (as in `FUN_004514b0`).
- **`0x78dd44` is the program's shared empty string ""**:
  - It sits in zero-initialised `.data` (beyond the raw data, which ends at 0x6847b8). No `.data`/`.rdata`
    word points at it.
  - All ~100 code references only read it. They use it as the GetPrivateProfileStringA default (`406de5`,
    `4e1a7a`, `4c78e1`→`FUN_004d3b00`, …), a CString ctor/assign source (`452cef`, `452d53`, `452dc2`,
    `456ae0`, `4f024c`), a strcpy source (`445876`, `4c6732`, `4c86b7`, `4f1849`, …), an `_stricmp`
    operand (`4fae81`, `4fef9e`), a `sprintf` format (`52f448`, `538222`), SetWindowText (`4e6e14`,
    `4e720b`), and a `char buf[N] = ""` initialiser (`4ea810`, `502fdc`).
  - `CharUpperBuffA` on its NUL byte is a no-op.
  - So the ticker **pushes one empty line every 3.0 s of sim time**. It does this even with text messages
    off (it does not test `DAT_0062f064`).
  - UNCERTAIN: a few sites hand the pointer out in a register (`541227` returns it, `5b30c6`, `5b4b54`,
    `5c8875`, `5c49b7`). No write through them was found. This looks like a leftover of a debug-message
    feed.

**Rule:**
- A line is visible while fewer than 14 pushes have happened after it. It disappears on the 14th push after
  its own. That push can be a tick or any later line: each wrapped line of a later subtitle, or any other
  console message such as the 50+ `FUN_0044a060` callers (cockpit/weapon/radio messages) and chat.
- With no other traffic, the first tick after the push comes 0–3 s later, and the line vanishes at the 14th
  tick. **Lifetime = 39–42 s of sim time** (≈40.5 s on average, quantised to frames).
- More traffic shortens it. For example, a 3-line wrapped message leaves only 11 pushes of lifetime for
  the older lines.
- Empty slots are not drawn, and the visible lines stay packed from y=10 downward. A tick therefore changes
  nothing on screen until it pushes the oldest visible line out. Then the remaining lines move up one row
  (15 px). A new line always appears below the others.
- The clock is sim time, so time compression shortens the lifetime in wall-clock terms. If the sim clock
  stops while paused, the lines freeze (UNCERTAIN: pause behaviour of `+0x38` not checked).

**Clearing:**
- Nothing clears the console at mission start or on a view change.
- The only writers of `0x836b58/04/88` are:
  - `FUN_004e2960` (main-window creation, once per run).
  - `FUN_004e3070` @`4e30db` (same re-allocation, all 40 slots emptied; `FUN_004e71e0` also empties the chat
    line). `FUN_004e3070` is reached from the message-box callbacks for message 0x55a (`CIAFWindow` map
    `0x605888` → `FUN_004e3050` when result == 6; flight-window map `0x605338` → `FUN_004dc650`) and from
    `FUN_004dc500` (message 0x55b, result 7, single player).
  - UNCERTAIN: which user-facing flight exit takes this path. The debrief exit `FUN_004e3230` does not touch
    the console.
- Lines left over from a previous flight therefore scroll out within ≤42 s of the next flight's sim time.
  The ticker fires on the first frame, because the new sim time < `last`.

### 3.4 Actions (`FUN_004c35d6`)
- Each record `{entity id, s0, s1}` is resolved to the entity key (doc vtbl+0xc4 `FUN_00590ee0`). A record whose
  lookup returns 0 is skipped (v1.1; v1.0 went on with the null entity).
- `s0` ≠ 0/-1 → `scenario->JumpMotion(s0)` (`FUN_004c3a10`). `s1` → `JumpTrigger(s1)` (`FUN_004c3a40`).
- The index is the script's **list index** (the `+0x10` / "raw10" value in the JSON), not its 0x1e id.
- A jump is ignored if scenario+0x88 is set (killScenario). It works in any control mode.

## 4. Scripts

`ScriptList::Jump(i)` (`FUN_004a5250`): current := i, start := now.
- **Execute** entry i on the owner entity.
- If the entry's duration ≠ -1.0 (`DAT_00832170`), schedule its end timer at now+duration (`FUN_004a5b70`).

On the end timer (`FUN_004a58a0`): current := entry.next (0x898). If that is 0 or -1, the list stops. Otherwise
execute that entry and schedule its end timer.

- Record builders: `FUN_00590920` → `FUN_005906f0` (trigger), `FUN_00590450` → `FUN_005901f0` (motion).
- Factories: `FUN_004b8f09` (trigger, switch on the opcode) and `FUN_004b8326` (motion).
- Both set **duration = (double)`0x87a` seconds** (sim clock, `DAT_006992d0+0x38`).
  - Motion adds TimeVar `0x884` seconds when `0x884` ≥ 1 (`FUN_00590410`).
- `Wait N` is a no-op entry whose duration is N. Every entry, not only Wait, holds the list for `0x87a` seconds
  before the next one runs. For example, "Visible off" with `0x87a`=7 waits 7 s.
- Duration 0 means the next entry runs on the next timer dispatch.

**The two lists have separate opcode spaces.**

### Trigger list (scripts1). Execute = vtbl[0] of the class built for the opcode.

| op | editor name | Execute | effect |
|---|---|---|---|
| 1 | Launch at location | `0x5c4160` | fire weapon at point (floats 0x852/0x85c…) — UNCERTAIN args |
| 2 | Launch at target | `0x5c42f0` | `FUN_004aae40(target key from 0x8ac entity id, …)` |
| 3, 4, 15, 18, 19, 23, 26 | (15 = **Wait**, 19 = "Destroy entity") | `0x58a330` | **no-op** (only the duration). Op 19 is a no-op in this build |
| 5 | **Explode** | `0x5c4310` | `FUN_004a8ae0(0,5,…)`: set damage level 5, entity destroyed (docs/damage.md §3). Skipped for the player when `FUN_0058a350()` is true (UNCERTAIN) |
| 6 | — | `0x5c4340` | fire scenario event (arg) |
| 7 | **Play message** | `0x5c4360` | `PlayMessage(0x8ac)` (§3.3); 0 = none |
| 8 | — | `0x5c4380` | subtitle console `FUN_0044a060(string 0x848)` |
| 9 | — | `0x5c43a0` | `FUN_0044d760(arg)` — UNCERTAIN |
| 10 | — | `0x5c43c0` | killScenario |
| 11 / 12 | Shield on / off | `0x5c43d0` / `0x5c43f0` | entity+0x10 → +8 = 1 / 0 (no damage, no collisions; docs/damage.md §2.1) |
| 13 / 14 | **Visible on / off** | `0x5c4410` / `0x5c4420` | `FUN_00463f10` / `FUN_00463ec0` (show / hide model) |
| 16 / 17 | — | `0x5c4430` / `0x5c4450` | sensor flag on / off (scenario+0xdc) |
| 20 | — | `0x5c4470` | `FUN_004bb409(arg)` + `FUN_004a8e70(1)` (back to brain control) — UNCERTAIN |
| 21 / 22 | Enable / Disable combat | `0x5c44b0` / `0x5c44c0` | `FUN_00440830` / `FUN_004407e0` on the unit's brain. Enable: +0x6c = 0, then (v1.1) the brain is reset (`FUN_0043eef0`: unschedules it, drops its current plan and target). Disable: +0x6c = 1; if engaged (+0x68): clear it, control mode 1 (`FUN_004aa900(1)`, the mission script drives the unit), tell the plan, and (v1.1) `MBrain::transferControl` (`FUN_004401d0`: drops the brain's scheduled event, mode 1 again, aircraft (class 0x1c) re-set up). Port: an entity `combat` flag only (no AI brains yet) |
| 24, 25, 27, 28 | — | `0x5c44d0`… | status+0x1c = 0, 1, 2, 3 — UNCERTAIN |

### Motion list (scripts0)

| op | name | Execute | effect |
|---|---|---|---|
| 1 | **Hover** | `0x5c38b0` | motion mode 1: hold position |
| 5 | Turn | `0x5c3940` | motion mode 5 with arg (heading?) — UNCERTAIN |
| 11 | Yaw to target | `0x5c39e0` | turn toward the target entity. Helicopter model ids use a 1 s re-aim timer. Otherwise mode 9 |
| 16 | **Path** | `0x5c3d00` | mode 0xe, `FUN_0047b9a9(path, …)`: follow CDMEPathsItem `0x8ac` (details below) |

Path details:
- The traverse time is the entry's duration. Duration -1 gives the default 1e7.
- Offset flag from floats 0x85c/0x866/0x870. `0x884 == -1` selects variant 2.
- Exact kinematics UNCERTAIN. With a 1 s duration the entity effectively jumps to the path's last point.

Opcodes absent from the data (motion 2–4, 6–10, 12–15; trigger 6, 8–10, 16–18, 20, 23–28) exist in the
factories. They are listed only where the Execute was read.

## 5. Mission end

### 5.1 Role accounting — `FUN_00599da0(entity)`
Called from the entity final-status path `FUN_004a86b0` (after destroy) and from `FUN_005485a0` (**ejection**, §5.4).
`FUN_0059aca0(slot)` counts a player slot as alive only if its entity has state ≠ 4/5 **and** control mode
(status+0x14) ≠ 0. In a campaign (`DAT_00832adc`), a second aircraft of the slot also counts if it is a flyable jet
(type 100…200). UNCERTAIN: which aircraft that is (`FUN_005bcb90`).
Mission start (`FUN_00599980`) sets `unit+0x6618 = #entities with role 1` (`FUN_0059ac00`), and clears passed
(+0x34), failed (+0x35) and result (+0x6615).

**Rule 1 — all players dead.** For player slots 1..4 (1..2 in campaign), `FUN_0059aca0` checks whether a player
entity exists with state ≠ 4/5. If none does:
- result := 0;
- post game event **0x82** at now + **5.0 s** (`DAT_00843c70`).

**Rule 2 — role of the dying entity:**
- **role 0**, not already failed (single player ignores "already passed"):
  - `PlayMessage(misc 0x4c4)`;
  - failed := 1, result := 0;
  - post **0x81** at now + **10.0 s** (`DAT_00843c60`).
- **role 1**:
  - `--unit+0x6618`;
  - when it reaches 0 and the mission is neither passed nor failed: `PlayMessage(misc 0x4ce)`;
  - passed := 1, **result := 1**;
  - post **0x80** at now + 10.0 s.
- **role 2**: nothing.

There is **no** landing, time or waypoint end condition. The landed/crashed/drowned classification in
`FUN_0047263d` is flight-model only. A mission with no role-1 entity can never succeed automatically.

### 5.2 Message box — `CIAFWindow::OnGameEvent` `FUN_004e33c0`

Single player:

| event | box | text (`txt/msgs.trx` line) | buttons |
|---|---|---|---|
| 0x80 | `FUN_004e3f30(13, reply, 0, 0x10000)` | 13 "Mission Accomplished! " | DEBRIEF, CONTINUE (`mbgfly`) |
| 0x81 | `FUN_004e3f30(14, reply, 0, 0x20000)` | 14 "Mission failed." | DEBRIEF, CONTINUE, EXIT |
| 0x82 | no box: `FUN_004e3230` ends the flight at once (game events 0x76, 0x7e), then the debrief | — | — |

- The box text is **fixed** from msgs.trx. The misc texts are *not* shown in it.
- In network play the text ids are 0x35/0x36 when `DAT_0083b810 == 0x213` or `FUN_004f1770()`.
- Button results (`FUN_004e4ff0`): DEBRIEF = 100, CONTINUE = 101, EXIT = 102. They are sent as
  `SendMessage(IAFWnd, 0x559, 3, result)`.
- Handler `FUN_004e31b0`:
  - 100 (or 6 = YES from the Esc "quit mission?" box) → flight window +0x150 = 3, `FUN_004e3230`: **end the flight
    and go to the debrief**;
  - 101 → close the box and **keep flying** (the mission stays passed or failed);
  - 102 → `FUN_004ee5b0`, flight window +0x150 = 8, `FUN_004d8d90(1)`: leave the flight **without** the debrief
    (back to the menus).

**Player dead (single player):**
- The player is normally role 0. At the moment of death both 0x81 (+10 s) and 0x82 (+5 s) are posted.
- The 0x82 handler ends the flight after 5 s, so the "Mission failed." box normally never appears (UNCERTAIN: the
  queue is flushed when the flight ends).
- The player's slot-1 event (for example "Player dead") fires first and adds its debrief text.

### 5.3 Debrief compile — `FUN_0059a0f0`, at flight shutdown (`FUN_004bad44`)
1. Each surviving entity with a scenario → evNotDestroy (slot-2 debrief, §2).
2. Destroyed entities → kill lists (+0x1f90, +0x3ecc).
3. Single player:
   - result +0x1f84 := passed (+0x6615);
   - headline text +0x5e0c := **misc 0x47e if passed, else misc 0x492**;
   - notes +0x620c := unit+0x3c + unit+0x40.

Misc fields as the engine uses them (via doc vtbl+0x90 `FUN_0058d720` → unit fields in `FUN_00599980`):

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

### 5.4 Ejection / player lost (`FUN_005485a0`)
Generic for every mission and aircraft. The graphics side (seat, canopy, parachuter kinematics) is in
docs/part-animation.md "Ejection". All times are **sim time** `[0x6992d0]+0x38`.

**Key → 3-press rule.** Key record 17 "Eject (x3)" sends GEV 0x12 (DIK_E, params ignored). It goes through the usual chain
(0x532 → CIAFWindow default → `FUN_004cd3b0` → `FUN_004cd630`). Case 0x12 (@137847) requires the player controller
`DAT_00699308` ≠ 0. It calls `FUN_0044a240(0x12, p, forced = 1)`. Because of `forced`, the controller's "control mode ≠ 3 → ignore" guard
(@44a26b) is bypassed, so the key also works after the controls were taken away (state 3, see below). Case 0x12 (@44b5b5):
`FUN_00548330(player entity)` on the eject singleton `DAT_0083fab0` (`FUN_00548400`, 0x20 bytes: +0 pool begin, +4 pool end, +8 cap,
+0x10 "player's ejection" flag (**not initialised**), +0x14 press count, +0x18 last press time, double):
```
if now − last >= EjectKeyTimeDistance:  count = 1; last = now          // gap too long (or first press): restart
else: count += 1
      if count >= 3: count = 0; last = 0; Eject(entity)                  // FUN_005485a0
      else: last = now
```
`Eject/EjectKeyTimeDistance` defaults to **1.0 s** (`0x66135c`). The window is **between consecutive presses**, not the total.
Nothing is displayed or played on any press. In a network game each press is also sent to the other players (@44b5cc,
`FUN_00450d60(0x10,9)`, UNCERTAIN). The `[Eject]` defaults are read once, by `FUN_00548400`:

| key | default | global |
|---|---|---|
| `Interval` | 2.0 s (seat launch delay) | `0x661350` |
| `ParachuterFlyBy` | 5.0 s (camera switch to the parachuter) | `0x661354` |
| `RandomFlyby` | 1 (byte) | `0x661358` |
| `EjectKeyTimeDistance` | 1.0 s | `0x66135c` |
| `Speed` (crew ctor) | 3.0 m per 0.05 s tick | `0x65ffdc` |

**`FUN_005485a0(entity)`** (disassembly @5485a0; the Ghidra output is stack-garbled):
1. Abort if the crew is already out (`FUN_00540350`: crew obj +0xc == 0). Abort unless control mode (status+0x14) == 3
   (player-controlled) **or** state (status+0xc) == 3 (fatally hit, "going down").
2. Schedule the "FlightControllerEjectReport" event (vtable `0x60c908` → `FUN_0054e560`) at **t0 + 4.5 s** (`0x60c8c0` = −4.5).
   The radio says `EJECTED_PHRASE` = "%S1 EJECTED" (phrasetemplates.trx; `GEjected.wav` "ejected" after the callsign).
   This happens only if `DAT_00832ad8` == 0, the ejector is on the player's side (`FUN_004a4cf0`) and its callsign (`FUN_0054ccb0`) is not empty.
3. The aircraft is left to itself. Three FM motions go to `(entity+0x38)->vtbl[0]`:
   * **0x0f** arg 0: `FUN_005a1e40` → `FUN_005c8800`, `DAT_00843dec = 0` (UNCERTAIN: autopilot / steering mode off; args 1/2 = fly to point / follow target);
   * **0x19** arg 0: **engine off**, `S+0x1d0 = 0` (`FUN_005a2890`), so there is no thrust;
   * **1** stick: in+0x10 = 0.2, in+0x14 = 0.1 → `sY = S+0x2e4 = −0.2` (a slight push), `sX = S+0x2e8 = +0.1`
     (`FUN_0059f3d0`; ×0.25 if controller flag 0x12 is set, 0 if flag 0x18 is set, UNCERTAIN: damage flags).
   Throttle, gear, flaps and brakes are not touched. Then `FUN_004a8e70(0)`: **control mode 0**. The player's inputs are now
   ignored, and the FM keeps flying the unmanned jet until it hits the ground (normal crash path `FUN_004a86b0`). UNCERTAIN: the
   FM integrates normally in mode 0. The crashing-aircraft path `FUN_004a8100` uses the same mode.
4. `FUN_00599da0(unit, entity)` (§5.1) runs **at the moment of ejection**. The player now has mode 0, so rule 1 fires in single
   player: result 0, unit+0x661c = 1, **game event 0x82 at t0 + 5 s**. Rule 2 applies with the player's role (normally 0):
   `PlayMessage(misc 0x4c4)`, failed = 1, **0x81 at t0 + 10 s**. So an ejection counts exactly like losing the aircraft.
5. Altitude test: `agl = z − ground(x, y)` of the aircraft (vehicle +0x70 at t0).
   * **agl < 50 m** (`0x60c8b8`), or **50 ≤ agl < 200 m** (`0x60c8bc`) with |state angle[1]| > 90° (`0x60c8d8`, a double;
     UNCERTAIN: roll, i.e. inverted): **short ejection**. The canopy is thrown, the seat record is pushed (`FUN_0053fb00`,
     `FUN_0053ee90(t0+Interval)`), and game event **0x7f** is posted at once with the entity's packed id. No camera change.
   * otherwise, **full ejection**:
     * singleton+0x10 = (entity == player `DAT_00699320`);
     * `entity+4 → +8 = 1` (external viewer mode) and crew obj +8 = 0 (`FUN_005400c0(0)`), so the jet shows canopy and pilot from outside;
     * **camera**: if it is the player's ejection, **or** the current view is Radar-target (9), Chase (6) or Fly-by (0x13) and
       it looks at this entity: `FUN_005808c0(now, entity, {1500, 900, −200, −10°, 0°, 120°}, 2.0, **0x13 Fly-by
       view**, RandomFlyby)` looks at the **aircraft**. With RandomFlyby, the x and z offsets get a random sign, and each offset is multiplied by
       `0.5 + rand/32767` ∈ [0.5, 1.5]. The eye is kept ≥ ground + 15 m (`0x610e18`). (The offset frame is UNCERTAIN.)
       The cockpit is left at once;
     * canopy throw at t0, seats at t0 + Interval (as above);
     * if the player's ejection or the view condition holds: schedule "Eject camera change view event" (vtable `0x60c8f8`,
       `0x548a20`) at **t0 + ParachuterFlyBy = t0 + 5 s**. It sets the fly-by view (0x13) on the **parachuter** entity (the pool slot
       captured at t0) with `{1000, 600, 200, 230° (4.014257 rad), ·, 160° (2.792527 rad)}` (`0x60c8a4..ec`), 2.0, RandomFlyby.
       UNCERTAIN: the slot layout; the call is the same as above.
6. **Game event 0x7f "jump to tactical display"** (short ejection: at once; full ejection: at the parachuter's `land − 10 s`,
   only if singleton+0x10). In `FUN_004cd630` case 0x7f, single player: if the id is the player's and the player is dead
   (state 4/5) or has mode 0 → `SendMessage(IAFWnd, 0x532, 0x7f)`. That message is also sent to the descendants (`FUN_005e24c3`).
   `CFlightWnd::OnGameEvent` (`0x4dc280`, 0x7f → `0x4dc2b3`): flight window +0x150 = **1**, then `FUN_004d8d90(1)` closes the
   flight view. The parent (`0x681` handler `0x4e38d0`) posts game event 0x75(1) and opens screen **0x20 FlyTSD**
   (`dat/flytsd.trx`: Fly / Visit, formation Alpha–Delta). In network mission 0x21d it opens a box instead:
   msgs 12 "Do you want to rejoin?" (reply 0x55b). CIAFWindow ignores 0x7f.

**What the player sees (single player, not campaign):**

| t | event |
|---|---|
| 3rd press (each < 1.0 s after the previous one) | t0. The pilot part vanishes from the jet, and the seat model (ejectA) takes its place. Canopy flies straight up (v1.1; v1.0 also aft). Fly-by camera on the jet (full ejection). Jet: engine off, stick (−0.2, +0.1), no pilot input |
| t0 + 2.0 | seat (ejectA) starts rising 60 m/s relative to the jet (v1.1: straight up; v1.0 also drifted 30 m/s aft) |
| ≈ t0 + 3.65 | seat passes 100 m → becomes the parachuter entity (ejectB), v0 (25, 30, −5), gravity 3 m/s² |
| t0 + 4.5 | radio "<callsign> ejected" (friendly side only) |
| t0 + 5.0 | game event 0x82: the flight ends and the **debrief** opens (`FUN_004e3230`, flight window +0x150 = 3). The camera event at t0 + 5 also fires (order UNCERTAIN) |
| t0 + 10 | 0x81 ("Mission failed." box) — normally never seen, because the flight has ended (§5.2) |

A **short ejection** (low, or inverted at 50–200 m) posts 0x7f at t0. So the flight view closes at once into FlyTSD, and 0x82
still follows at t0 + 5 s (UNCERTAIN: how the two interact).
In a **campaign**, if the slot still has a live flyable aircraft, rule 1 does not end the flight. The full ejection then plays the
parachute and "jumps" to FlyTSD at `land − 10 s`, where the player can pick another aircraft (Fly). UNCERTAIN: the Fly
button logic was not traced.

**Debrief / score.** There is no special ejection text, pilot status or score. The ejection only goes through §5.1:
- result 0: headline misc 0x492 (default "Mission failed");
- "Mission failed." is msgs line 14; "Mission Accomplished! " is msgs line 13.

No "ejected"/"rescued"/"MIA" strings exist in the exe or the menu texts. The player's slot-1 "destroyed" event does **not**
fire on ejection, because the jet is not destroyed. UNCERTAIN: whether the still-flying jet gets the slot-2 "not destroyed" debrief line at flight end (§5.3 step 1).

**Voices.** Nothing is played on the key presses or at t0.
- `WINGMAN_EJECT_EJECT` (code `0x37007000`, `eject.wav`) is played only when the player's jet goes from state 1 to 3, i.e. is fatally hit
  (`FUN_004a8100` @108832). That path also sets control mode 0 and the crash motion, and switches the view to mode 0x10. This is the cue to press E three times.
- `BACKSEAT_EJECT` (0x36/7) is defined but not referenced.
- `parachute open.wav` is not referenced.

**Port:** `mission_runtime.gd` `player_ejected()` runs the role rules for the player at once and ends the flight
into the debrief 5 s later (event 0x82); the jet's later crash does not count again. A short ejection (AGL < 50 m,
or < 200 m with |roll| > 90°) ends the flight at once (the original opens its in-flight TSD, not built). Without a
mission the flight ends after 5 s. The radio plays `gejected.wav` at +4.5 s (the callsign part is not ported).

### 5.5 Landed handler (`FUN_00440f90`)
The flight model calls it at a gear-down touchdown of the player that passes the landing check, while the
controller's landed flag (`ctl+0xe0`) is 0, then sets the flag (docs/flight-model.md §15.6.2). v1.1 clears the flag at
lift-off, so it runs on **every** landing (v1.0: only the first landing of a flight). It looks up the route of the
player's formation (`FUN_005bcb90` / `FUN_005bcd70`) and, if the route's +0x2c is set, makes its last waypoint the
current NAV waypoint (`FUN_00440e90(count − 1)` → `FUN_00453450`: +0x44 = index, the waypoint copied, NAV state 5). It
fires no mission event: there is no scripted "landed" trigger (§5, §8). UNCERTAIN: route+0x2c, taken as "the route
has waypoints".
**Port:** `terrain_view.gd` `_on_landed()` runs whenever the flight state's `landings` counter grows and sets
`cockpit.current_waypoint` to the route's last waypoint (test `test_landed.gd`).

## 6. Implementation checklist
1. Spawn entities. For `0x320&1` entities, start both script lists at list index 1 and arm the radius check
   (4 s period, 3-D).
2. Hook entity hit, destroy and death (docs/damage.md §3: hit = state 1 → 3 at damage ≥ 0.8, destroy = state
   4 / 5): fire slot 0 or 1 (if the sensor flag is on), then kill the scenario, then run the §5.1 rules.
   **Port:** `mission_runtime.gd` `area_damage` / `apply_damage` / `set_damage_level` (docs/damage.md §4.3); the
   player's crash, collisions and Explode go through `set_damage_level(…, 5)`; rule 1 ("all players dead" →
   0x82 after 5 s) and rule 2 run once per unit (an ejection, then the jet's crash, counts once).
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
- The player-exempt test in Explode (`FUN_0058a350`).
- Subtitle lifetime: resolved in §3.3 (14 pushes; a 3 s empty-line ticker gives 39–42 s). Which exit path
  runs `FUN_004e3070` (console reset) is still open.
- Whether the 0x81 box can appear after 0x82 has ended the flight.
- Where the Deb screens draw +0x5e0c and +0x620c (front-end).
