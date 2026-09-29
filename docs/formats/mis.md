# .mis — mission files (and the .bdb object database they reference)

`resource/missions/*.mis` (131 files) are MFC `CArchive` dumps written by the original mission editor ("DME").
Every file parses end-to-end with `tools/probe_mis.py` (which also parses `default6_1.bdb`), so the
layout below is exact. Field *meanings* come from the game's use of them plus value statistics over all
131 missions; anything not backed by code is marked **UNCERTAIN**.

Loader: `FUN_00589720` (mission document `Serialize`), bdb: `FUN_0058a080`. Class `CRuntimeClass` table
at `0x66b2f0..0x66b5f0` (all schema 0x0b). All integers are little-endian.

## 1. Primitives

| name | encoding |
|---|---|
| `CString` | u8 len; if 0xFF → u16 len; if 0xFFFF → u32 len; then bytes (cp1252, no NUL) |
| `Count` | `CArchive::ReadCount` (`0x5e3ca3`): u16; if 0xFFFF → u32 |
| `Obj` | `CArchive::ReadObject` (`0x5e57f5`): u16 tag. `0x0000` = NULL. `0xFFFF` = new class: u16 schema, u16 name len, name; then the object body. `0x8000\|i` = class already seen at map index *i*; then the object body. Other `i` (< 0x7FFF) = back-reference to an already-loaded object. **Map indexing:** index 0 = NULL; every new class *and* every new object take the next index (class first). |
| `Field` (tagged) | u32 field id, u8 type char, value. `'S'` → CString (`FUN_00590710`); `'I'`/`'B'` → i32 (`FUN_00590800`); `'F'` → f32 (`FUN_005908d0`). Readers check the id and error out on mismatch, so order is fixed. |
| `Junk(n)` | n bytes of reserved space the editor filled with *uninitialised memory* (stack pointers, `0xCDCDCDCD`). Skip; never interpret. |

Many written fields are also uninitialised (`-842150451` = `0xCDCDCDCD`, or pointer-looking values such as
`9696508`): treat values outside a sane range as "unset".

### Item base (`CDMEDataItem::Read`, `FUN_00590610`) — prefix of every `*Item`/`*Rule`/`CDMEScriptObj`
```
u32    len        byte count of the tagged fields (informational; not needed to parse)
Field  0x14 'B'   flag: 1 on the editor's trailing "Add data here" placeholder row (and on all script objs)  UNCERTAIN
Field  0x1e 'I'   id  — 1-based id, unique within its part; everything cross-references by this id
Junk(0x200)
```
Every item then has its own fields followed (unless stated) by `Junk(0x200)`. Each `*Part` is a
`CObArray` (`Serialize` `0x590b30` → `CObArray::Serialize` `0x5dc861`): `Count`, then `Count × Obj`.
The **last item of every part is a placeholder named "Add data here"** — skip it.

## 2. File layout (`FUN_00589720`)
```
0x000  u32 magic   = 0x00068B3F
0x004  u32 version = 9 (128 files) or 8 (3 files)   → global DAT_0083f040, gates optional fields
0x008  Junk(0x1FC)
0x204  CString bdb name   ("default6_1.bdb" in every file; loaded from the same directory, FUN_00589d70)
       Obj CDMEMiscPart       mission header/texts          (doc +0x24)
       Obj CDMETimeVarsPart   named timers                  (+0x28)
       Obj CDMEPathsPart      named paths for scripts       (+0x2c)
       Obj CDMEEntitiesPart   all units / objects / markers (+0x30)
       Obj CDMEFormationPart  flights + waypoint routes     (+0x34)
       Obj CDMEDebriefPart    debrief texts                 (+0x38)
       Obj CDMEEventPart      events (triggers → actions)   (+0x3c)
EOF
```

## 3. Classes (reader address; `Fid type` in read order)

