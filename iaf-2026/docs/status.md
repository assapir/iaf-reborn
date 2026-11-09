# Modern IAF: status

What works and what is open, by work item ([plan.md](plan.md)). Newest first.

## Works
- **[D3](plan.md#d3-f-15c-baz-at-tel-nof), the F-15C Baz's data and Tel Nof (2026-11-09):** the Baz's unit record
  (`data/db/units/f15c.json`) compiles into the sim's bdb, and Tel Nof (LLEK, from OpenStreetMap and OurAirports) is
  the fifth base `iaf-sim airbases` compiles, with a Baz parking spot and a paved taxi path to 33L
  ([airbases.md](airbases.md)). `sim::tests::every_data_file_compiles_and_loads`,
  `sim_bases::tests::the_departure_is_paved`.
- **Compact JSON (2026-11-09, [plan.md](plan.md#rules-the-user-3-november-2026) rules):** every JSON file the
  sim writes is on one line ([data-formats.md](data-formats.md) §7).
- **The core sounds against real references (2026-11-09, Approvals A12, branch `wt/iaf-2026-core-sound`):** the
  dry engine plays its idle recording at its own pitch at idle (it was 4.2 semitones up) and rises to 1.3 and 6 dB at
  military; the start plays a JFS whine (its partials measured on an F-16 start), the engine's pitch and level by its
  RPM, a light-off thump and the JFS winding down at the generators; the gun buzzes at 100 rounds a second (it was
  48); the wind follows the dynamic pressure; the canopy closes at its checklist step; the touchdown is an airplane
  tyre skid with a thump, not a bicycle squeal ([sound.md](sound.md) §1.3–§1.8). The original game keeps its rules.
  `test_mvp.gd`, the original's `test_sounds.gd`.
- **The afterburner sounds like an F-16's (2026-11-09, the Mac play test's finding 27):** measured against an F-16
  hush-house run and take-offs, the burner now rises over 1.5 s with a low thump at light-off, dies away over 1.3 s
  at the cut, sits 6 dB over the dry engine, and is a real RNLAF F-16's roar with no pulse and no pitch shift
  ([sound.md](sound.md) §1.2). The original game keeps its rule. `test_mvp.gd`, the original's `test_sounds.gd`.
- **[B3](plan.md#b3-scenery-roads-and-inland-water), the sea and the shore's ground (2026-11-08):** the sea is one
  surface: Sentinel-2's from the beach out, with no Survey photo (its white no-data patch, its lighter blocks) beyond
  the coastline, and the open sea's fill in the composite's own tone, so its edge no longer shows as steps
  ([terrain.md](terrain.md) §3, §12). Near the camera the ground keeps the close up's grain and relief without its
  colour patches, which had speckled the pale desert orange ([terrain.md](terrain.md) §13). Pictures before and after
  in [scenery.md](scenery.md) §7. `sim_terrain::tests::the_shore_follows_the_coastline`.
- **[B2b](plan.md#b2-the-airbases) / [B3](plan.md#b3-scenery-roads-and-inland-water), the bases' ground and the shore (2026-11-08):** the taxiways and aprons
  are paved for the flight model (no rough-ground crash taxiing out), taxiway signs at the holding points and
  junctions ([airbases.md](airbases.md) §9), the sea follows OpenStreetMap's coastline in the photo and the surface
  flags ([terrain.md](terrain.md) §12), the airbases step downloads the extracts its water needs, and the wizard has
  an optional scenery step ([setup.md](setup.md) §3).
- **The gun (2026-11-08, the Mac play test):** the rounds are the unit record's (Sufa and Barak 511, F-35I 180) and
  run out; our own muzzle flash and tracers; every flight starts with the master arm safe, Shift+A arms
  ([weapons.md](weapons.md)). `test_sim_gun.gd`.
- **The Mac play test's findings (2026-11-08, [plan.md](plan.md#f-the-probe) F):** the mission card, the radio lines
  in the sim's band wholly in the game's language, the key hint; the pause menu centred at any size in Hebrew;
  Preferences as sections on their own screens with no aid or realism row and the aids off; Home on every start;
  clickable breadcrumbs ([front-end.md](front-end.md) §1, §8). `test_flight_ui.gd`, `test_front_end.gd`.
- **Keys and Joystick (P1, 2026-11-08, the Mac run's "keys / joystick mapping"):** Preferences → Devices opens a
  Keys screen (every command the sim has, by group; click and press to rebind, Cmd on macOS, conflicts with Swap /
  Use it here, Default, Reset all) and a Joystick screen (the devices, each axis' role with a live bar, Invert and a
  dead zone, the buttons and hat bound by pressing them, Reset all), in English and Hebrew. One compact store,
  `user://devices.json`, read, written and merged by Rust (`IafDevices`); the flight reads the merged key table and
  the axes. The Thrustmaster Hotas X has its own default map (`iaf-2026/data/devices/`), and a joystick connecting no
  longer asks for the install's `menu/joy` ([front-end.md](front-end.md) §9). On macOS the keys start from the
  laptop map, no numpad: the rudder on Z / X, the snap views on Alt + 1–9 (§9.1). `test_devices.gd`, the M0 probe
  with a fake joystick.
- **The HUD's light (2026-11-09, Approvals A10):** the F-16s' HUD in the P43 green, added to the scene's light,
  bright by day and dimmed to a night floor as the sun sets, with a faint halo, a 0.08° stroke and the combiner glass
  at 14 %; Preferences → Graphics "HUD brightness" sets the day level and Shift + H steps it
  ([cockpit.md](cockpit.md) §5.1). `test_hud.gd`, `test_mvp.gd`. Open: the glass's edge line (an `f16.glb` rebuild).
- **The cockpit holds still (2026-11-09, the Mac play test's finding 25):** far from the flight's start the whole
  cockpit jumped against the eye (32-bit floats: 3.1 mm steps 30 km out, 4.4 mm at 60 km). The sim draws the cockpit
  in its own world about the origin and lays it over the flight's view ([cockpit.md](cockpit.md) §6.2): it no longer
  moves against the eye at any distance; about +4 to +5 ms GPU a frame on the Iris Xe. `test_sim_look.gd`.
- **The ILS bars glide (2026-11-09, the Mac play test's finding 24):** the HUD's ILS lines sit at the exact
  deviation instead of the original's whole-pixel steps, which jumped about 5.5 screen pixels at a time on the 3D
  HUD glass ([real-hud.md](../../docs/real-hud.md#what-ours-draws-status)). `test_mvp.gd` checks all three jets.
- **The F-16s' loadout (2026-11-08, the Mac play test):** the Sufa and the Barak fly with an AIM-9M on the wingtip
  rails and on stations 2 / 8 and 3 / 7 and a 370 US gal tank on each inboard pylon, so the look back shows the stores
  instead of a bare rail and pylons ([data-formats.md](data-formats.md) §3). The Python and AIM-120 records (the
  AIM-9M stands in) and the tank's drag are open.
- **The sim's own look (2026-11-08, the Mac run):** the look switches whose 1998 value draws art the sim does not
  have are fixed to ours in `PROFILE`: Detailed airbases (the runways, taxiways and aprons were missing), the
  atmospheric sky, water, night lights, effects, the conformal ladder; the CC0 ground and model textures when setup
  downloaded them ([airbases.md](airbases.md) §9). `test_sim_look.gd`.
- **[E2](plan.md#e2-the-front-end), the front end (2026-11-08):** `./modern-iaf` opens Home; Pick a plane, Training, Pick a mission, Fly,
  the flight, its debrief sheet, the Pilot log, Preferences and Attributions, in English and Hebrew (mirrored), in the
  round-3 look ([front-end.md](front-end.md)). Esc over a flight opens the pause menu. `test_front_end.gd`.
- **The records in SQLite (2026-11-09):** the sorties and their debrief records are in `user://modern-iaf.sqlite`
  (`iaf_tools::pilot_log`, `IafPilotLog`, a schema version and migrations); its first open imports the JSON records
  from before it once and leaves them in place; Home, Training, the Debrief and the Pilot log read it
  ([storage.md](storage.md) §5). `cargo test -p iaf-tools --lib pilot_log`, `test_front_end.gd`, `test_mvp.gd`.
- **[A4](plan.md#a4-the-gate), the gates on the original's converted data and install (2026-11-08):** every path under
  `assets/converted` a shared script reads goes through `Settings.converted()`, every path under the install through
  `Settings.install()`; the sim refuses everything but its own converted data and the M0 probe fails on any refusal
  (0 today). The sim's own loading screen in English and Hebrew ([front-end.md](front-end.md) §7).
  The effects (flares, chaff, trails, afterburner) draw a soft dot and the flight shows no message texts until the
  sim's own art and messages.
- **[A3](plan.md#a3-the-setup-wizard), the setup wizard (2026-11-03):** `./modern-iaf-setup` opens the wizard; it builds the terrain,
  the airbases, the units and weapons, the sounds and voices and the training missions as a step graph with stamps (a
  second run is all up to date), in English and Hebrew ([setup.md](setup.md)). Its look is Godot's default theme until
  the user's next round.
- **[B3](plan.md#b3-scenery-roads-and-inland-water), scenery and inland water (2026-11-03):** `iaf-sim scenery` builds the original's buildings, trees, road
  layer and city lights in the sim's UTM theatre from the shared open-data cache ([scenery.md](scenery.md)); the sim
  shows them over its own ground when Scenery is on (Preferences → Graphics → "Buildings and trees": Off / On /
  Detailed, On by default, greyed without the step, 2026-11-08); `iaf-sim airbases` flags the Dead Sea, the Sea of
  Galilee, the evaporation pans and the reservoirs as inland water ([terrain.md](terrain.md) §11).
- **[E3b](plan.md#e3-the-training-missions), the training missions in the game (2026-11-03):** `./modern-iaf -- --mission 2011` (… 2032) flies a start-up or
  take-off mission without the front end: parked cold, the start command (Ctrl+E) runs the jet's start sequence on
  the 6-DoF, the screens and the HUD come alive at the real moments; the radio menu (Ctrl+T, 1–3) asks the base's
  tower for start-up, taxi and take-off and the English TTS tower answers; at the end the flight is scored, the
  sortie and its debrief record stored in the records database ([training.md](training.md) §7–§10).
  `iaf-2026/tests/test_mvp.gd` flies both missions for the Sufa, the Barak and the F-35I to a Pass. Since 2026-11-08
  a crash, any damage or the wheels off the pavement fail a mission at once with that reason first; a pass ends 5 s
  after the goal or when the player ends the flight; the debrief sheet shows only the mission's goals
  ([training.md](training.md) §3.0, §4). A banner says "Mission complete" or the Fail and its reason, then the flight
  ends into the debrief; an ejection ends the sortie: silent, outside view, Fail "ejected" (§9). The start-up
  mission is the real start by keys: the F-16's six-step checklist and the F-35I's battery, IPP, engine, canopy, on
  a card in both languages; a step out of order has its consequence (a hot start, no power) and fails (§7.1).
- **[B2b](plan.md#b2-the-airbases), the airbases in the game (2026-11-03):** `iaf-sim airbases` compiles Ramon, Ramat David, Hatzerim and
  Nevatim into the theatre: `airbases.json` and paved masks (Detailed airbases), an own `iaf.ibx` and
  `terraintype.dat` ([airbases.md](airbases.md) §9); the missions start on the bases' parking spots; the M0 probe
  parks each jet on its spot, on the ground, at a base the flight model finds.
- **[B1](plan.md#b1-the-terrain), the terrain (2026-11-03):** `iaf-sim terrain` builds the sim's theatre `converted/terrain/israel/` from open
  data (GLO-30, Sentinel-2, the Survey of Israel), UTM 36N at 1:1 ([terrain.md](terrain.md)); the sim streams it
  (`theatre_dir()`); the M0 probe flies 5 s over it and checks the heights.
  Every download is shared with the original game in `assets/source/` (the WorldCover tiles in
  `source/imagery/sentinel2/`, also read by `iaf-imagery sentinel2`; the DEM in `source/dem/`): a complete cache
  builds with no network; the heights and the colour build at the same time ([terrain.md](terrain.md) §1.1, §4).
  Since 2026-11-09 the setup downloads only the 14 WorldCover tiles under the 8 m nodes (8.28 GB, before 21 tiles,
  10.62 GB) and reads the other 7 at 20 m over the network (offline, the build stops and says so); the DEM fetch is the shared `imagery_run::fetch_dem`
  (resumes a `.part`); every download logs its MB every 15 s ([terrain.md](terrain.md) §1, §2, §4).
- **[C2](plan.md#c2-the-6-dof) stage (c), the 6-DoF flies the sim's jets (2026-11-03):** TP-1538's control system (g command, α limiter, roll
  and yaw), `Fm { Original, SixDof }` behind `IafFlight` chosen by `Model = 6dof` in the own data (the original game's
  data never reaches it, tested), fuel burn, Mach effects (inferred), the validation rows on the 6-DoF, a real Sufa
  flight in mission 311 ([flight-model.md](flight-model.md) §9.11–9.14).
- **[C2](plan.md#c2-the-6-dof) stage (b), engines, gear, the jets' data (2026-11-03):** TP-1538's engine model scaled to the F110-GE-100,
  F100-PW-229 and F135; a three-strut gear with brakes, steering and a braked stand; the four jets' mass, inertia and
  geometry; tests against the ratings, the spool times, a take-off roll and a stop ([flight-model.md](flight-model.md)
  §9.7–9.10). The take-off roll is 26 % short of the F-16A's SAC figure (open).
- **[C2](plan.md#c2-the-6-dof) stage (a), the 6-DoF's core (2026-11-03):** `crates/iaf-flight/src/sixdof/`: NASA TP-1538's aerodynamic
  tables checked value by value against the scan, appendix B's coefficient build-up, a quaternion rigid body; the
  trim tests match the report's trims and Stevens & Lewis's ([flight-model.md](flight-model.md) §9). Nothing calls
  it yet.
- **[D2](plan.md#d2-units-and-weapons) drafts (2026-11-03), pending the user's decision:** the threat set's 12 units and 10 weapons as readable
  records in `iaf-2026/data/db/drafts/`, every figure sourced; `iaf-sim db` skips them, and a test compiles them as if
  approved ([threat-records.md](threat-records.md)).
- **[A1](plan.md#a1-the-project-skeleton), the project (2026-11-02):** the `iaf-2026/` Godot project with its `shared` link, `sim_settings.gd`, the
  `install_dir()` / `own_dir()` / `keys_file()` calls in the shared code (the original game reads the same files as
  before), the launchers `./modern-iaf` and `./modern-iaf-setup` (+ `.ps1`), `tools/test.sh` over `iaf-2026/tests` and
  gdparse on both projects, the M0 probe.
- **Own sources for the flight-model type and the bases (2026-11-03):** the player's jet takes its flight-model type
  from the sim's table (`Settings.fm_section`), not the converted descriptor; `IafBases` reads `own_dir()`'s
  `iaf.ibx`, not the install's ([README.md](../README.md) "How the sim reads its data"). `test_own_sources.gd`.
- **The M0 probe (2026-11-02):** passes the no-install check, the profile, the key and sound tables, and for each jet
  the mission's object database, the aircraft definition, the motion table, the 3D cockpit model and the flight
  model's start from the own `bd.ibx` (item [C1](plan.md#c1-fm-0-data)'s FM-0 data; `NEEDS DATA` without that file). With the terrain built
  ([B1](plan.md#b1-the-terrain), the terrain) it flies 5 s over it and checks the heights. On every flight it makes (the free flight, each jet's start-up) the
  3D-only cockpit check (2026-11-08): the cockpit dir the sim's own, no panel, lamp, HUD glass or ADI art loaded, the
  3D cockpit up ([cockpit.md](cockpit.md)).
- [A2](plan.md#a2-the-iaf-sim-compilers) (the data compilers), [B2a](plan.md#b2-the-airbases) (the airbases' layouts), [E1b](plan.md#e1-cockpit-data-sounds-and-voices) (sounds, voices, keys), [E3a](plan.md#e3-the-training-missions) (the training scoring): see
  their rows in [plan.md](plan.md).
- **[E1a](plan.md#e1-cockpit-data-sounds-and-voices), the HUD and display font (2026-11-08):** Hershey's Roman Simplex stroke font
  on the HUD, the MFDs, the small screens and the F-35I's panoramic display ([cockpit.md](cockpit.md) §5); each jet's
  cockpit by day and at night in [cockpit.md](cockpit.md) §6.
- The setup wizard's headings use Heebo's weights since 2026-11-08 (the font axis is set by its tag number; a "wght"
  string key had left every weight at the regular).

## Open
- **CI for the sim (2026-11-09):** [ci.md](ci.md) recommends parse-checking `iaf-2026/` in the godot job and adding
  `iaf-2026/tests/` to the sweep; the workflow is unchanged.
- **[D3](plan.md#d3-f-15c-baz-at-tel-nof), the Baz is not flyable:** it has no 3D cockpit and no model of its own,
  so the front end does not offer it and no mission flies it; type 110 flies the F-15I's flight-model row. Tel Nof's
  apron is placed by eye ([airbases.md](airbases.md) §5).
- **The core sounds' open points** ([sound.md](sound.md) §1.3–§1.8): the cockpit's idle-to-military step, the
  wind's real spectrum, the gun's spin-up, a real canopy's run time, the gear and flaps clips against a real F-16, the
  F-35I's own IPP, the tower's key clicks (on `wt/iaf-2026-voices`).
- **The afterburner's open points** ([sound.md](sound.md) §1.2): the light-off delay after the detent, the level in
  the cockpit, FlightGear's F-16 sounds not compared, the F-35I's own burner.
- **Keys and Joystick's open points** ([front-end.md](front-end.md) §9): one joystick flies (the first; a separate
  throttle or pedals as a second device is listed but not read); a joystick plugged in during a flight takes its map's
  buttons at the next flight or when the Preferences close; the hat's diagonals press two look commands, the last one
  wins; maps for more sticks than the Hotas X; the Hotas X's button choice is ours, untried on the stick.
- **[B3](plan.md#b3-scenery-roads-and-inland-water)'s open points** ([scenery.md](scenery.md) §9).
- **The scenery over a dense town is over its budget (2026-11-09):** on the Iris Xe at 500 m over Tel Aviv and
  Beersheba it adds 15 % to the frame with Far towns Light and 18–19 % with Full, against the 7 % budget
  ([scenery.md](scenery.md) §6).
- **The 6-DoF's wave drag is a fit ([C2](plan.md#c2-the-6-dof), the 6-DoF):** fit to each jet's published top speeds, not a sourced table; open: a public
  F-16 drag rise, the high-speed g onset, the take-off roll, the flaps ([flight-model.md](flight-model.md) §9.6).
- **[E3b](plan.md#e3-the-training-missions)'s open points** ([training.md](training.md) §6): the Hebrew voice (the user), the
  pilot's request voice (sound.md §7); the 6-DoF's short take-off roll.
- **[E2](plan.md#e2-the-front-end)'s open points** ([front-end.md](front-end.md)): a pilot list (the name is the computer's user
  name); the debrief sheet and the pilot log in the original game ([shared.md](shared.md)); the missions'
  own Hebrew briefings in `iaf-2026/data/missions/` still use the masculine imperative (the front end shows its own
  gender-neutral ones).
- **[Floating origin / camera-relative cockpit](plan.md#floating-origin--camera-relative-cockpit)**: open; the 3D
  cockpit's screens hold their depth out to 100 km from the flight's start (the F-35I's depth pull).
- **The airbases' open points** ([airbases.md](airbases.md) §9): the towers of Ramon, Hatzerim and Ramat David (their
  reference points stand in), one taxi hub per base. The temp-root run of item F finds any read of the
  original's data still left.
