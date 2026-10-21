# Mission editor

The mission editor is our own tool for making custom missions from the original ones. It is not part of the 1998
game: the original Mission Creator (front-end.md §19) stays as it was. The editor opens the converted mission files
(formats/mis.md), changes them, saves the result as your own mission, and flies it with **Fly**.

- **Start:** `./mission-editor` at the repo root. It runs `./iafjets` with `IAF_SCENE=res://editor/mission_editor.tscn`,
  so it builds and starts the same way as the game, on the editor's scene.
- **Code:**
  - the edits and checks: `crates/iaf-tools/src/mission_edit.rs`;
  - their Godot class: `IafMissionEdit` (`crates/iaf-godot/src/mission_edit.rs`);
  - the editor scene: `game/editor/mission_editor.tscn`;
  - Fly: `Settings.fly_edited` (`game/settings.gd`).

**Terms**
- **Original mission:** one of the converted files in `assets/converted/missions`. The editor never writes there.
- **Custom mission:** a fork of an original, saved under `user://missions/`.
- **Flight:** a formation (`formations.items`): two member slots and a waypoint route.
- **Placeholder row:** the last row of every part (`0x14` = 1, "Add data here"). Every edit keeps it last.

The editor scene calls `IafMissionEdit` through `game/editor/_edit_api.gd`.

## 1. The window

- **Start:** with no mission open, two choices stand where the map goes: **New mission** and **Open a mission**.
- **Top bar:** New, Open, Fork, Save, Save as, Undo, the mission's name, the issues, **Fly as** (Alpha … Delta) and Fly.
- **Map:** the TSD (`game/menu/tsd.gd`) in its edit mode, scaled to the window. The mouse wheel zooms; the
  scrollbars and arrow art are the TSD's own. The right button is the TSD's ruler.
  It opens zoomed in two TSD steps on the blue units. The editor hides a scrollbar when there is nothing to scroll
  that way (`tsd.gd bar_shown`); the original TSD always draws both.
- **HiDPI:** on a Retina or other HiDPI screen the window's content grows by the screen's scale
  (`content_scale_factor`), as the setup wizard's does.
- **Side panel**, three tabs:
  - **Units:** every entity of the main file; the selected unit's name, side, role, heading and altitude; Delete;
    Add a unit; Give a route.
  - **Flights:** Alpha … Delta (type, number of jets, Set, Remove), and the route of any flight, blue or red: its
    waypoints with altitude (m) and speed (km/h), Insert a waypoint after, Delete the waypoint.
  - **Mission:** the start time, the wind and the briefing in English and Hebrew.

## 2. Opening and saving

- **Original missions** are the menu missions of `missionlist.json` except 666 (0x29a, the Mission Creator's
  template) and 777 (multiplayer All-Out War), listed by their title (misc `0x44c`). They open
  read-only. The only action on them is **Fork**.