### CDMEMiscItem (`FUN_00593560`) — item 1 is the mission header
| fid | t | meaning |
|---|---|---|
| 0x44c | S | mission title ("Engines ON") |
| 0x456 | S | free text / sub-title, sometimes the briefing number ("232") — UNCERTAIN |
| 0x460 | F | start time of day, seconds after midnight (28800 = 08:00) |
| 0x46a | I | weather: probably wind speed or direction (0,10,240,270…) — UNCERTAIN |
| 0x474 | I | weather: the other of the pair (0,270,10,180…) — UNCERTAIN |
| 0x47e | S | success message text |
| 0x488 | S | (always empty) |
| 0x492 | S | failure message text |
| 0x49c | S | (empty) |
| 0x4a6 | S | second failure message text (e.g. time-out/abort) — UNCERTAIN |
| 0x4b0 | S | (empty) |
| 0x4ba | I | audio id (bdb Audio) for success message, -1 none (23 = "GOOD WORK") |
| 0x4c4 | I | audio id for failure, -1 none |
| 0x4ce | I | audio id for 2nd failure, -1 none |
| 0x4d8 | S | category / campaign label ("training", "Future/Lebanon") |
| 0x4e2 | I | unknown small int 0..7 — UNCERTAIN |
| 0x4ec | I | unknown small int 0..12 (players/flights?) — UNCERTAIN |

### CDMETimeVarsItem (`FUN_005939d0`)
`0x6a4 S` name ("Boats Reach Shore"), `0x6ae F` time in seconds.

### CDMEPathsItem (`FUN_00593d00`, `Serialize` `0x593cd0`)
`0x5dc S` name, `0x5e6 S` (empty), `Junk(0x200)`, then a `CList` (`0x596870`): `Count` × 24-byte raw
records `{i32 index, f32 x, f32 y, f32 alt, i32 0, i32 0}`. Used by the script op `Path` (16).

### CDMEEntitiesItem (`FUN_00594620`, 0xF8 bytes) — every unit, building, sensor and marker
Offsets = object offsets; `[n]` = dword index in the runtime spawn descriptor built by
`FUN_0058fc50` + `FUN_0058cb50` and consumed by the spawner `FUN_004b6d17`.

