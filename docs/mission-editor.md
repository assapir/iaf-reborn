# Mission editor

The mission editor is our own tool, not part of the original game. It opens a converted mission
(`assets/converted/missions/*.json`, [formats/mis.md](formats/mis.md)), edits it on the pre-flight TSD's map and
saves it as a mission of your own. Its **Fly** button starts the edited mission through the game's TSD. The original
Mission Creator ([front-end.md](front-end.md) §19) stays as it was.

The scene is `game/editor/mission_editor.tscn` (`mission_editor.gd`). The mission logic (new ids, routes, flights,
names and the checks) is the Rust `IafMissionEdit`; the editor calls it through `game/editor/_edit_api.gd`.

## 1. The window

- **Top bar:** Open, Fork, Save, Save as, Undo, the mission's name, the issues, **Fly as** (Alpha … Delta) and Fly.
- **Map:** the TSD (`game/menu/tsd.gd`) in its edit mode, scaled to the window. The mouse wheel zooms; the
  scrollbars and arrow art are the TSD's own. The right button is the TSD's ruler.
- **Side panel**, three tabs:
  - **Units:** every entity of the main file; the selected unit's name, side, role, heading and altitude; Delete;
    Add a unit; Give a route.
  - **Flights:** Alpha … Delta (type, number of jets, Set, Remove), and the route of any flight, blue or red: its
    waypoints with altitude (m) and speed (km/h), Insert a waypoint after, Delete the waypoint.
  - **Mission:** the start time, the wind and the briefing in English and Hebrew.

## 2. Opening and saving

- **Original missions** are the menu missions of `missionlist.json`, listed by their title (misc `0x44c`). They open
  read-only. The only action on them is **Fork**.
- **My missions** are the files in `user://missions/`. Only these can be edited.
- **Fork** asks for a name and suggests a free one (`<title> 2`, `3` …). The fork is saved at once.
- **Names:** 1 to 40 English letters, digits, spaces, `_` or `-`, starting with a letter or digit. A name in Hebrew or
  another script is refused with the reason shown. Names compare without case:
  - a clash with an original mission's title is refused;
  - a clash with another of your missions asks Replace / Cancel.
- **The file** is `user://missions/<stem>.json` (the stem is the name in lower case, spaces as `_`):

  ```json
  {"source": 512, "name": "Wild West 2", "files": [{"name": "wild_west", "data": {…}}], "briefing": {"en": "…", "he": "…"}}
  ```

  Only the edited main file is saved. The base missions are read again from `source` when the mission opens and when
  it flies. The editor never writes under `assets/`.
- **Save as** saves a copy under the new name and goes on editing the copy.
- **Undo** steps back through up to 50 edits.

## 3. Editing on the map

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

## 4. Issues and Fly

- After each edit the editor checks the mission. A unit with an error gets a red ring on the map, a warning a yellow
  one; the list is under the issues button beside Fly.
- An error turns Fly off. With only warnings, Fly asks "Fly anyway".
- **Fly as** lists Alpha … Delta; a flight is enabled by the TSD's own rule (`tsd.gd flight_enabled`: it exists, its
  leader's type is flyable, side 1).
- **Fly** saves the mission, then calls `Settings.fly_edited` with the source's id, the edited main file and the base
  files, the briefing, the chosen flight and the mission's file. The game's TSD opens on that mission with that
  flight selected. When the flight ends, the editor opens the same file again (`Settings.editor_file`).

## 5. The TSD's edit mode

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

## 6. Tests

- `tests/godot/test_mission_editor.gd`: Fork's name, the name rules, a drag moving an Alpha jet, an added SA-6 at the
  ground's height, Undo, an SA-6 in the sea as an error (red ring, Fly off), Save and Open giving the same mission,
  and the original file unchanged.
- `tests/godot/_mission_editor_shot.gd`: a real-render screenshot (usage in its header).
