# .mis — mission files (and the .bdb object database they reference)

Addresses are `IAFJets.exe` **v1.1** (the reference version); [v1.1.md](../v1.1.md) maps them to v1.0 and lists what the patch changed.

This page gives the exact byte layout of the 131 mission files and of the object database they share, plus what each
field means. Key facts:

- `resource/missions/*.mis` (131 files) are MFC `CArchive` dumps (MFC = Microsoft Foundation Classes) written by the
  original mission editor ("DME"; its classes are named `CDME…`).
- `crates/iaf-tools/src/mis.rs` parses every file end to end, and also parses `default6_1.bdb`. The layout below is
  therefore exact.
- Field *meanings* come from how the game uses each field and from value statistics over all 131 missions. A meaning
  that no code backs is marked **UNCERTAIN**. What the engine does with each field at run time is in
  [mission-runtime.md](../mission-runtime.md).
- Loaders: `FUN_0058bce0` reads the mission (the mission document's `Serialize`); `FUN_0058c640` reads the bdb.
- The `CRuntimeClass` table (one entry per class) lies at `0x66fbb8..0x66feb8`; every class has schema 0x0b.
- All integers are little-endian.

## 1. Primitives

The file is built from these five encodings.

| name | encoding |
|---|---|
| `CString` | u8 len; if 0xFF → u16 len; if 0xFFFF → u32 len; then the bytes (cp1252, no terminating NUL) |
| `Count` | `CArchive::ReadCount` (`0x5e6db3`): u16; if 0xFFFF → u32 |
| `Obj` | `CArchive::ReadObject` (`0x5e8905`): u16 tag. `0x0000` = NULL. `0xFFFF` = new class: u16 schema, u16 name len, name; then the object body. `0x8000\|i` = class already seen at map index *i*; then the object body. Any other `i` (< 0x7FFF) = back-reference to an object already loaded. **Map indexing:** index 0 = NULL; every new class *and* every new object takes the next index (class first). |
| `Field` (tagged) | u32 field id, u8 type char, value. `'S'` → CString (`FUN_00592cf0`); `'I'`/`'B'` → i32 (`FUN_00592de0`); `'F'` → f32 (`FUN_00592eb0`). Each reader checks the id and stops with an error on a mismatch, so the field order is fixed. |
| `Junk(n)` | n bytes of reserved space that the editor filled with *uninitialised memory* (stack pointers, `0xCDCDCDCD`). Skip these bytes; never interpret them. |

Many written fields are also uninitialised: they hold `-842150451` (= `0xCDCDCDCD`) or values that look like
pointers, such as `9696508`. Treat any value outside a sane range as "unset".

### Item base (`CDMEDataItem::Read`, `FUN_00592bf0`) — prefix of every `*Item`/`*Rule`/`CDMEScriptObj`
Every item starts with this base:
```
u32    len        byte count of the tagged fields (informational; not needed to parse)
Field  0x14 'B'   flag: 1 on the editor's trailing "Add data here" placeholder row (and on all script objs)  UNCERTAIN
Field  0x1e 'I'   id  — 1-based id, unique within its part; everything cross-references by this id
Junk(0x200)
```
After the base, each item has its own fields, followed by `Junk(0x200)` unless a section says otherwise.

Each `*Part` is a `CObArray` (`Serialize` `0x593120` → `CObArray::Serialize` `0x5df996`): a `Count`, then
`Count × Obj`. The **last item of every part is a placeholder named "Add data here"**; skip it.

## 2. File layout (`FUN_0058bce0`)
A mission file is a fixed header, the bdb file name, then seven parts in this order:
```
0x000  u32 magic   = 0x00068B3F
0x004  u32 version = 9 (128 files) or 8 (3 files)   → global DAT_00843bcc, gates optional fields
0x008  Junk(0x1FC)
0x204  CString bdb name   ("default6_1.bdb" in every file; loaded from the same directory, FUN_0058c330)
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

Each class below lists its tagged fields in read order: field id (fid), type (t) and meaning.

### CDMEMiscItem (`FUN_00595b80`) — item 1 is the mission header
| fid | t | meaning |
|---|---|---|
| 0x44c | S | mission title ("Engines ON") |
| 0x456 | S | free text / sub-title, sometimes the briefing number ("232") — UNCERTAIN |
| 0x460 | F | start time of day, seconds after midnight (28800 = 08:00); the time-of-day option overrides it (mission-runtime.md §5.3) |
| 0x46a | I | wind speed in kt (0, 10, 15, 20 …; a few missions store the pair swapped); the tower's wind (`FUN_00551320`, radio.md) |
| 0x474 | I | wind direction in degrees (0, 270, 180 …; inferred, no reader found) |
| 0x47e | S | debrief headline when passed |
| 0x488 | S | (always empty) |
| 0x492 | S | debrief headline when not passed |
| 0x49c | S | (empty) |
| 0x4a6 | S | unused in single player (default "Passed") |
| 0x4b0 | S | (empty) |
| 0x4ba | I | bdb Audio id, -1 none (23 = "GOOD WORK"); no reader found |
| 0x4c4 | I | bdb Audio id played at the role-0 failure, -1 none |
| 0x4ce | I | bdb Audio id played at success, -1 none |
| 0x4d8 | S | category / campaign label ("training", "Future/Lebanon") |
| 0x4e2 | I | unknown small int 0..7 — UNCERTAIN |
| 0x4ec | I | unknown small int 0..12 (players/flights?) — UNCERTAIN |

### CDMETimeVarsItem (`FUN_00595ff0`)
A named timer: `0x6a4 S` name ("Boats Reach Shore"), `0x6ae F` time in seconds.

### CDMEPathsItem (`FUN_00596320`, `Serialize` `0x5962f0`)
A named path that the script op `Path` (16) uses. Fields in order:

1. `0x5dc S` name.
2. `0x5e6 S` (empty).
3. `Junk(0x200)`.
4. A `CList` (`0x598ea0`): `Count` × 24-byte raw records `{i32 index, f32 x, f32 y, f32 alt, i32 0, i32 0}`.

### CDMEEntitiesItem (`FUN_00596c50`, 0xF8 bytes) — every unit, building, sensor and marker
In the table, "obj" is the offset in the loaded object. `[n]` is the dword index in the runtime spawn descriptor:
`FUN_00592210` + `FUN_0058f110` build that descriptor, and the spawner `FUN_004b7634` consumes it.

| fid | t | obj | meaning |
|---|---|---|---|
| 0x2bc | S | +0x0c | name ("Player1", "mig29_1"). The names `Player1..Player7` are the player slots (`s_Player` check in `FUN_0058f110`) |
| 0x2c6 | I | +0x14 | **type** = bdb *Objects* item id (1 = f16, 2 = mig29, 51 = civilhouse, 130 = sensor) → `[6]` |
| 0x2d0 | I | +0x18 | **side**: 1 = Israel/blue, 2 = enemy/red, 0/3 rare (neutral?) → `[12]` |
| 0x2da | I | +0x20 | **brain** = bdb *Brains* item id (AI behaviour), -1 = none/human → `[13]` (`FUN_0058e530` looks brains up by name) |
| 0x2e4 | I | +0x24 | **X** world position (east) → `[8]` as float |
| 0x2ee | I | +0x28 | **Y** world position (north) → `[9]` |
| 0x2f8 | I | +0x2c | **altitude** above mean sea level (MSL, ≈ m); ground units carry the terrain height (e.g. 63 on Ramat David's runway, 1293 on the Golan) → `[10]` |
| 0x302 | I | +0x30 | **heading**, compass degrees (0 = N, clockwise; RD runway 15 → 150) → `[11]`; same meaning as the engine's `*Yaw` defaults |
| 0x30c | I | +0xbc | unused (always junk/0) |
| 0x316 | S | +0xc0 | group label ("Alpha leader", "SA-6 North") — UNCERTAIN |
| 0x320 | I | +0xc4 | control mode, bit 0: 1 = mission-controlled (scripts run from the start), 0 = brain-controlled; `[7] = !(v&1)` (mission-runtime.md §1 "Control mode") |
| 0x32a | I | +0xc8 | **role** → `[14]`: 0 must survive, 1 target, 2 neutral (mission-runtime.md §1 "Role") |
| 0x35c | I | +0xf4 | 0/1 → `[0x43]`; set on the player and on key friendlies/targets — UNCERTAIN (mission-critical flag?) |

**Event slots.** Then come **7 event slots** (i = 0..6, at object +0x34+16i). Each slot holds:

- `0x334 S` event name (the editor's display copy; nothing reads it);
- `0x33e I` **event id**: the CDMEEventItem id it fires, 0 = none;
- `0x348 I` parameter;
- `0x352 I` (junk);
- `Junk(0x200)`.

| slot | runtime meaning (mission-runtime.md §2) |
|---|---|
| 0 | fires when the entity is damaged |
| 1 | fires when the entity is destroyed |
| 2 | **a debrief id**, shown at the end of the flight if the entity is not destroyed (the editor stores event names here) |
| 3 | no reader found (3 uses, all named "…Combat") |
| 4 | fires when the watched entity leaves the radius `0x348` (70…10000) |
| 5 | fires when the watched entity comes within that radius |
| 6 | unused (junk) |

**Trailing fields.** Then come these reads, all version-gated in `FUN_00596c50`:
```
Obj CObArray  scripts0   (+0xe0) of CDMEScriptObj
Obj CObArray  scripts1   (+0xe4) of CDMEScriptObj  (runs from mission start on markers/sensors)
Obj CArmament armament   (+0xe8)
9 bytes skipped (a Field whose value is ignored)
if scripts0 non-empty && version>=4: Field 0x8b6 I → +0xec   else 9 bytes skipped
if scripts1 non-empty && version>=4: Field 0x8b6 I → +0xf0   else 9 bytes skipped
if version>=8: i32 → +0xac, Junk(0x1e1)   else Junk(0x1e5)
```
- `+0xec/+0xf0` look like editor counters (UNCERTAIN).
- `+0xac` = the id of a *related entity*, -1 none. It is the target or watched unit: for a sensor, the flight it
  detects; for a ground unit, what it engages.

**CArmament** (`Serialize` `0x5951a0`) is raw 0x60 bytes: 12 stations × `{u32 bdb Weapons id, u32 count}`. Only the
low byte of count is used (`FUN_005951f0`).

- Stations 0–8 are pylons; stations 9–11 are gun/chaff/flare.
- At spawn, stations 9–11 always come from the object type's template (`FUN_00595220`).
- Stations 0–8 come from the entity when any of its stations is set (`FUN_005951c0`), else from the type.
- Example, takeoff.mis Player1: pylons empty, `25 × 200` (20 mm), `33 × 60` (chaff), `34 × 60` (flare).

### CDMEScriptObj (`FUN_00596610`) — per-entity behaviour scripts (linked list by index)
| fid | t | meaning |
|---|---|---|
| 0x834 | S | name |
| 0x83e | I | **opcode** (see below) |
| 0x848 | S | string argument (audio name, path name, entity name) |
| 0x852,0x85c,0x866,0x870 | F | numeric args (Path: 0x852 ≥ 0 runs toward the last point; Launch at location: y / z in 0x852 / 0x85c, x in 0x848) |
| 0x87a | I | **duration** in seconds: every entry holds its list this long (Wait 15) |
| 0x884 | I | motion list: a TimeVar added to the duration when ≥ 1; Path: −1 selects the constant-speed variant |
| 0x88e | S | name of the next script ("N.A" = none) |
| 0x898 | I | index of the next script (matches the next script's *index* below), -1 = stop |
| 0x8a2 | S | opcode name (repeats 0x83e) |
| 0x8ac | I | resolved id of the string argument (bdb Audio id for Play message, Paths id for Path), -1 |

After the fields: 4 bytes skipped, `i32 index` (+0x10, the 1-based position within its list), `Junk(0x1f8)`.

The two lists have separate opcode spaces (mission-runtime.md §4). Opcodes in the data:

- motion list (`scripts0`): 1 Hover, 5 Turn, 11 Yaw to target, 16 Path (follow a CDMEPathsItem);
- trigger list (`scripts1`): 1 Launch at location, 2 Launch at target, 5 Explode, 7 Play message, 11 / 12 Shield
  on / off, 13 / 14 Visible on / off, 15 Wait, 19 Destroy entity (a no-op), 21 / 22 Enable / Disable combat.

### CDMEFormationItem (`FUN_005974f0`, `Serialize` `0x5974a0`) — flights and their routes
```
0x3e8 S name ("Alpha", "Mig 29")   0x3f2 I flight number (1 Alpha … 10 India, −1 → 8; front-end.md "Flights")
0x3fc I, 0x406 I  unused (junk)   Junk(0x200)
2 × { 0x410 S member name, 0x41a I member entity id (-1 none), 0x424 I target entity id (-1 none), Junk(0x200) }
CList waypoints (0x598ea0): Count × 24 bytes {i32 id, f32 x, f32 y, f32 alt, f32 speed, i32 action}
if version>=9: CList names (0x598fe0): Count × {u32 waypoint id, CString name} ("Departure", "Target", "Home")
```
- Waypoints are stored in route order; their ids are labels.
- Speed values run 60…1800, probably km/h (UNCERTAIN).
- `action` is 0..8 (3 most common): the waypoint type, UNCERTAIN.

### CDMEDebriefItem (`FUN_005978d0`)
Fields: `0x258 S` name, `0x262 I` 0/1 (which half of the debrief text it joins: 0 first, 1 second), `0x26c S` text.

### CDMEEventItem (`FUN_00597c70`, `Serialize` `0x597c40`) — triggers
```
0x384 S name   0x38e I debrief id shown when it fires (-1 none)   0x398 I maximum fire count (1 mostly)
0x3a2 S subtitle text   0x3ac I bdb Audio id to play (-1 none)   Junk(0x200)
3 × condition { 0x3b6 S variable ("", "COUNT", "NUMOFLAUNCHERS"), 0x3c0 S operator ("==", "++", ">="): both
                editor-only; 0x3ca I value, 0x3d4 I operator code, [version>5: 0x3de I counter id, Junk(0x1f7)]
                else Junk(0x200) }
CList actions (0x599110): Count × {i32 entity id, i32 script index in scripts0 (-1), i32 script index in scripts1 (-1)}
```
When an event fires, it:

1. plays its audio and text;
2. shows its debrief;
3. (re)starts the listed scripts on the listed entities. Read this way, 829 of the 892 action records resolve to
   existing script indices.

The mission ends through the entities' roles (`0x32a`): mission-runtime.md §5.

## 4. The .bdb object database (`FUN_0058c640`)
The bdb starts with `u32 magic 0x0004D769`, then 6 `Obj` parts. It has *no* version of its own: the reader uses the
version of the loaded .mis. The parts, in order:

| part | count | fields |
|---|---|---|
| Present | 221 3D models | `0x640 S` name, `0x64a S` model path `CONTROLLABLEPLANES\MIG29\MIG29_H.XFR`, `0x654 I`, `[v>=5] 0x65e F` model scale ([world-scale.md](../world-scale.md)), Junk(0x1ee\|0x1f7) |
| Weapons | 62 | `0x708 S` name "AA-10", `0x712 S` class, … 14 fields `0x708..0x78a` |
| Actions | 38 AI manoeuvres | `0x64..0xc8` |
| Audio | 496 | `0x12c S` name, `0x136 S` wav file, `0x140 S` subtitle |
| Brains | 67 | `0x1f4 S` name, `0x1fe S`, `0x208 I`, u32 0x212, `Obj CObList` rules, u32 0x21c, `Obj CObList` rules; `CDMEBrainRule` `0x190..0x1ae` + two CLists of 16- and 20-byte records, `Serialize` `0x594a90` |
| Objects | 182 unit types | `0x514 S` name "f16", `0x51e S` category "Controlled aircraft", `0x528 S` display "F16", `0x532 S` default brain, 18 ints `0x53c..0x5d7`, Junk, u32, `Obj CArmament` default loadout, u32, `Obj CObArray` of `CDMEWeaponLoadItem` (`FUN_00597f80`), Junk |

Cross-references:

- An entity's `type` is an Objects id.
- Objects `0x53c` is a Present id (the model).
- Objects `0x58c` = 1 means the unit has a collider (docs/damage.md §7).

Full parser: `mis.rs` `parse_bdb`.

## 5. Coordinates

Mission X/Y/alt are **engine world units**: metres (the ground is real size within 1 %, [georef.md](../georef.md)), X east, Y
**north**, alt above MSL. The engine's hard-coded
airbase spawn points (`FUN_0058ed60`, registry `BlueTeam\*`) use the same units:

| base | X | Y | Z | yaw |
|---|---|---|---|---|
| Tel Nof | 312984 | 500459 | 59 | 90 |
| Ramat David | 356404 | 602402 | 28 | 270 |
| Ramon | 317439 | 411135 | 579 | 230 |

The terrain (map.ptt) uses its own units. The terrain object's transforms convert between the two: `0x4053f0` maps
world → terrain and `0x405460` is the inverse (object `0x7793c0`, set up by `FUN_004056b0`/`FUN_00402740`):
```
tx = (X - DataXShiftPR) / PlaneScalePR      DataXShiftPR = -166850, PlaneScalePR = 1.2411389
ty = (DataYShiftPR - Y) / PlaneScalePR      DataYShiftPR = 1043780   (ty grows southward = ptt row order)
X  = tx * PlaneScalePR + DataXShiftPR ;  Y = DataYShiftPR - ty * PlaneScalePR
```
Check: the three bases map to (386608, 437760), (421592, 355623) and (390197, 509729). Each lies inside a level-0
airbase inset of map.ptt (records 31–33, 28–30, 25–27).

Heights: mission altitudes are metres above MSL. map.ptt's raw elevation converts to metres as in
[ptt.md](ptt.md) "Tile data"; Ramat David's runway is 63.7 m there and 63 in takeoff.mis.

### Worked example — takeoff.mis ("Engines ON", training mission 311, `brief/txt/311.brl` → "takeoff")
**Player.** Entity 1 `Player1`: type 1 (f16), side 1, brain -1, X = 356226, Y = 600689, alt 63, heading 150,
armament gun 200 / chaff 60 / flares 60. Slot 1 (destroyed) → event 5 "Player dead" → debrief 1
"The first rule of success in every mission - STAY ALIVE.".

**Where that is.** The terrain position is `tx = 523076 / 1.2411389 = 421448.4`,
`ty = 443091 / 1.2411389 = 357003.6`. This lies inside inset records 28–30 (x 416768–428032, y 352256–360448) =
**Ramat David AB** (airbase), 1.7 km from its default spawn point: level-0 tile column 36, row 37, pixel (72, 12).
Heading 150° = runway 15.

**Other entities:**

- `Player2..7` (types 40 F15, 17 f4, 74 Lavi, 48, 47 mirage, 99 CFIR) with X = Y = -1: unused slots for the other
  aircraft choices — UNCERTAIN.
- Three invisible `civilhouse` audio markers along the runway (proximity radii 70/85/500 m). They fire events 1–4:
  instructor audio Eagle1–4, bdb audio 211–214.
- A `sensor` "Win sensor". Its scripts1 chain runs Wait → Play message "GOOD WORK" (audio 23) → Explode; events 3/4
  start it via the action `(6, -1, 2)`. The whole chain at run time: mission-runtime.md §7.

**Header and formation.** Start time 08:00. Formation "Alpha" = member "player" (entity 1), with one waypoint
"Departure" (347870, 602383, 1000, 900, action 3).

Note: single missions use the file's positions. In campaign/multiplayer modes the game replaces the `PlayerN`
positions with the airbase spawn table above, adding +1666/+3333/+5000 to the altitude depending on an options field
(`FUN_0058f110`).

## 6. Open questions

[mission-runtime.md](../mission-runtime.md) decodes the runtime and takes precedence over this page. Still open:

- misc `0x456`, `0x4e2`, `0x4ec`; the slot 3 reader;
- the script float args of the unused opcodes; the waypoint `action`;
- the unit of waypoint speed (km/h assumed).
