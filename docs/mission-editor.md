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
- **Top bar:** New, Open, Fork, Duplicate (your own mission, §17), Save, Save as, Undo, Delete (your own mission,
  after a confirmation; originals have none), the mission's name, **Fly as** (Alpha … Delta) and Fly.
- **Map:** the TSD (`game/menu/tsd.gd`) in its edit mode. Its client (`tsd.area`) grows to the whole map pane, so
  the map fills it at any window size, 4K full screen included; the art and icons keep the size the original's frame
  would have there, and the farthest zoom still fills the pane (`tsd.min_zoom`). The mouse moves it: the wheel zooms
  about the point under the cursor (the + / − buttons at the top right zoom too), and a drag with the middle button,
  or with the left one from empty map when no tool is on, pans it; the editor draws no scrollbars. The right button
  is the TSD's ruler. It opens zoomed in on the blue units.
- **HiDPI:** on a Retina or other HiDPI screen the window's content grows by the screen's scale
  (`content_scale_factor`), and the window grows to hold 1600 × 1000 of those units as far as the work area allows,
  as the setup wizard's does.
- **Side panel**, four tabs:
  - **Units**, in the order of use: every entity of the main file, a target or a must-survive unit tagged and
    coloured; **Add a unit** right under the list (kind; object, shown by its game name then its own, e.g. "SA 6
    (sa6launcher)"; side, role and Place on one line); the selected unit's name, side, role, heading and altitude;
    Delete; mark the selected units Target / Must survive / Neutral; Give a route (§13); Copy and Paste (§17);
    Random: the chance to appear and the start spread, the roll preview (§15).
  - **Flights:** the what-if switch (§12.4) above the jet lists it widens; Alpha … Delta (type: the blue jets in
    service in the mission's year, number of jets; on its second line where it starts: "as placed" (a new flight: in
    the air at the map's centre) or a base blue holds that year, on its runway with a route that takes off; Add / Set,
    Remove); the route of any flight, blue or red: its waypoints
    with altitude (m) and planned arrival time (seconds after the start: the file's "speed" field, docs/ai.md §7.2),
    Insert a waypoint after, Delete the waypoint; **Waits parked at its base until a rule makes it take off** for a
    flight whose first waypoint is a take-off (§18.6); **Remove this enemy flight** for a flight other than Alpha …
    Delta (§12.5). **Add an enemy flight:** a red base, a red jet and 1 or 2 jets (§12.5).
  - **Mission:** the win and lose summary and the debrief headlines (§13), the year (§12), the start time, the wind,
    the weather (§3) and the briefing in English and Hebrew. A new year runs the checks again and refills the jet lists; a year on
    another TSD map moves the mission to that map (§12.1).
  - **Intel:** what the pilot sees before the flight: the units shown on the pilot's TSD, the intel preview and the
    briefing's links (§14).
  - **Scenario:** "when X then Y" rules built from blocks (§18).
- **Bottom:** what passes and fails the mission (§13), red when it can never pass; under it the errors and warnings,
  errors first, in red and yellow (the list shows only when it has any, as tall as its lines up to four). A
  line names its unit; the same finding on several units is one line with their count. A click on one selects its unit and centres
  the map on it.

## 2. Opening and saving

- **Original missions** are the menu missions of `missionlist.json` except 666 (0x29a, the Mission Creator's
  template) and 777 (multiplayer All-Out War), listed by their title (misc `0x44c`). They open
  read-only. The only action on them is **Fork**.
- **My missions** are the files in `user://missions/`. Only these can be edited.
- **Open** lists your missions, then the originals, under a search box (number or title); the dialog fits the
  window.
- **New** builds a mission from scratch. It asks for a name, a year (§12), a home base, a jet, whether Alpha has a
  wingman, and whether what-if aircraft are offered:
  - The year picks the original the mission is built on, so its TSD map and airbases (§12.1).
  - The home bases are the bases blue holds that year (§12.2); the jets are the blue jets in service that year
    (§12.3).
  - `IafMissionEdit.blank` empties the original: every unit and flight but Alpha, the paths, events, debrief texts and
    the briefing go. The debrief headlines become "Mission - successful." / "Mission - failed." and the pass / fail
  audio none (§13). `set_flight` then puts Alpha on the home base's start point with one waypoint 20 km ahead.
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
   "year": 1998, "what_if": true, "briefing": {"en": "…", "he": "…"}}
  ```

  Only the edited main file is saved. The base missions are read again from `assets/` when the mission opens and when
  it flies, except a flipped base (§12.5), which the file holds whole. The editor never writes under `assets/`.
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
- `bases`: the base missions by name; a base with its sides flipped is an object `{"name": "bmisrfdim_flipped",
  "data": {…}}` (§12.5). Without `bases`, the source's.
- `year`: the mission year (§12). Without it, the source's year (§12.6).
- `what_if`: true when never-served aircraft are allowed (§12.4). Without it, true for sources 200 and up.
- `briefing`: the English and the Hebrew text (plain text), both optional; `entries`, the briefing's links (§14.3).
- `files[0].data.scenery_release` and the scenery targets' entity fields: §19.
- `random`: the chance and start spread per entity id, `{"12": {"chance": 50, "spread_km": 2}}` (§15). The mission
  data never holds them.
- `files[0].data.misc.items[0].weather` (ours, formats/mis.md): the Mission tab's **Weather**, under Wind / From:
  - **Default (Graphics Rain)**: no field, as every original. The flight rains at the Graphics Rain level.
  - **Clear** `"clear"`, **Light rain** `"light"`, **Heavy rain** `"heavy"`: the mission's own weather. It wins over
    the Graphics Rain level, but Rain Off keeps every flight dry.
  - **Random** `"random"`: Clear, Light or Heavy rain, picked once per flight at the start, as wind's Random.
  - The full rules: rendering.md §10. The weather is drawn only: no effect on the flight, the AI or the brakes.

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
| `set_role(mission, ids, role)` | role 0 must survive, 1 target, 2 neutral on the units `ids` (§13) |
| `conditions(mission)` | what passes and fails the mission, with its summary (§13) |
| `set_red_flight(mission, spec)` | a red flight taking off from a base (§12.5) |
| `flip_base(base)` | a base mission with blue and red swapped (§12.5) |
| `years()`, `year_source(year)`, `default_year(source)` | the years; the original a year builds on; an original's year (§12) |
| `year_bases(year, side)`, `base_owner(stem, year)` | the bases a side holds; a base's owner (§12.2) |
| `year_jets(year, side, what_if)` | the jets a side has in service (§12.3) |
| `year_issues(mission, year, what_if)` | the year's warnings (§12.7) |
| `set_known(mission, ids, known)` | entity flag `0x35c` on the units `ids` (§14) |
| `intel_links(mission)` | the model links the mission's unit types can have (§14.3) |
| `roll(mission, random, seed)` | one roll of the random settings (§15) |
| `random_issues(mission, random)` | the randomness warnings (§15) |
| `year_map_source(source, year)` | the source for a new year: `source`, or the year's original on another map (§12.1) |
| `base_issues(bases, year)` | warnings for base missions whose side does not fit the year (§12.1) |
| `sanity(mission)` | the sanity check's warnings (§16) |
| `paste_group(mission, entities, dx, dy)` | copies of units moved by (dx, dy); returns `{"mission", "ids"}` (§17) |
| `remove_formation(mission, index)` | removes the formation at `index` of `formations.items` and its jets (§12.5) |
| `set_scenery(dir)`, `has_scenery()` | the scenery folder the editor reads; whether setup made the scenery (§19) |
| `scenery_at(x, y, r)`, `scenery_outlines(x0, y0, x1, y1, xf)` | the building at a point; the buildings' outlines in a box (§19) |
| `scenery_target(mission, template, x, y, r)` | Set as target on the building there; returns `{"mission", "id"}` (§19) |

### 5.1 Ids and references
- A new row takes the placeholder row's id, and the placeholder moves one up. Ids are never reused, so an old
  reference cannot point at a new row.
- `add_entity` clears what belongs to the template's own mission: its event slots, both script lists and its related
  entity (`0xac`). The new entity is brain-controlled (`0x320` bit 0 clear).
- `remove_entity` sets the formation members and targets that named the entity to -1, removes the event actions on
  it, and sets every `0xac` that pointed at it to -1. A Launch at target (trigger op 2) or Yaw to target (motion op
  11) at it becomes a Wait / Hover, which does nothing.

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
removes the scenario rules' jumps into it (§18) and removes a path that no unit follows any more. A new route for a
unit that a rule starts keeps waiting for the rule: Hover at entry 1, the Path at entry 2, the rule's jump moved to it.

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
  one; the list is in the list at the bottom.
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
     (`tsd.gd _text_of`). The override's `entries` are the briefing's links (§14.3).
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

**Win and lose check** (§13):
- error: the mission can never pass: no unit is a Target;
- warning: a red unit must survive (red sensors are left out: the originals use them as lose tokens).

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
| a red unit that must survive | 24 warnings |
| no target | 2 errors, not counted in the 10: 666 (the Mission Creator's template, its roles are set at run time) and 777 (multiplayer) |

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

- `tests/godot/test_mission_editor.gd`: New by year (1967 offers Tel Nof and Ramat David and the
  Mirage; 1973 adds Refidim; no Lavi without what-if), an enemy flight from Damascus, a flipped Refidim in 1967
  1967, the year and the bases kept by Save and Open, the Refidim warning in 1990; then Fork's name, the name rules, a drag moving an Alpha jet, an added SA-6 at the
  ground's height, Undo, an SA-6 in the sea as an error (red ring, Fly off), the Weather (a fork's Default, Heavy rain
  written to misc `weather`), Save and Open giving the same mission and weather, and the original file unchanged.
- `tests/godot/_mission_editor_shot.gd`: a real-render screenshot (usage in its header).
- `tests/godot/test_mission_edit_fly.gd`: Fly from an edited mission 115 (§8).
- `tests/godot/test_mission_edit_win.gd`: New can never pass; an SA-6 marked Target and a Merkava marked Must survive;
  flown through the runtime, the SA-6 destroyed passes it, the Merkava lost first fails it (§13).
- `cargo test -p iaf-tools --lib mission_edit`: names, edits and references, routes, the check and its calibration,
  the win and lose summary of 231, 311 and a New mission, Paste and removing an enemy flight.
- `tests/godot/test_mission_edit_intel.gd`: on a fork of 115, the TSD flag per unit and by the quick picks, the
  intel preview, the links, the random settings, Save and Open keeping them; Fly with a fixed seed gives the game
  the roll, and its TSD shows only the known units and the link, which opens the model window (§14, §15).
- `cargo test -p iaf-tools --lib mission_intel`: the TSD flag, the links of 115, a roll (chance 0 removes, 100 keeps,
  Alpha always appears, a spread unit within its radius on land at the ground's height, a flight moving as one with
  its route, the same seed giving the same roll), the targets that do not appear no longer counted.
- `cargo test -p iaf-tools --lib mission_sanity`: the fuel estimate, a too-long route, the calibration on the
  originals (§16).
- `tests/godot/test_mission_edit_clone.gd`: Duplicate, Copy / Paste (keys too), a fuel warning with its ring, a year
  on another map (1973, 1966, 1998) kept by Save / Open, Remove for an enemy flight.
- `tests/godot/test_mission_edit_red.gd`: two MiG-29s added at Damascus in a 1998 mission spawn as AI jets, take off
  and fly their route.
- `cargo test -p iaf-tools --lib mission_`: names, edits and references, routes, red flights, flipped bases, the
  check and its calibration; the year tables (`mission_year`); the scenario rules (`mission_events`, §18.5).
- `tests/godot/test_mission_edit_scenario.gd`: the Scenario tab (§18.5).
- `tests/godot/test_mission_edit_takeoff.gd`: a flight that takes off on a rule, and the originals' take-off times
  (§18.6).
- `tests/godot/_scenario_shot.gd`: real-render screenshots of the Scenario tab (usage in its header).
- `tests/godot/test_scenery_targets.gd` and `cargo test -p iaf-tools --lib mission_edit::tests::scenery`: scenery
  targets (§19).

## 12. Mission year

Every mission has a year from 1966 to 1998, set in a number box. 1998 is the game's present. 1967 is the Six-Day War
itself (5–10 June 1967), fought from the pre-war lines. The year decides:
- the original that New builds on, and so its TSD map (§12.1);
- the bases each side holds (§12.2);
- the aircraft and SAM / AAA each side has in service (§12.3);
- the year's warnings (§12.7);
- the night-vision goggles' tube when it flies (rendering.md §8.1).

Code: `crates/iaf-tools/src/mission_year.rs`, through `IafMissionEdit` (§5).

- **Values:** a whole year stands for mid-year (1973 is mid-1973); 1967 stands for the war's first day. The tables
  below use dates. A file saved with the earlier 1967.25 / 1967.75 opens as 1967.

### 12.1 The TSD map
The TSD draws one of three maps, chosen by the mission id (`tsd.gd setup`, front-end.md §8). Rendered from
`menu/emf/*.json`, the three maps show:

| Map | Missions | Borders drawn | Years in the editor | Source original |
|---|---|---|---|---|
| `67` | 110–119 | the 1949 Green Line round the West Bank and Gaza; the Sinai border; the Golan Syrian | 1966, 1967 | 111 Battle Against Time |
| `73` | 120–129 | no Green Line; no Sinai border, the line on the Suez Canal; the Golan inside Israel's line | 1968 to 1981 | 121 7 Columns of Fire |
| `82` | the rest | the Sinai border again; no Green Line; the Golan inside Israel's line | 1982 to 1998 | 231 License to Kill |

- The cut years follow the history: Israel took Sinai, the West Bank and the Golan on 5–10 June 1967[^sinai-occ]
  and completed its withdrawal from Sinai on 25 April 1982[^1982].
- The `73` map shows the lines of 1967–1973. It does not draw the 1974 and 1975 pull-backs in Sinai[^sinai2] or
  the 1980 interim line[^jta-1980]; the editor uses it up to 1981 (inferred: the closest of the three maps).
- The map follows the source's id.

**A new year on the Mission tab** (your own mission) that the table above puts on another map moves the mission
there (`year_map_source`):
- `source` becomes the year's original (111, 121 or 231), so the TSD draws its map, and Fly, Save and Open use the
  new id. A year on the same map keeps the source: a fork of 512 stays on 512 from 1982 to 1998.
- The units, flights, roles and briefing stay as they are.
- The base missions become the new original's, plus the ones the mission had before. An airbase of §12.2 that
  nobody holds in the new year leaves (Refidim from 1980, Ramon before 1982); a later year change that allows it
  brings it back, while the mission stays open. A base mission of yours (a flipped copy too) takes the place of the
  original's of the same base.
- Going back to the first map gives that map's original, not the one the mission was forked from: a fork of 512 set
  to 1973 and back to 1998 is on 231.
- The check warns of a base mission whose side is not the side holding it that year (`base_issues`): "Refidim: red
  holds it in 1966, but its base is blue". The editor does not flip it; an enemy flight from it does (§12.5). The 66
  originals at their own years have no such warning.

### 12.2 Airbases
The base missions' airbases, who holds them, and where a flight starts. A blue start is the Mission Creator's
(`mission_creator.rs` BASES; Refidim's is 121's Alpha). A red start is the base's lineup point and runway heading in
`iaf.ibx` (docs/ai.md §9), where the originals' red flights take off.

| Base (base mission) | Held by | Start (x, y, z, heading) |
|---|---|---|
| Tel Nof (`bmistlnf`) | blue throughout[^telnof] | 312984, 500459, 59, 90 |
| Ramat David (`bmisrdvd`) | blue throughout[^ramatdavid] | 356404, 602402, 28, 270 |
| Ramon (`bmisrmon`) | blue from 1982[^ramon] | 317439, 411135, 579, 230 |
| Refidim (`bmisrfdim`) | red to 5 June 1967; blue to 25 January 1980; then nobody[^gifgafa][^jta-1980][^treaty] | 153765, 373720, 98, 0 |
| Inshas (`bmisinsa`) | red throughout[^inshas] | −23742, 360968, −556, 270 |
| Damascus (`bmisdmsk`) | red throughout[^mezzeh] | 450815, 699907, 889, 240 |
| Al-Qusayr (`bmiskuzr`, "Kutzeir") | red throughout[^syaf] | 487086, 820615, 614, 280 |
| Bley (`bmisbley`) | red throughout (open) | 468942, 614520, 856, 235 |
| Rayak (`bmisryak`) | red throughout[^rayak] | 446008, 762295, 1200, 90 |
| Amman (`bmisamman`) | red throughout[^amman] | 430218, 505154, 924, 260 |

- **Refidim** (Bir Gifgafa) was Egyptian until the IDF took it on 7 June 1967 (the table uses 5 June, the war's
  start)[^gifgafa]. It was the first base Israel left after the peace treaty; JTA on 22 January 1980 reports its
  handover "at a ceremony Friday", so 25 January 1980[^jta-1980]. After that the treaty's zones allow no fighter base
  there: only unarmed transports in Zone B and civilian airfields[^treaty].
- **Ramon** was built from 1979 to 1982; squadrons moved in from Sinai from 1981[^ramon]. The table uses 1982.
- **Rayak** is a Lebanese Air Force base[^rayak]. The originals use it as a red base (237, 325); Syrian use of it is
  open. Red throughout is inferred from the originals.
- **Amman** (Marka) opened in 1950 as a joint military and civil airport[^amman]. It stays red after the 1994 peace
  treaty, as in the originals (516 The Reactor, set in 1998): inferred.
- **Bley** stands about 45 km south of Damascus, where a source lists a "Ble" military airfield[^ble]. Its opening
  year is open.
- `bmistlnf_red` (Tel Nof as red, for multiplayer 513) is not in the table.

### 12.3 Aircraft and SAM / AAA in service
Per bdb object (`default6_1.bdb`): the years each side has it. Red is any of Egypt, Syria, Jordan and Iraq; the data
does not tell the countries apart, so red has a type from the first year any of them had it. "—" means never in
1966–1998. A type not listed has no year check.

| Type (bdb ids) | Blue | Red |
|---|---|---|
| F-16 (1, 146, 177) | from July 1980[^f16-ops][^fas-iaf] | from March 1982 (Egypt)[^egaf] |
| F-15 (40, 147) | from December 1976[^f15] | —[^f15-wiki] |
| F-4 (48, 156, 179) | from September 1969[^f4] | from September 1979 (Egypt)[^acig-f4] |
| F-4 2000 (17) | from August 1987[^f4] | — |
| Mirage (47, 180) | to 1982[^mirage3][^acig-mirage] | from 1973 (Egypt, Libyan Mirages)[^egaf] |
| Kfir (99, 181) | from 1975[^kfir] | — |
| A-4 (144) | from December 1967[^a4] | — |
| Lavi (74) | never: a what-if (§12.4)[^lavi] | — |
| MiG-17 (44) | — | throughout (Egypt 1956)[^mig17] |
| MiG-21 (8) | — | throughout (Iraq 1962)[^mig21] |
| MiG-23 (11) | — | from April 1974 (Syria)[^mig23] |
| MiG-25 (33) | — | from March 1971 (Egypt, Soviet crews)[^mig25] |
| MiG-29 (2) | — | from 1987 (Iraq)[^fas-iraq] |
| Su-22 (45) | — | from 1973 (Iraq's Su-20)[^su17] |
| Su-24 (73) | — | from 1987 (Syria)[^su24] |
| Tu-22 (54) | — | 1973 to 1991 (Iraq)[^tu22] |
| Black Hawk (39) | from August 1994[^uh60] | — |
| CH-53 (53) | from October 1969[^ch53] | — |
| Mi-8 (43) | — | from 1967[^mi8] |
| Mi-24 (42) | — | from 1972[^mi24] |
| Il-76 (15, 131) | — | from 1974[^il76] |
| Hawk (30–32) | throughout (1965)[^hawk] | — |
| SA-3 (22, 23) | — | from March 1970 (Egypt)[^sa3] |
| SA-5 (19–21) | — | from January 1983 (Syria)[^sa5] |
| SA-6 (6, 13) | — | from 1973[^sa6] |
| SA-8 (75, labelled "SA 10") | — | from 1982 (Syria)[^sa8] |
| SA-13 (26) | — | from May 1976[^sa13] |
| ZSU-23-4 (50) | — | from 1968 (Egypt, Syria)[^zsu] |

- **Inferred:** the Mirage's end is the sale of the IAF's Mirages to Argentina, delivered from December
  1982[^acig-mirage]. The Tu-22's start: "during the 1970s"[^tu22]; 1973 is inferred, the exact year is open.
- **Inferred lower bounds:** the Mi-8, Mi-24, Il-76 and SA-13 years are their first Soviet service; an export is no
  earlier. Their first Arab years are open.
- **SA-6:** Egypt and Syria used it in October 1973[^sa6]; an earlier delivery is open.
- **Open, no year check:** SA-2 (Egypt had it by 1967[^sa2]), C-130 and Boeing 707 (the IAF's first years), the
  Kfir's IAF retirement ("the second half of the 1990s"[^kfir]), tanks and other vehicles.

### 12.4 What-if aircraft
A type that never served (the Lavi: first flight 31 December 1986, cancelled 30 August 1987[^lavi]) is offered only
with the **What-if (hypothetical) aircraft** switch, in New (above the jet list) and on the Flights tab. The switch is saved as
`"what_if"`. With it off, a Lavi in the mission gets the warning "Lavi: never in service (a what-if aircraft)".
Originals from 200 up (the game's own future, where the Lavi flies: 213, 513) open with the switch on.

### 12.5 Enemy flights
**Add an enemy flight** on the Flights tab adds a red flight that takes off from a base red holds in the year, with
a red jet in service that year, 1 or 2 jets (`set_red_flight`). It follows the originals' red flights:
- the formation number is 8, as for all 172 red flights of the originals ("Other"; the TSD's edit mode keys each by
  `100 + formation index`);
- the brains (`0x2da`) are 13 for the leader and 15 for the wingman, the commonest pair (55 red flights);
- the leader stands at the base's red start (§12.2), the wingman 50 m off its left; ground-start jets near the lineup
  roll straight out (docs/ai.md §8.2);
- the template is a red jet of that type from the originals; the pylons are left empty, so the type's own stores load;
- the route: take off to a point 10 km ahead on the runway heading (action 2), on 30 km further (action 3), back to
  the base to land (action 7). The originals' red take-off points are 10–11 km ahead too. A waypoint's "speed" is its
  planned arrival time in sim seconds (docs/ai.md §7.2): the take-off waits for wp0's 30 s; the others are timed at
  250 m/s.

The base's base mission is added to the mission's `"bases"`. When the data has that base for the other side (Refidim
in 1967 (the war's start) is Egyptian, its base mission blue), the editor writes a copy with blue and red swapped
(`flip_base`), named `<stem>_flipped`, into the custom file. Only the files under `user://` change.

The route is then edited as any flight's (§1). **Remove this enemy flight** on the Flights tab removes the flight
picked there with its jets (`remove_formation`); it is on for any flight other than Alpha … Delta.

### 12.6 The year of an original
A fork starts with its original's year, by the mission id (front-end.md §5.4, the campaign lists):

| Ids | Campaign | Year |
|---|---|---|
| 111–117 | Six-Day War | 1967 |
| 121–127 | Yom Kippur War | 1973 |
| 131–137 | Lebanon War | 1982 |
| 2xx, 3xx, 4xx, 5xx | the future campaigns, training, scramble, multiplayer | 1998 |

### 12.7 The year's warnings
After each edit, and when the year changes, the editor adds `year_issues` to the check (§9). They are warnings only:
- a blue or red unit outside its side's years in §12.3: "MiG-29 in 1973: not in red service then";
- a flight whose leader starts on the ground at a base (within 3 km of its start point and less than 300 m above it)
  that its side does not hold that year: "flight Alpha starts at Refidim in 1990: no fighter base".

Run over the originals at their own years, the warnings show the game's own liberties, for example:
- 111–117: CH-53, A-4, Il-76, Tu-22, ZSU-23-4 and Mi-24 in 1967;
- 126: MiG-29 and MiG-23 in 1973;
- the training missions: the Mirage in 1998;
- 512, 513, 666, 777: blue types on the red side.

[^sinai-occ]: Wikipedia, "Israeli occupation of the Sinai Peninsula": https://en.wikipedia.org/wiki/Israeli_occupation_of_the_Sinai_Peninsula
[^1982]: Wikipedia, "1982 in Israel", 25 April: "Israel completes its withdrawal from the Sinai Peninsula": https://en.wikipedia.org/wiki/1982_in_Israel
[^sinai2]: Wikipedia, "Sinai Interim Agreement" (4 September 1975): https://en.wikipedia.org/wiki/Sinai_Interim_Agreement
[^jta-1980]: JTA, "Israel moving to new Sinai line", 22 January 1980: "the Refidim military base and airfield, the largest in the Sinai, will be given back to the Egyptians at a ceremony Friday": https://www.jta.org/archive/israel-moving-to-new-sinai-line
[^telnof]: Wikipedia, "Tel Nof Airbase": RAF Aqir from 1941, an Israeli base from 17 August 1948: https://en.wikipedia.org/wiki/Tel_Nof_Airbase
[^ramatdavid]: Wikipedia, "Ramat David Airbase": an RAF field from 1942, Israeli from 1948: https://en.wikipedia.org/wiki/Ramat_David_Airbase
[^ramon]: Wikipedia, "Ramon Airbase": "built between 1979 and 1982": https://en.wikipedia.org/wiki/Ramon_Airbase
[^gifgafa]: Wikipedia, "Bir Gifgafa Airfield": "taken by the IDF's 84th Tal Division on June 7"; "the very first air base from which Israel withdrew": https://en.wikipedia.org/wiki/Bir_Gifgafa_Airfield
[^treaty]: Peace treaty between Israel and Egypt (1979), Annex I Art. III: Egyptian combat aircraft only over Zone A; unarmed transports in Zone B; only civilian airfields in the zones: https://jewishvirtuallibrary.org/peace-treaty-between-israel-and-egypt
[^inshas]: Wikipedia, "Inchas Air Base": "In 1954, the airfield was taken over by the Egyptian Air Force": https://en.wikipedia.org/wiki/Inchas_Air_Base
[^mezzeh]: Wikipedia, "Mezzeh Military Airport": a Syrian Air Force base after 1946, MiG-17 squadrons by 1957: https://en.wikipedia.org/wiki/Mezzeh_Military_Airport
[^syaf]: Wikipedia, "List of Syrian Air Force bases" (Al-Qusayr, 825 Squadron); the opening year is open: https://en.wikipedia.org/wiki/List_of_Syrian_Air_Force_bases
[^rayak]: Wikipedia, "Rayak Air Base": "the place where the Lebanese Air Force was born on June 1, 1949": https://en.wikipedia.org/wiki/Rayak_Air_Base
[^amman]: Wikipedia, "Amman Civil Airport": "founded in 1950 by the British as a joint military-civilian airport": https://en.wikipedia.org/wiki/Amman_Civil_Airport
[^ble]: Enab Baladi, "Eight military airfields around Damascus" (read from the search summary only): https://english.enabbaladi.net/archives/2025/11/eight-military-airfields-around-damascus-what-are-they/
[^f16-ops]: Wikipedia, "General Dynamics F-16 Fighting Falcon operators": Peace Marble I, deliveries 1979–1981; Jordan 1997: https://en.wikipedia.org/wiki/General_Dynamics_F-16_Fighting_Falcon_operators
[^fas-iaf]: FAS, "Israeli Air Force": the first F-16s "became operational in Israel in 1980": https://nuke.fas.org/guide/israel/agency/iaf.htm
[^egaf]: Wikipedia, "Egyptian Air Force": "In March 1982, Egypt received its first 12 F-16"; Libyan Mirages in the 1973 war: https://en.wikipedia.org/wiki/Egyptian_Air_Force
[^f15]: GlobalSecurity, "F-15 Baz": "the first Baz planes arrived in Israel on 10 December 1976": https://www.globalsecurity.org/military/world/israel/f-15.htm
[^f15-wiki]: Wikipedia, "McDonnell Douglas F-15 Eagle": Saudi Arabia is the only Arab operator: https://en.wikipedia.org/wiki/McDonnell_Douglas_F-15_Eagle
[^f4]: Wikipedia, "McDonnell Douglas F-4 Phantom II non-U.S. operators": first F-4Es accepted 5 September 1969; Kurnass 2000 "formally accepted on 11 August 1987": https://en.wikipedia.org/wiki/McDonnell_Douglas_F-4_Phantom_II_non-U.S._operators
[^acig-f4]: ACIG, Egyptian F-4Es: "first 18 arrived in September 1979": https://acig.org/artman/publish/article_361.shtml
[^mirage3]: Wikipedia, "Dassault Mirage III": the IAF's Mirage IIICJs delivered "between April 1962 and July 1964": https://en.wikipedia.org/wiki/Dassault_Mirage_III
[^acig-mirage]: ACIG, Argentina received "19 Mirage IIICJ and 3 Mirage IIIBJ … between 12/1982 and 02/1983": https://acig.org/artman/publish/article_274.shtml
[^kfir]: Wikipedia, "IAI Kfir": "The Kfir entered service with the IAF in 1975"; withdrawn "during the second half of the 1990s": https://en.wikipedia.org/wiki/IAI_Kfir
[^a4]: Wikipedia, "McDonnell Douglas A-4 Skyhawk": "The first deliveries took place in December 1967": https://en.wikipedia.org/wiki/McDonnell_Douglas_A-4_Skyhawk
[^lavi]: Wikipedia, "IAI Lavi": first flight 31 December 1986; cancelled on 30 August 1987: https://en.wikipedia.org/wiki/IAI_Lavi
[^mig17]: Wikipedia, "Mikoyan-Gurevich MiG-17": "The Egyptian Air Force received its first MiG-17s in 1956": https://en.wikipedia.org/wiki/Mikoyan-Gurevich_MiG-17
[^mig21]: Wikipedia, "Mikoyan-Gurevich MiG-21 operators": "Iraq received its first 16 MiG-21F-13s in 1962": https://en.wikipedia.org/wiki/Mikoyan-Gurevich_MiG-21_operators
[^mig23]: Wikipedia, "Mikoyan-Gurevich MiG-23": "The first MiG-23s were supplied to Syria in April 1974": https://en.wikipedia.org/wiki/Mikoyan-Gurevich_MiG-23
[^mig25]: Wikipedia, "Mikoyan-Gurevich MiG-25": MiG-25R / RB in Egypt from March 1971: https://en.wikipedia.org/wiki/Mikoyan-Gurevich_MiG-25
[^fas-iraq]: FAS, "Iraqi Air Force": "a squadron of 24 MiG-29s to Baghdad in early 1987": https://nuke.fas.org/guide/iraq/agency/af.htm
[^su17]: Wikipedia, "Sukhoi Su-17": "Su-20s Iraq acquired in 1973": https://en.wikipedia.org/wiki/Sukhoi_Su-17
[^su24]: Wikipedia, "Sukhoi Su-24": Syria, "20 Su-24MKs … starting in 1987": https://en.wikipedia.org/wiki/Sukhoi_Su-24
[^tu22]: Wikipedia, "Tupolev Tu-22": exported to Iraq "during the 1970s"; the rest destroyed in the 1991 Gulf War: https://en.wikipedia.org/wiki/Tupolev_Tu-22
[^uh60]: Wikipedia, "Sikorsky UH-60 Black Hawk": the IAF "received 10 surplus UH-60A Black Hawks … in August 1994": https://en.wikipedia.org/wiki/Sikorsky_UH-60_Black_Hawk
[^ch53]: Wikipedia, "Sikorsky CH-53 Sea Stallion": "On 2 October 1969, the first … were delivered to Israel": https://en.wikipedia.org/wiki/Sikorsky_CH-53_Sea_Stallion
[^mi8]: Wikipedia, "Mil Mi-8": Soviet service from 1967: https://en.wikipedia.org/wiki/Mil_Mi-8
[^mi24]: Wikipedia, "Mil Mi-24": Soviet service from 1972: https://en.wikipedia.org/wiki/Mil_Mi-24
[^il76]: Wikipedia, "Ilyushin Il-76": Soviet service from 1974; Iraq and Syria flew it: https://en.wikipedia.org/wiki/Ilyushin_Il-76
[^hawk]: Wikipedia, "MIM-23 Hawk": the first Hawk battalion deployed to Israel in 1965: https://en.wikipedia.org/wiki/MIM-23_Hawk
[^sa3]: Wikipedia, "S-125 Neva/Pechora": Soviet S-125 battalions in Egypt from March 1970: https://en.wikipedia.org/wiki/S-125_Neva/Pechora
[^sa5]: Wikipedia, "S-200 (missile)": "Starting in January 1983, Syria received supplies of S-200 missiles": https://en.wikipedia.org/wiki/S-200_(missile)
[^sa6]: Wikipedia, "2K12 Kub": the Egyptian and Syrian 2K12s in the 1973 war: https://en.wikipedia.org/wiki/2K12_Kub
[^sa8]: Wikipedia, "9K33 Osa": the Syrians deployed Osas in the 1982 Lebanon war: https://en.wikipedia.org/wiki/9K33_Osa
[^sa13]: Wikipedia, "9K35 Strela-10": Soviet service from 16 May 1976: https://en.wikipedia.org/wiki/9K35_Strela-10
[^zsu]: Wikipedia, "ZSU-23-4 Shilka": "1968–1970: War of Attrition (Egypt and Syria)": https://en.wikipedia.org/wiki/ZSU-23-4_Shilka
[^sa2]: techno-science.net, "S-75 Dvina": Israel captured S-75 batteries in 1967: https://www.techno-science.net/fr/definitions/s-75-dvina

## 13. Win and lose

### How the original decides
The roles alone decide a mission's end (mission-runtime.md §5). Each entity has a role (`0x32a`): 0 must survive,
1 target, 2 neutral. The role accounting `FUN_00599da0` runs when an entity is destroyed:

- **Passed:** the last target (role 1) is destroyed, and no must-survive unit was lost before. At mission start
  `FUN_00599980` counts the targets (`FUN_0059ac00`). The box "Mission Accomplished!" follows 10 s later.
- **Failed:** a must-survive unit (role 0) is destroyed. From then on the mission can no longer pass. The box
  "Mission failed." follows 10 s later.
- **Every player jet lost** (or the player ejected) ends the flight 5 s later, into the debrief.
- At the debrief (`FUN_0059a0f0`) the headline is misc `0x47e` when the mission passed, else misc `0x492`. A flight
  that ends with targets left is therefore failed.
- The engine has no time, landing or waypoint rule. Misc `0x4ce` (audio at the pass) and `0x4c4` (audio at the
  failure) are the only other misc fields used.

Events do not decide the end by themselves. In all 131 original files no event names a counter (`0x3de`), so the
conditions and counter actions never take effect (mission-runtime.md §3.1). Events reach the end only through the
roles: an event's Explode (trigger op 5) destroys a **sensor** (bdb object 130), and a role-1 sensor counts as a
destroyed target, a role-0 sensor as a lost must-survive unit.

**The 66 original missions** (missionlist.json without 666 and 777):

| what makes them pass | missions |
|---|---|
| units to destroy only | 46 |
| units to destroy and sensors the events explode | 10 |
| sensors the events explode only (the training, rescue and escort missions, e.g. 311 Takeoff) | 10 |
| no target | 0 |

- 44 missions have a must-survive unit other than a player jet; 17 have a must-survive sensor (a lose token).
- No base mission has a target or a must-survive unit.
- Every mission has a passed and a failed headline of its own.

### What the editor writes
Only the original's own data, so the runtime needs no change:

- **Role** (`0x32a`): the Units tab's Role, or Target / Must survive / Neutral for every unit selected in the list
  (`set_role`). "Select all units of this kind" selects every unit of the selected unit's bdb object.
- **Headlines:** misc `0x47e` (passed) and `0x492` (failed), on the Mission tab, in English.
- **New** (`blank`) removes the events, so only units can be targets; its headlines are "Mission - successful." and
  "Mission - failed.", and the original's pass / fail audio is cleared (`0x4ce`, `0x4c4` = -1).

### The summary
`conditions(mission)` counts the units the runtime spawns (unplaced, unused Player slots left out):

```json
{"targets": [{"id", "name", "kind"}], "scripted": [{"id", "name"}], "keep_alive": [{"id", "name"}],
 "can_pass": true, "passed_text": "…", "failed_text": "…",
 "summary": "Pass: destroy 2 targets (2 Tank) · Keep alive: HermonPost · Fail: a keep-alive unit is lost, or the flight ends first"}
```

- `kind` is the bdb object's name (`0x528`, else `0x514`); the summary groups the targets by kind.
- `scripted` are the role-1 sensors: "1 scripted goal the mission's events complete".
- The summary shows at the top of the Mission tab and on the line under the top bar.

## 14. Intel

What the pilot sees before the flight, through the game's own mechanisms; the runtime is unchanged.
Code: `crates/iaf-tools/src/mission_intel.rs`, through `IafMissionEdit` (§5); the editor's Intel tab.

### 14.1 Units on the pilot's TSD
- The pre-flight TSD shows a unit only when its entity flag `0x35c` ("known to the player") is set
  (front-end.md §8.1, the `+0x44` state of `FUN_004d2900`'s records). In flight a unit also becomes known when the
  player's radar records it (`FUN_004af300`).
- **Shown on the pilot's TSD** sets or clears the flag on the units selected in the Units list (`set_known`).
- **Show all / Hide all** do the same for every unit of a kind (all units, SAM / AAA, ground units, aircraft, ships)
  on a side (red, blue, any).
- Markers, sensors, ground radars and trees never show on the TSD, flag or not (front-end.md §8.1).
- In the original missions and base missions the flag is set on 1159 of 4646 units (about 1 in 4).

### 14.2 SAM rings
The TSD draws a SAM's range ring around each SAM record it has (`FUN_00504ea0`; tsd.gd `_draw_units`: class 8 with
the type codes 290 / 340, 300, 320). A record exists only for a known unit, so the rings follow the known SAMs: a
hidden SAM has no ring before the flight.

### 14.3 The briefing's links
The TSD's briefing links open the model, image, text and target windows (front-end.md §6, `FUN_00502cd0`; tsd.gd
`_on_link`). They are briefings.json `missions[id].entries`, `{file, title {en, he}, type}`.

- A fork keeps its original's links; New starts with none.
- **Add the link** offers a model link (type 2, the 3D-model window) for each unit type in the mission that has an
  info page (briefings.json `models`; the type's model from its bdb Present record `0x53c`). The title is the one the
  originals' briefings give that model most often, else the bdb object's name (`intel_links`).
- The titles in English and Hebrew can be edited; **Remove the link** drops one.
- The links are saved in the custom file's `briefing.entries`. Fly passes them in `Settings.briefing_override`, and
  the TSD's briefing (`tsd.gd _briefing`) lists them at the end of the text as "Intel: …" (Hebrew "מודיעין: …"),
  marked `[u]title[/u]` as the originals mark a link (`frame_window.gd _linkify`). A Hebrew briefing left empty shows
  the English text with the Hebrew titles.

### 14.4 Intel preview
**Intel preview** shows the map as the pilot will see it: the TSD out of its edit mode, so only the known units
show, and only the routes of Alpha..Delta. The map cannot be edited while it is on.

## 15. Randomness

Rolled by the editor at each Fly, so the game gets a normal mission; the runtime is unchanged.
Code: `mission_intel::roll` and `random_issues`, through `IafMissionEdit` (§5).

### 15.1 Settings
In the Units tab's Random group, for the units selected in the list:
- **Appears %**: the chance (0–100) the unit is in the flight.
- **Start spread km**: the unit starts at a random point within this distance of its place.

100 % and 0 km remove the setting. The settings live in the custom file's `random`, per entity id (§3).

### 15.2 The roll
`roll(mission, random, seed)` (seeded, so a seed repeats its roll):

- **Groups:** a flight (a formation's placed members) rolls as one, with the setting of its first member that has
  one; every other unit alone.
- **Chance:** a group that does not appear is removed (`remove_entity`: its formation slots, event actions and
  related entities lose it). Flights Alpha..Delta always appear, because the pilot flies one of them.
- **Spread:** the group moves by one offset, uniform in the disc of the spread. A flight's waypoints move with it.
  - Each new place must be inside the map. A vehicle, site or ship must also pass the ground check (§9) with no
    finding: a land unit on land, a ship on water, no steep slope, off the runway area.
  - A ground unit takes the ground's height there; an aircraft keeps its altitude.
  - After 64 samples without a fit the group keeps its place.
- A unit on a route (§5.2) joins its path from its new place, as the runtime joins a path from the closest point.

**Fly** saves the mission as edited, then gives the game one roll with a fresh seed. **Roll preview** shows one roll
on the map (the map cannot be edited while it shows); **Roll again** draws another.

### 15.3 Targets and the pass rule
A target that does not appear is removed from the flown mission, so the runtime never counts it
(`FUN_00599980` counts the targets at the start, §13): the mission passes when the targets that appeared are
destroyed. `random_issues` warns:
- for each target with a chance under 100 %: "a target that appears in N% of flights: when it does not, it is not
  needed to pass";
- when every target may be missing: "in P% of flights no target appears: the mission cannot pass then", P being the
  product of the targets' chances of not appearing.

A must-survive unit that does not appear cannot be lost, so it never fails the mission.

## 16. Sanity check

`sanity(mission)` (`crates/iaf-tools/src/mission_sanity.rs`) adds warnings to the check (§9) for a mission that flies
but may not play as meant. Each names its unit, so the unit gets a yellow ring on the map. They never block Fly.

| finding | text |
|---|---|
| a blue flight burns more than 80 % of its fuel on its route | "Alpha: about 120% of its fuel for this route" |
| a target that the SAM rings cover from every side | "SA 6 battery covers this target from every side" |
| an enemy flight without waypoints | "enemy flight MiG-29 has no waypoints" |
| a unit on a route (Path, §5.2) whose path is missing or has fewer than two points | "its route has no points: it stays where it is" |
| a flight that waits for a rule (§18.6) that no rule makes take off | "MiG-29 waits for a rule, but no rule makes it take off" |
| a target that no blue flight's loadout can destroy | "no blue flight carries an air-to-ground weapon for this SA 6" |

### 16.1 Fuel
For each blue flight Alpha … Delta, from its leader's data:
- **Fuel:** the flight model's `FuelWeight` plus the tanks of its loadout (one tank per station, its bdb weight; as
  `Aircraft::set_fuel_capacity`). The original data set; the Real set and the stores weight fix are left out.
- **Loadout:** the stores the leader spawns with (`stores::loadout`, `FUN_0058f110`): its own pylons, else its type's.
  A loadout changed on the Arming screen before the flight is not known to the editor.
- **Route:** from the leader's start through every waypoint, then back to the start, unless the last waypoint lands
  (action 7) or ends within 10 km of the start (inferred: an airborne start is the flight's way in).
- **Each leg:** level flight at the waypoint's altitude and its planned speed, the speed the AI flies a waypoint at
  (docs/ai.md §7.2, `FUN_005d6dc0`): the distance over the time to its arrival time, clamped to 180–300 m/s, or
  275 m/s without one.
- **Burn per metre:** the flight model's drag at 1 g (flight-model.md §4.3: the clean drag, the stores drag and the
  induced drag, the mass with half the fuel burnt), the throttle whose thrust (§4.1) equals it, that throttle's fuel
  flow (dry: ×`dry_fuel_frac`), divided by the speed. A drag beyond military thrust burns at afterburner.
- **Warning:** above 80 % of the fuel (inferred: the rest is for the take-off, the climb, the fight and a reserve).
  The text rounds the share to 5 %.

Not counted (inferred, covered by the margin): the take-off and climb, turns, combat, wind.

Example (the Rust test): an F-16 at 6 km and 275 m/s burns 1.7 kg/km clean. With its type's own stores at 3 km it
burns 9.9 kg/km: the original adds the stores' weight in pounds to the kilogram field (stores.rs
`init_weight_drag`), so the jet is heavy and needs afterburner.

### 16.2 SAM rings
- **Rings:** the red SAM sites of the main file whose type the TSD rings (`tsd.gd SAM_RING`): SA-2 and Hawk 37.1 km,
  SA-6 22.2 km, SA-3 16.7 km. A SAM that is itself a Target is meant to be attacked, so it is left out. The base
  missions' SAMs are left out too.
- **Covered from every side** (inferred): a ground target inside a ring, where every point 15 km from it, on 36
  bearings, is inside a ring too. A SAM within 5 km of the target is the target's own site's defence and counts for
  neither test. The warning names the nearest covering SAM.

### 16.3 Routes and weapons
- An enemy flight is a formation whose leader is red.
- **Weapons:** the stores of every jet of the blue flights Alpha … Delta, by the weapon category (`Category::of`,
  `FUN_004d72a0`). An aircraft target needs an air-to-air weapon or a gun; any other target an air-to-ground one
  (bombs, rockets, HARM, Maverick, TV and laser weapons). The gun does not count against ground targets (inferred:
  every jet has one). Sensors (scripted goals) are left out.

### 16.4 Calibration on the original missions
The Rust test `sanity_warns_and_originals_stay_clean` runs the check over the 66 original missions (missionlist.json
without 666 and 777) and fails when a count changes. 57 missions are clean; 16 warnings in 9 missions:

| finding | count | missions |
|---|---|---|
| fuel | 3 | 225 (Delta 90 %), 227 (Delta 85 %), 314 (Alpha 100 %) |
| covered from every side | 11 | 122 (2), 134 (6), 322, 511 (2) |
| a route without points | 2 | 215 (two units on a path with fewer than two points) |
| no weapon for a target | 0 | |

Before the tuning, with every SAM counted and the approach points 8 km out, 48 targets in 18 missions were "covered
from every side". Leaving out the target's own site (5 km) and testing 15 km out left 11.

## 17. Duplicate and Copy / Paste

- **Duplicate** (top bar) is for your own missions. It asks for a name, suggesting a free one ("Clone A 2" for
  "Clone A"), and saves a copy under it. You go on editing the mission you had open; Save as goes on with the copy
  instead. An original has no Duplicate: Fork it.
- **Copy** (Units tab, or Ctrl+C / Cmd+C) takes the units selected in the Units list, else the selected unit.
- **Paste** (or Ctrl+V / Cmd+V) waits for a click on the map, then places the copied units with their centre there
  (`paste_group`):
  - their layout and headings are kept;
  - each gets a new id (`add_entity`, §5.1);
  - a ground unit takes the terrain's height at its new place; an aircraft keeps its altitude;
  - side and role are kept;
  - **routes are not copied**: a pasted unit is brain-controlled with no motion list, no events and no related
    entity. A pasted aircraft is in no flight.
  - The pasted units become the list's selection, so Give a route or Target works on them at once.
- Copy works on an original too; Paste only into your own mission. The copied units stay until the next Copy, also
  across missions.

## 18. Scenario

The **Scenario** tab holds the mission's rules: "when X then Y". Each rule is one WHEN block and any number of THEN
blocks. The rules are written as the original's own event data (mission-runtime.md §2–§4), so the runtime runs them
with no change, as it runs the originals' events.

Code: `crates/iaf-tools/src/mission_events.rs` (`rules`, `set_rules`, `audio_list`, through `IafMissionEdit`), the
tab `game/editor/scenario_editor.gd`.

### 18.1 The tab
- At the top, the WHEN and THEN palettes. Drag a block onto a rule, or click it: a WHEN block makes a new rule (or
  replaces the highlighted rule's WHEN), a THEN block goes to the end of the highlighted rule.
- Under them, the rules in the mission's event order, each with its summary in plain English, for example "When
  SA6 is destroyed → Convoy starts its route". ↑ and ↓ move a rule, ✕ deletes it or one of its blocks.
- A unit is picked from a list of the mission's units by name, kind and side ("SA6 (SA 6, red)", a flight leader
  as "Alpha: …"), or with **Map** and then a click on the unit on the map. A message is picked by its subtitle.
- A rule that cannot be written yet (a unit still to pick, a slot another rule uses) stays on the tab as a new rule
  with what is missing ("To finish: …"); it is not in the mission until it can be written.
- An original's rule that does not fit the blocks is listed with the reason and kept as it is: it cannot be changed,
  moved into another form or deleted here.

### 18.2 WHEN blocks
| block | the original's data |
|---|---|
| Unit destroyed (one or more units, "or") | entity slot 1 (evDestroy) = the rule's event, on each unit (`FUN_004a6310`) |
| Unit badly hit | slot 0 (evHit): the unit goes from alive to fatally hit, state 1 → 3 (`FUN_004a6240`) |
| Comes within (a unit, a distance, a centre unit) | slot 5 (evReached), the watched unit `0xac`, the radius in slot 4's `0x348` (`FUN_004a6590`, checked every 4 s in 3-D, mission-runtime.md §2.2) |
| Moves away | slot 4 (evLeft): armed only after the unit came within the distance |
| Mission start | a holder sensor, mission-controlled: its trigger list starts at entry 1 with the flight (`FUN_004a61e0`) and fires the rule's event (op 6) |

**Where a distance check goes.** The runtime arms a reached / left check only on a mission-controlled entity, and
never on the player. The distance is symmetric, so:
- a centre that does not move (no route, not in a flight): a new **area sensor** (bdb object 130, mission-controlled)
  at the centre's position, watching the unit;
- else the unit, or the centre, when it is mission-controlled (a unit on a route), is not in flights Alpha..Delta
  and its slot is free (its other slot may hold a rule on the same unit and distance);
- else the rule cannot be written: two moving units of which neither is on a route (for example a MiG and Alpha).

The distance is 3-D: a jet at 5 km altitude is 8.7 km from a ground unit it passes over at "within 10 km".

### 18.3 THEN blocks
| block | the original's data |
|---|---|
| Radio message | the event's audio `0x3ac`: PlayMessage, the wav and its subtitle (`FUN_004bb10b`); a second message in the same moment is trigger op 7 in the holder's list |
| Wait | trigger op 15 Wait for that many seconds in the holder's list, then op 6 fires the event of the blocks after it (§18.4) |
| Flight takes off | ours: trigger op 40 on the flight's leader; the flight waits parked until then (§18.6) |
| Start its route | an action jumping the unit's motion list to its Path (the route from the Units tab); the route waits on a Hover at entry 1 until then, the originals' pattern ("Wait" / "hov", Path at 2) |
| Appear / Disappear | trigger op 13 / 14 (`FUN_00463f10` / `FUN_00463ec0`) in the unit's trigger list |
| Cannot be hurt / Can be hurt | op 11 / 12 (the damage object's shield flag) |
| May fight / Hold fire | op 21 / 22 (`FUN_00440830` / `FUN_004407e0`, docs/ai.md §6) |
| Fire at a unit (to kill, or a miss for show) | op 2 Launch at target, `0x8ac` the target, `0x852` 1 or 0 (`FUN_004aae40`) |
| Explode | op 5 (`FUN_004a8ae0`, damage level 5) |
| Goal done | op 5 on a new role-1 sensor: it counts as a destroyed target (§13, `FUN_00599da0`) |
| Mission fails | op 5 on a new role-0 sensor: a lost must-survive unit fails the mission |

Read back only: Launch at location (op 1), shown as "fires at a point".

Blocks at the same moment run together; the tab shows them in a fixed order (the message first).

### 18.4 How a rule is written
- **The event.** One event per rule (`CDMEEventItem`): its name, audio, executions (`0x398`, 1), debrief and text
  are kept from the original when it is rewritten; its actions `[unit, motion index, trigger index]` jump the units'
  lists (`FUN_004c35d6`).
- **A unit's blocks.** Appended to the unit's trigger list as one chain of entries of 0 s. A list that was empty
  first gets a Wait at entry 1 ("WAIT FOR RULE"), which ends the list at once: entry 1 runs with the flight on a
  mission-controlled unit, and a route makes a unit mission-controlled.
- **Waits.** The blocks after a wait need a later event. A **holder sensor** (brain-controlled, so its list waits
  for the jump) gets the chain Wait N → op 6 (fire the next event) → … ; the rule's event jumps it. Trigger op 6 is
  in the exe but in no original: its Execute `FUN_005c4340` fires the event at script +0x28, which the factory
  `FUN_004b8f09` fills as for op 7 Play message (`0x8ac`).
- **The editor's sensors** carry the label `0x316` "scenario rule", "scenario area" or "scenario goal" (the runtime
  never reads it). They stand at (-1, -1), as the originals' sensors do, except an area sensor, which stands at its
  centre. Their names: "Rule: …", "Area: near …", "Goal: …", "Lose: …".
- **Keeping the original.** `set_rules` rewrites only the rules that changed; an unchanged rule (same key, same
  blocks) and every rule not editable here keep their data byte for byte. A changed or deleted rule is taken out
  first: its event and later events, the slots that fired them, its script entries (the lists renumbered, every
  action and next link following), a route's Hover hold, and the sensors left with nothing to do.
- **Order.** The events follow the order of the rules on the tab.

### 18.5 Reading the originals
`rules` reads every event: the slots that fire it, then its audio and actions, then the trigger chains the actions
jump to (waits add up, op 6 follows to the next event). A rule is editable when it is one WHEN block, every entry is
a block, it uses no counter, and its entries belong to it alone (not to another rule, nor to a script that runs from
entry 1 at the start).

Over the 131 converted files: 1197 events, 754 editable. Rewritten in the editor's form, all 754 read back as the
same blocks; written back unchanged, every file stays byte-identical (Rust test `originals_round_trip`). Not
editable are, for example, events no slot fires (205 in the data), events fired by several kinds of slots, and
motion jumps other than to a Path (Hover, Yaw to target).

**Tests:** `cargo test -p iaf-tools --lib mission_events` (the round trip; New with three rules written, read back,
kept by a new route, all removed giving the mission back; references after `remove_entity`; a slot used twice);
`tests/godot/test_mission_edit_scenario.gd` builds on the tab, on a New mission, "when the SA-6 is destroyed → the
convoy starts its route" and "when Alpha comes within 10 km of the tank → play MiG's! MiG's! MiG's!", flies it
through the runtime, and checks that the message plays and that the convoy waits until the SA-6 is destroyed and
then drives. `cargo test -p iaf-tools --lib mission_events::tests::takeoff_rule_holds_and_releases` and
`tests/godot/test_mission_edit_takeoff.gd` test the take-off rule (§18.6).

### 18.6 A flight that takes off on a rule
**Flight takes off** (THEN) makes an AI flight wait parked at its base until the rule fires; then it takes off and
flies its route. Any flight whose first waypoint is a take-off (action 2) can wait: an enemy flight, or a blue flight
the player does not fly. A unit picked on the map stands for its flight.

**The original's own hold.** An AI flight's take-off already waits: TaxiCL keeps the brakes on until the take-off
waypoint's planned arrival time (wp0's "speed" field; `FUN_005d5cb0`, docs/ai.md §8.2). The leader rolls at that time,
the wingman follows it. The originals' enemy flights wait from 10 s to 1260 s this way.

**What the editor writes:**
- **The wait:** wp0's planned time becomes 1e7 s (116 days), so the original's own TaxiCL holds the jets parked. This
  is the Flights tab's **Waits parked at its base until a rule makes it take off**; the block sets it too. The
  waypoint list shows "waits for a rule" for that waypoint.
- **The release:** trigger op 40 "Take off" in the leader's trigger list, jumped by the rule's event as any other
  block. Op 40 is ours: the exe's trigger opcodes end at 28.
- A rule taken out, when no other rule makes the flight take off, gives wp0 back the time 30 s (the enemy flights'
  take-off time, §12.5). The sanity check warns of a flight that waits with no rule (§16).

**The runtime part** (ours, editor missions only): `mission_runtime.gd` runs op 40 only while
`Settings.mission_files_override` is set, which only the editor's Fly sets (§8). Then every jet of the flight gets
`ap_release_takeoff` (`Autopilot::release_takeoff`): wp0's time becomes now, and a TaxiCL already waiting is timed as
its FirstRun would time it then (the leader at once, a wingman away from the lineup 10 s later). Later waypoints keep
their times; a flight past them flies its legs at 275 m/s, as the original flies any late leg (docs/ai.md §7.2).

**Why this design** (inferred: the least runtime code that keeps the originals unchanged):
- The hold is the original's own data and code: no new state in the flight model or the brain.
- No original event can release it: Disable combat stops a brain only when it is engaged (docs/ai.md §6), and op 20
  (back to brain control) would need a mission-controlled jet that has no flight model in the port. So the release
  is one new opcode and one small function.
- The originals stay byte for byte as they were: none holds op 40 or a planned time of 1e7 s (Rust test
  `originals_round_trip`), and their take-offs follow wp0's time as before (`test_mission_edit_takeoff.gd`: 132's and
  114's AI leaders roll 2 s after their planned 20 s and 10 s, the brain's first tick).

**Tests:** `takeoff_rule_holds_and_releases` (a wingman picked becomes the leader, wp0 at 1e7 s, the rule read back,
taken out giving the mission back, the errors for a unit in no flight and a flight with no take-off);
`test_mission_edit_takeoff.gd` (a New mission with two MiG-29s at Damascus and "when Alpha comes within 30 km of the
tank → the MiG-29 flight takes off": the MiGs stay parked past their usual 30 s until the rule fires at 61 s, then
take off; then the originals above).

## 19. Scenery targets

With the scenery made by setup, buildings show on the map when zoomed in; a click on one offers **Set as target**,
and a unit placed on a building gets the warning "on a building: move to clear ground" with **Move to clear ground**.
A mission can set a building as a target but never remove one. Details: docs/scenery.md §5.