- **My missions** are the files in `user://missions/`. Only these can be edited.
- **New** builds a mission from scratch. It asks for a name, an era, a home base, a jet and whether Alpha has a
  wingman (`NEW_ERAS`, `NEW_BASES` in `mission_editor.gd`):

  | Era | Built on (map, airbases) | Home bases (blue) | Jets |
  |---|---|---|---|
  | 1998 (the game's present) | 231 License to Kill | Ramat David, Tel Nof, Ramon | F-16, F-15, F-4 2000, Kfir, Lavi |
  | 1973 | 121 7 Columns of Fire | Ramat David, Tel Nof, Refidim | F-4, Mirage |
  | 1967 | 111 Battle Against Time | Ramat David, Tel Nof | Mirage |

  - The bases and jets per era are inferred from history: Refidim in Sinai was an Israeli base from 1967 to 1982,
    so blue starts there only in 1973; Ramon opened in 1982.
  - `IafMissionEdit.blank` empties the original: every unit and flight but Alpha, the paths, events, debrief texts and
    the briefing go. `set_flight` then puts Alpha on the home base's start point (the Mission Creator's, Refidim's
    from 121's Alpha) with one waypoint 20 km ahead.
  - **No wingman** is allowed: Alpha flies alone, as the original Mission Creator's number 1 does.
  - The original's base missions (its airbases and their defences) stay, as for a fork, plus the home base's own
    when the original lacks it. The file keeps the list as `"bases"`; `source` is the original.
- **Fork** asks for a name and suggests a free one (`<title> 2`, `3` …). The fork is saved at once.
- **Names:** 1 to 40 English letters, digits, spaces, `_` or `-`, starting with a letter or digit. A name in Hebrew or
  another script is refused with the reason shown. Names compare without case:
  - a clash with an original mission's title is refused;
  - a clash with another of your missions asks Replace / Cancel.
- **The file** is `user://missions/<stem>.json` (the stem is the name in lower case, spaces as `_`):

  ```json
  {"source": 512, "name": "Wild West 2", "files": [{"name": "wild_west", "data": {…}}], "bases": ["bmisrmon", "bmistlnf"],
   "briefing": {"en": "…", "he": "…"}}
  ```

  Only the edited main file is saved. The base missions are read again from `source` when the mission opens and when
  it flies. The editor never writes under `assets/`.
- **Save as** saves a copy under the new name and goes on editing the copy.
- **Undo** steps back through up to 50 edits.

## 3. The custom mission file

`user://missions/<stem>.json`:

```json
{"source": 115, "name": "Close Support 2", "files": [{"name": "closesupport", "data": {…}}],
 "briefing": {"en": "…", "he": "…"}}
```

- `source`: the original mission's id (missionlist.json). Fly uses this id, so the bdb, the base missions, the
  debrief texts and the training rules are the source mission's.
- `name`: the mission's name, also written to `misc 0x44c`.
- `files`: the edited main file only. The base missions are read again from `source`.
- `briefing`: the English and the Hebrew text (plain text), both optional.

**Names** (`mission_edit::valid_name`, `stem`, `free_name`):
- Allowed: `^[A-Za-z0-9][A-Za-z0-9 _-]{0,39}$`, English letters only, because the name is also the file name.
- The stem is the name in lowercase with spaces as `_`.
- Names are compared without case (the Mac's file system ignores case). `free_name` gives the first free one of
  "name", "name 2", "name 3"…

## 4. Editing on the map

- **Units:** a click selects a unit (and its flight); a drag moves it. Every placed unit shows, also the ones the
  pre-flight TSD hides until they are known. Only the main file's units are edited; a base mission's unit returns to
  its place.
- **Ground height:** a ground unit that is placed or moved takes the terrain's height as its altitude (`0x2f8`).
- **Waypoints:** a drag moves a waypoint of the selected flight. Click a flight's unit, or pick the flight on the
  Flights tab, to select it.
- **Add a unit:** pick a kind (aircraft, SAM / AAA, vehicles, buildings, ships), the bdb object, its side and role,
  then press "Place on the map" and click. The new entity copies the fields of a placed entity of the same object (in
  this mission, else in an original mission).
- **Give a route:** select ground units or flyers in the Units list, press "Draw the route", click the points, then
  "Give the route" with a speed (km/h) and, when asked, a hover at the end.

## 5. Edits (`IafMissionEdit`)

Missions go in and come back as JSON strings. Positions are engine world metres: X east, Y north.

| func | what it does |
|---|---|
| `set_assets(path)` | the assets directory that `check` and `ground_height` read (call once) |
| `valid_name(name)` | "" when the name is allowed, else the reason in English |
| `stem(name)`, `free_name(base, taken)` | the file stem; a free name (see §3) |
| `add_entity(mission, template, fields)` | a copy of `template` (an entity of the wanted bdb type, from any mission) with `fields` on top; returns `{"mission", "id"}` |
| `remove_entity(mission, id)` | removes the entity and the references to it |
| `set_route(mission, ids, points, speed_kmh, hover_end)` | a ground or flyer route for the units `ids` (§5.2) |
| `clear_route(mission, id)` | takes the unit off its route |
| `set_flight(mission, number, spec)`, `remove_flight(mission, number)` | blue flight 1..4, Alpha..Delta (§5.3) |
| `ground_height(x, y)` | the terrain height, or null outside the terrain (§6) |
| `check(mission)` | the Fly and ground check as a JSON array of `{id, level, text}` (Checks and calibration) |
| `blank(mission)` | a mission from scratch: only flight 1 (Alpha) and its jets stay (New, §2) |

### 5.1 Ids and references
- A new row takes the placeholder row's id, and the placeholder moves one up. Ids are never reused, so an old
  reference cannot point at a new row.
- `add_entity` clears what belongs to the template's own mission: its event slots, both script lists and its related
  entity (`0xac`). The new entity is brain-controlled (`0x320` bit 0 clear).
- `remove_entity` sets the formation members and targets that named the entity to -1, removes the event actions on
  it, and sets every `0xac` that pointed at it to -1.

### 5.2 Routes for ground units and flyers
A route uses the original's own mechanism: motion op 16 Path (mission-runtime.md §4 "Path details").

1. `set_route` adds one `paths.items` entry with the points. z is 0 for a ground unit, which keeps to the terrain;
   for a flyer z is the height above the ground.
2. Each unit becomes mission-controlled (`0x320 |= 1`), so its scripts start with the mission
   (`mission_runtime.gd start()`).
3. Its motion list (`scripts0`) gets entry 1 = Path: `0x8ac` = the path id, `0x884` = -1 (the constant-speed
   variant, 604 of the originals' 713 Path entries).
4. The entry's duration is the unit's arc length along the path divided by the speed. The length is measured from
   the unit's closest point on the path, where the runtime joins it (`_path_from`, `FUN_0047eb90`).
5. With `hover_end`, entry 2 is Hover (op 1): the unit stops at the last point.

Several units can share one path. `clear_route` empties the unit's motion list, makes it brain-controlled again,
and removes a path that no unit follows any more.

### 5.3 Flights Alpha..Delta
`set_flight(mission, number, spec)`: `spec` is `{type, count, slot_x, slot_y, alt, heading, points?}`.

- `type`: the bdb object id (entity `0x2c6`). The TSD lets the player fly the types in `tsd.gd FLYABLE_TYPES`.
- `count`: 1 or 2. A formation has two member slots (formations, formats/mis.md).
- The leader stands at the slot. The wingman stands 50 m to its left, as the Mission Creator places a wingman
  (`FUN_0058eb40`).
- New members are named `Player<n>` and `Player<nn>`, the Mission Creator's slot names. They are copied from a blue
  aircraft of the mission, and their pylons are left empty, so they carry their type's own stores (`FUN_005951c0`).
- `points` (optional): `[[x, y, alt, speed(, action)]]`. A new flight without points gets one waypoint 20 km ahead.

## 6. Ground height
`ground_height` reads the level-6 height tiles (`assets/converted/terrain/theatre/L6/h_<i>_<j>.png`, `meta.json`)
as they are first needed. It interpolates them as `terrain.gd height_at` does, through the same code
(`iaf_avionics::heights`). The Fly test checks that the two agree within 1 m.

One height sample covers about 79 m (inferred from `meta.json`: 64 terrain units of 1.24 m).

## 7. Issues, Fly as and Fly

- After each edit the editor checks the mission. A unit with an error gets a red ring on the map, a warning a yellow
  one; the list is under the issues button beside Fly.
- An error turns Fly off. With only warnings, Fly asks "Fly anyway".
- **Fly as** lists Alpha … Delta; a flight is enabled by the TSD's own rule (`tsd.gd flight_enabled`: it exists, its
  leader's type is flyable, side 1).
- **Fly** saves the mission, then calls `Settings.fly_edited` with the source's id, the edited main file and the base
  files, the briefing, the chosen flight and the mission's file. The game's TSD opens on that mission with that
  flight selected. When the flight ends, the editor opens the same file again (`Settings.editor_file`).

## 8. How Fly runs
`Settings.fly_edited(id, files, briefing, flight, file)` flies the edited mission in the same window:

1. It sets `Settings.mission_files_override` (the whole file list, the main file first), `briefing_override`,
   `return_to_editor`, `editor_flight` and `editor_file`. These are run-time only and never saved to settings.cfg.
   It sets `mission_id` = the source id and `jet_id` = -1.
2. The front end opens on that mission's TSD with the chosen flight selected (`tsd.select_flight`).
   - `MissionRuntime.mission_files` returns the override for any id while it is set.
   - The TSD's briefing is the override as plain text, in the game's language, falling back to English
     (`tsd.gd _text_of`).
3. The TSD's own Fly starts the flight as usual.
4. Back from the flight, every debrief button goes back to the editor (`res://editor/mission_editor.tscn`), which
   reopens `editor_file`. So do the TSD's BACK and MAIN.
5. `Settings.back_to_editor` clears the override state.

The flight is not saved to the pilot's records: it is not the original mission.

Test: `tests/godot/test_mission_edit_fly.gd`. It edits mission 115: Bravo's leader is moved, three jeeps get a
route, and the briefing is new. It then checks the files, the TSD, the briefing in English and Hebrew, the player's
start, the jeeps' speed on their route, and the ground height.

## 9. Checks and calibration
`check` lists errors and warnings. Errors block Fly; with only warnings, Fly asks once.

**Fly check:**
- error: no blue flight 1..4 whose leader is a jet the player can fly;
- error: a flight 1..4 lists a member that does not exist (warning for flights 5 and up: they never spawn);
- error: a unit or a waypoint outside the map.

**Ground check**, for vehicles (bdb class 5, 6), sites (8–13: SAM, AAA, radars, buildings) and ships (15, 16), at
the unit and at each point of its route:

| finding | level |
|---|---|
| outside the terrain | error |
| a land unit on the sea | error; warning within 200 m of land |
| a land unit on inland water | warning |
| a ship on land | error; warning within 200 m of water |
| a vehicle, SAM or AAA on an airbase's runway area (the `RUNWAY` surface flag) | warning |
| a slope over 30° for a vehicle, over 15° for a site | warning |

- The surface comes from terraintype.dat (`iaf_formats::terrain_types`).
- The slope is measured from the height samples one sample east, west, north and south of the unit.
- All limits are inferred, and set so that the original missions mostly pass (Calibration, below).

### Calibration on the original missions
The check ran over all 131 converted mission files (the 68 missions in missionlist.json and their base missions).
The Rust test `check_finds_problems_and_calibration` repeats it and fails when the error count changes.

| finding | count |
|---|---|
| errors | 10 |
| a land unit on the sea | 8 errors, 12 warnings |
| a ship on land | 1 error, 8 warnings |
| outside the map | 1 error |
| on inland water | 69 warnings |
| on an airbase runway area | 76 warnings |
| a slope over the limit | 38 warnings |
| a member that does not exist (flights 5 and up) | 3 warnings |

The 10 errors are in the originals' data:
- 4 BMPs in "chaos" stand at X = -1, in the sea;
- one marker in "saychees" stands in the sea;
- in "against_all_odds", one boat and 3 harbour objects are at the harbour, where the surface map's coast is
  coarse;
- "battle against time" places Inshas' runway 03 outside the map.

Before the tuning:
- every unit on water was an error (89), and a ship on land was an error (9);
- every unit on an airbase surface was a warning (441), because the `RUNWAY` flag covers the whole airbase, with its
  buildings.

## 10. The TSD's edit mode

`tsd.gd` has these hooks for the editor. With them unset the TSD behaves as the original's.

| Hook | What it does |
|---|---|
| `files_override` | the files to show in place of `mission_files(mission_id)` |
| `reload(files)` | reads the files again, keeping the zoom, the scroll and the selected flight |
| `edit` | every placed unit shows; every flight's route is drawn; flights other than 1–4 are keyed `100 + formation index` |
| `issues` | unit key → `"error"` (red ring) or `"warning"` (yellow ring) |
| `unit_dragged(index)` | a unit was pressed (and maybe dragged) and released |
| `waypoint_dragged(flight, index)` | a waypoint of the selected flight was released |
| `map_clicked(map_pos)` | a press on the map away from units and waypoints |

Each flight record also carries `formation`, the index of its formation in the main file.

## 11. Tests

- `tests/godot/test_mission_editor.gd`: Fork's name, the name rules, a drag moving an Alpha jet, an added SA-6 at the
  ground's height, Undo, an SA-6 in the sea as an error (red ring, Fly off), Save and Open giving the same mission,
  and the original file unchanged.
- `tests/godot/_mission_editor_shot.gd`: a real-render screenshot (usage in its header).
- `tests/godot/test_mission_edit_fly.gd`: Fly from an edited mission 115 (§8).
- `cargo test -p iaf-tools --lib mission_edit`: names, edits and references, routes, the check and its calibration.