| fid | t | obj | meaning |
|---|---|---|---|
| 0x2bc | S | +0x0c | name ("Player1", "mig29_1"). Names `Player1..Player7` are the player slots (`s_Player` check in `FUN_0058cb50`) |
| 0x2c6 | I | +0x14 | **type** = bdb *Objects* item id (1 = f16, 2 = mig29, 51 = civilhouse, 130 = sensor) → `[6]` |
| 0x2d0 | I | +0x18 | **side**: 1 = Israel/blue, 2 = enemy/red, 0/3 rare (neutral?) → `[12]` |
| 0x2da | I | +0x20 | **brain** = bdb *Brains* item id (AI behaviour), -1 = none/human → `[13]` (`FUN_0058bf70` looks brains up by name) |
| 0x2e4 | I | +0x24 | **X** world position (east) → `[8]` as float |
| 0x2ee | I | +0x28 | **Y** world position (north) → `[9]` |
| 0x2f8 | I | +0x2c | **altitude** MSL (≈ m); ground units carry terrain height (e.g. 63 on Ramat David's runway, 1293 on the Golan) → `[10]` |
| 0x302 | I | +0x30 | **heading**, compass degrees (0 = N, clockwise; RD runway 15 → 150) → `[11]`; same meaning as the engine's `*Yaw` defaults |
| 0x30c | I | +0xbc | unused (always junk/0) |
| 0x316 | S | +0xc0 | group label ("Alpha leader", "SA-6 North") — UNCERTAIN |
| 0x320 | I | +0xc4 | 1 = surface unit (vehicles, buildings, markers), 0 = aircraft/sensor; `[7] = !(v&1)` selects spawn mode 1/2 in `FUN_004b6d17` — "on ground" semantics UNCERTAIN |
| 0x32a | I | +0xc8 | 0/1/2 → `[14]`; players get 2 (or 1) forced by options — AI skill? UNCERTAIN |
| 0x35c | I | +0xf4 | 0/1 → `[0x43]`; set on player and key friendlies/targets — UNCERTAIN (mission-critical flag?) |

Then **7 event slots** (i = 0..6, object +0x34+16i), each `0x334 S` event name (display copy),
`0x33e I` **event id** (CDMEEventItem id fired, 0 = none), `0x348 I` parameter, `0x352 I` (junk),
`Junk(0x200)`. Slot meaning inferred from names used across all missions — UNCERTAIN:
0 = hit/damaged ("friendly hit", "were hit"), 1 = destroyed ("Player dead", "Mig down"),
2 = other end-of-life/landed ("landed2", "Echo 1 Dest"), 3 = starts combat ("ZSU 1 Combat"),
4 = proximity, `0x348` = radius (70…10000) and fires its event when the watched entity comes
within it, 5 = "reached" events ("Tank reach sensor", "safe landing"), 6 = unused (junk).
In takeoff.mis marker slot 4 holds the radius while slot 5 holds the event.

Then (all version-gated reads in `FUN_00594620`):
```
Obj CObArray  scripts0   (+0xe0) of CDMEScriptObj
Obj CObArray  scripts1   (+0xe4) of CDMEScriptObj  (runs from mission start on markers/sensors)
Obj CArmament armament   (+0xe8)
9 bytes skipped (a Field whose value is ignored)
if scripts0 non-empty && version>=4: Field 0x8b6 I → +0xec   else 9 bytes skipped
if scripts1 non-empty && version>=4: Field 0x8b6 I → +0xf0   else 9 bytes skipped
if version>=8: i32 → +0xac, Junk(0x1e1)   else Junk(0x1e5)
```
`+0xec/+0xf0` look like editor counters (UNCERTAIN). `+0xac` = id of a *related entity*: the
target/watched unit (sensors → the flight they detect, ground units → what they engage), -1 none.

**CArmament** (`Serialize` `0x592b80`): raw 0x60 bytes = 12 stations × `{u32 bdb Weapons id, u32 count}`
(only the low byte of count is used, `FUN_00592bd0`). Stations 0–8 are pylons, 9–11 gun/chaff/flare.
At spawn, stations 9–11 always come from the object type's template (`FUN_00592c00`); stations 0–8 come from the
entity when any station is set (`FUN_00592ba0`), else from the type. takeoff.mis Player1: pylons empty,
`25 × 200` (20 mm), `33 × 60` (chaff), `34 × 60` (flare).

### CDMEScriptObj (`FUN_00593ff0`) — per-entity behaviour scripts (linked list by index)
| fid | t | meaning |
|---|---|---|
| 0x834 | S | name |
| 0x83e | I | **opcode** (see below) |
| 0x848 | S | string argument (audio name, path name, entity name) |
| 0x852,0x85c,0x866,0x870 | F | numeric args (0x852 = 1.0 for Path; others x/y/z? UNCERTAIN) |
| 0x87a | I | int argument, e.g. seconds for Wait (15) — UNCERTAIN in general |
| 0x884 | I | int argument, usually -1 (target entity id?) — UNCERTAIN |
| 0x88e | S | name of the next script ("N.A" = none) |
| 0x898 | I | index of the next script (matches the next script's *index* below), -1 = stop |
| 0x8a2 | S | opcode name (redundant with 0x83e) |
| 0x8ac | I | resolved id of the string argument (bdb Audio id for Play message, Paths id for Path), -1 |
then 4 bytes skipped, `i32 index` (+0x10, 1-based position within its list), `Junk(0x1f8)`.

Opcodes seen (id: name): 1 Hover (also "Launch at location"), 2 Launch at target, 5 Explode (also "Turn"),
7 Play message, 11 Shield on / Yaw to target, 12 Shield off, 13 Visible on, 14 Visible off, 15 Wait,
16 Path (jump/follow a CDMEPathsItem), 19 Destroy entity, 21 Enable combat, 22 Disable combat.
(A few ids carry two names — the editor reused slots; trust the number. UNCERTAIN.)

### CDMEFormationItem (`FUN_00594eb0`, `Serialize` `0x594e60`) — flights and their routes
```
0x3e8 S name ("Alpha", "Mig 29")   0x3f2 I kind (1 player flight, 8 enemy, 0..6, -1) UNCERTAIN
0x3fc I, 0x406 I  unused (junk)   Junk(0x200)
2 × { 0x410 S member name, 0x41a I member entity id (-1 none), 0x424 I target entity id (-1 none), Junk(0x200) }
CList waypoints (0x596870): Count × 24 bytes {i32 id, f32 x, f32 y, f32 alt, f32 speed, i32 action}
if version>=9: CList names (0x5969b0): Count × {u32 waypoint id, CString name} ("Departure", "Target", "Home")
```
Waypoints are in route order (ids are labels, not order). Speed values 60…1800 — probably km/h
(UNCERTAIN); `action` 0..8 (3 most common) — waypoint type, UNCERTAIN.

### CDMEDebriefItem (`FUN_00595260`)
`0x258 S` name, `0x262 I` 0/1 (probably 0 = failure debrief, 1 = success — UNCERTAIN), `0x26c S` text.

### CDMEEventItem (`FUN_00595620`, `Serialize` `0x5955f0`) — triggers
```
0x384 S name   0x38e I debrief id shown when it fires (-1 none)   0x398 I count/threshold (1 mostly) UNCERTAIN
0x3a2 S subtitle text   0x3ac I bdb Audio id to play (-1 none)   Junk(0x200)
3 × condition { 0x3b6 S variable ("", "COUNT", "NUMOFLAUNCHERS"), 0x3c0 S operator ("==", "++", ">="),
                0x3ca I value, 0x3d4 I (junk), [version>5: 0x3de I counter id, Junk(0x1f7)] else Junk(0x200) }
CList actions (0x596ae0): Count × {i32 entity id, i32 script index in scripts0 (-1), i32 script index in scripts1 (-1)}
```
Firing an event plays its audio/text, shows its debrief, and (re)starts the listed scripts on the listed
entities (829 of 892 action records resolve to existing script indices this way). Success/failure of
the mission is then driven by the scripts/debriefs — exact win/lose rule is an open question.

## 4. The .bdb object database (`FUN_0058a080`)
`u32 magic 0x0004D769`, then 6 `Obj` parts, *no* version (the loaded .mis version is used):
Present (221 3D models: `0x640 S` name, `0x64a S` model path `CONTROLLABLEPLANES\MIG29\MIG29_H.XFR`,
`0x654 I`, `[v>=5] 0x65e F`, Junk(0x1ee|0x1f7)), Weapons (62: `0x708 S` name "AA-10", `0x712 S` class,
… 14 fields `0x708..0x78a`), Actions (38 AI manoeuvres, `0x64..0xc8`), Audio (496: `0x12c S` name,
`0x136 S` wav file, `0x140 S` subtitle), Brains (67: `0x1f4 S` name, `0x1fe S`, `0x208 I`, u32 0x212,
`Obj CObList` rules, u32 0x21c, `Obj CObList` rules; `CDMEBrainRule` `0x190..0x1ae` + two CLists of 16- and
20-byte records, `Serialize` `0x592480`), Objects (182 unit types: `0x514 S` name "f16", `0x51e S` category
"Controlled aircraft", `0x528 S` display "F16", `0x532 S` default brain, 18 ints `0x53c..0x5d7`, Junk,
u32, `Obj CArmament` default loadout, u32, `Obj CObArray` of `CDMEWeaponLoadItem` (`FUN_00595930`),
Junk). Entity `type` → Objects id; Objects `0x53c` → Present id (model). Full parser: `probe_mis.load_bdb`.

## 5. Coordinates

Mission X/Y/alt are **engine world units** (≈ metres; X east, Y **north**, alt MSL). They are the same
units as the engine's hard-coded airbase spawn points (`FUN_0058c7a0`, registry `BlueTeam\*`):

| base | X | Y | Z | yaw |
|---|---|---|---|---|
| Tel Nof | 312984 | 500459 | 59 | 90 |
| Ramat David | 356404 | 602402 | 28 | 270 |
| Ramon | 317439 | 411135 | 579 | 230 |

Terrain (map.ptt) units, from the terrain object's world↔terrain transforms
(`0x4053b0` world→terrain, `0x405420` inverse; object `0x7749f0`, set up by `FUN_00405670`/`FUN_004026e0`):
```
tx = (X - DataXShiftPR) / PlaneScalePR      DataXShiftPR = -166850, PlaneScalePR = 1.2411389
ty = (DataYShiftPR - Y) / PlaneScalePR      DataYShiftPR = 1043780   (ty grows southward = ptt row order)
X  = tx * PlaneScalePR + DataXShiftPR ;  Y = DataYShiftPR - ty * PlaneScalePR
```
Check: the three bases map to (386608, 437760), (421592, 355623), (390197, 509729) — each inside a
level-0 airbase inset of map.ptt (records 31–33, 28–30, 25–27). (Vertical: the same transform
divides height by PlaneScale and adds a sea-level offset; verify against map.ptt elevations — open.)

### Worked example — takeoff.mis ("Engines ON", training mission 311, `brief/txt/311.brl` → "takeoff")
Entity 1 `Player1`: type 1 (f16), side 1, brain -1, X = 356226, Y = 600689, alt 63, heading 150,
armament gun 200 / chaff 60 / flares 60, slot 1 (destroyed) → event 5 "Player dead" → debrief 1
"The first rule of success in every mission - STAY ALIVE.".
→ terrain `tx = 523076 / 1.2411389 = 421448.4`, `ty = 443091 / 1.2411389 = 357003.6`: inside inset
records 28–30 (x 416768–428032, y 352256–360448) = **Ramat David AB**, 1.7 km from its default spawn
point; level-0 tile column 36, row 37, pixel (72, 12). Heading 150° = runway 15. Other entities:
`Player2..7` (types 40 F15, 17 f4, 74 Lavi, 48, 47 mirage, 99 CFIR; X = Y = -1, i.e. unused slots
for other aircraft choices — UNCERTAIN), three invisible `civilhouse` audio markers along the runway
(proximity radii 70/85/500 m) that fire events 1–4 (instructor audio Eagle1–4, bdb audio 211–214), and a
`sensor` "Win sensor" whose scripts1 chain Wait → Play message "GOOD WORK" (audio 23) → Explode, started
by events 3/4 via action `(6, -1, 2)`. Start time 08:00. Formation "Alpha" = member "player" (entity 1),
one waypoint "Departure" (347870, 602383, 1000, 900, action 3).

Note: in campaign/multiplayer modes the game overrides `PlayerN` positions with the airbase spawn table
above (+1666/+3333/+5000 altitude depending on an options field, `FUN_0058cb50`); single missions use
the file values.

## 6. Open questions

**See [../mission-runtime.md](../mission-runtime.md).** It decodes the runtime: slots, 0x32a role, 0x320 control
mode, 0x398, the conditions, both script opcode tables, the win/lose rule and the misc audio usage. Where it
disagrees with the guesses above, it takes precedence.

- Exact win/lose rule (debrief 0x262 flag? scripted Explode of a `sensor`? misc 0x4e2/0x4ec?).
- Slot semantics 0/2/3/5, script float args, formation `0x3f2` and waypoint `action`, misc 0x46a/0x474.
- Whether `0x2f8` for ground entities is absolute MSL (values match terrain) or gets re-clamped.
- Units of waypoint speed (km/h assumed); whether world units are exactly metres.
