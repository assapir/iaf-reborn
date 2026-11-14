# Modern IAF: status

What works and what is open, by work item ([plan.md](plan.md)). Newest first.

## Works
- **The start-up switches both ways (2026-11-13, the switches audit's M2, first part):** on all three jets every
  start-up switch goes back off by its key or a click and on again, with its consequence: main power off darkens
  everything, the starter off stops a crank, the avionics off darken the displays and lose the INS alignment (a
  warm-up and a new alignment when back on), the INS knob off loses it, the canopy opens; the JFS switch springs
  back to OFF at 52 %. The flight model holds the positions (`start.rs` `Start::on`); the checklist, the card and the
  debrief read them, so a switch back off undoes its step ([cockpit.md](cockpit.md) §5.2 "Both ways";
  `test_switches_both_ways.gd`). Open: the in-between positions (MAIN PWR BATT, JFS START 1, INS NORM / NAV), the
  lamps and cues (M3).
- **Each power switch its own system (2026-11-13, the switches audit's M2b):** on the Sufa and the Barak the
  generators give the displays' power, and each AVIONIC POWER and SNSR PWR switch powers its own system after a 3 s
  warm-up: MMC the HUD, ST STA store release, MFD the MFDs, UFC the DED, FCR the radar, RDR ALT the HUD's radar
  altitude; the INS needs main power only. Each has its own command (219); Ctrl+A throws the four AVIONIC POWER
  switches; the avionics step is the four on ([cockpit.md](cockpit.md) §5.2 "One by one"; `test_switches_both_ways.gd`).
  Open: the real consequences beyond the switches' names (sources), the CARA ALOW and GAAF voices without RDR ALT.
- **Every checklist switch by the mouse (2026-11-13, the switches audit's M1):** in the 3D cockpits the throttle
  answers the wheel and a drag both ways; a drag down begun at idle goes over the detent to OFF (Throttle OFF), a
  drag up moves it out of OFF (the idle step); the landing gear handles (both F-16s, the F-35I) send the G key's
  toggle; the F-16's FCR and RDR ALT switches (FlightGear's own `fcr-switch` / `rdr-alt-switch`, now nodes of `f16.glb`) move on a click
  and power the radar and the radar altimeter since M2b ([cockpit.md](cockpit.md) §5.2). `test_switches_click.gd` checks every switch of each jet's
  start-up, take-off and landing steps resolves to a clickable part, lights and sends its command. Open: the
  F-35I's CANOPY switch still behind the seat (a model move
  awaits the user's look).
- **The pointer comes back after a mouse look (2026-11-13, the user's Mac):** the right drag hides the pointer while
  held; on release, a release the view missed, a lost focus or a pause it shows again where it was
  ([cockpit.md](cockpit.md) §2). `test_sim_look.gd` checks it.
- **The right glove holds the stick (2026-11-13, the user):** looking down in the F-16s the right glove wraps the
  side-stick's grip (it hung 9 cm ahead of it) and the left palm sits on the throttle's head (it lay on the console
  beside it), its fingers closed on the grip (they spread onto the panel beside it), cold and in flight
  ([cockpit.md](cockpit.md) §5.3). `test_cockpit_view.gd` checks both hands.
- **No mission card (2026-11-13, the user):** a flight starts with nothing over it but the key hint, the flight
  running; the in-flight mission card and its H key are gone (record 118 and H are the Checklist notebook's since). The key hint names Esc
  and the pause menu for its first 8 s ([front-end.md](front-end.md) §8). The goals are in the briefing, the live "To
  complete" line, the completion message and the debrief. `test_flight_ui.gd` checks it.
- **The pilot's checklist notebook, part 1 (2026-11-13, the approved mock-up's look A):** in every flight a paper
  notebook on the right thigh; H raises it at the screen's lower right and stows it. Tabs START-UP, TAXI / T-O, RADIO,
  LANDING, EMERGENCY, DATA; a tab click, the wheel, PgUp / PgDn and the page's own ‹ › with its page count turn it. No
  key hints on it; a help line in the first start-up mission only. It replaces the start-up card: the steps whose
  switches are on ticked (a switch back off unticks its step), the step to take now marked. In a start-up training
  mission a ring on the current step's switch (and the F-16's RPM gauge for the idle step), a pointer at the screen's
  edge for a part out of view, the board sliding off a ring it would cover. English and Hebrew (mirrored). RADIO's
  frequencies: OurAirports' where published, the rest invented ([training.md](training.md) §11). `test_notebook.gd`.
  Open: the GUIDE tab and the front end's Guides screen (part 2); the throttle OFF, the brakes and the ejection handle
  by the mouse.
- **The F-16's approach speed matches the manual (2026-11-11):** TP-1538's speed-brake tables gave the open speed
  brake lift (+0.25 CL at 13° α); the 6-DoF flies the JSBSim model's speed-brake drag instead, and its flaps' lift
  (+0.122). The 13° α approach is 136–139 kt at the manual's three weights (manual 139–141 kt, was 118–121 kt)
  ([flight-model.md](flight-model.md) §9.17). Open: the speed brake's 43° limit with the gear down.
- **The trailing-edge flaps droop with the gear handle (2026-11-11):** on the 6-DoF the F-16s' and the Adir's
  flaperons go 20° down with the gear handle below 240 kt, less to 370 kt, and up with the handle, in the gear's 3.1 s
  (the F-16 flight manual); their lift, drag and nose-down moment are inferred (DATCOM, FM-0's drag); the models'
  flaperons droop with them ([flight-model.md](flight-model.md) §9.16).
- **The cockpit zoom one way per scroll; every jet's view alike (2026-11-11, the Mac play test's P1):** each wheel or
  trackpad step narrows the view (the true size kept between the wide and the narrow view; a step against the scroll
  dropped until it pauses), clamped at both ends; the trackpad zooms too. The Barak, the Sufa and the F-35I open at the
  same wide view, the F-16s at the same eye ([cockpit.md](cockpit.md) §2). Home's Pilot log entry removed: the pilot
  block → the Pilot screen's Pilot log button ([front-end.md](front-end.md) §3). `test_cockpit_view.gd`,
  `test_front_end.gd`. Open: the Barak's view looked closer on the Mac; at default settings both jets render the same
  view (only the HUDs differ: the Barak's Block 50 frame against the Sufa's wide-angle glass).
- **Mouse look in the cockpit (2026-11-11, the Mac play test's finding 9):** hold the right button and move the mouse
  to turn the head, double right-click to centre it; the wheel zooms from the wide view through the true size to a
  narrow 20° view for reading the MFDs. The left button stays on the switches. No head lean with the mouse
  ([cockpit.md](cockpit.md) §2). `test_sim_look.gd`.
- **The HUD stays on its glass (2026-11-11, the Mac play test's finding 10):** looking down or aside at the dash the
  HUD's symbols stay on the combiner glass while any of it is on the screen; the DASH takes over only once the glass
  is out of view ([cockpit.md](cockpit.md) §4, docs/cockpit.md "3D cockpit").
- **The canopy handle shows (2026-11-11, the Mac play test's finding 11):** a grey rod on the left canopy sill, aft of
  the throttle; it was a clear hit box under the pilot's shoulder ([cockpit.md](cockpit.md) §5.2).
- **The hands on the stick and the throttle (2026-11-11, the Mac play test's finding 12):** the left glove holds the
  throttle's grip and follows it over its travel (two shape keys in `f16_pilot.glb`); the right glove holds the stick
  ([cockpit.md](cockpit.md) §5.3).
- **The start-up checklist card, one step at a time (2026-11-11, the Mac play test):** a start-up flight opens with the
  checklist card only; the card is smaller and shows the step to take now with its key, place and wait, and its number
  of the steps ([training.md](training.md) §7.1). Replaced by the pilot's notebook on 2026-11-13
  ([training.md](training.md) §11).
- **The radio lines at subtitle size (2026-11-11, the Mac play test):** 20 px at 1080, was 26
  ([front-end.md](front-end.md) §8). `test_flight_ui.gd`.
- **The F12 info line: the mission and the FPS (2026-11-11, the Mac play test):** the sim's line leaves out the 1998
  game's modes, place, speed and controls (`Settings.info_line_full`, [front-end.md](front-end.md) §8).
  `test_flight_ui.gd`.
- **The black world with TAA or Upscaling (2026-11-12):** with Anti-aliasing TAA, or Upscaling Quality / Balanced,
  the 3D cockpit's own picture lost its alpha and laid black over the whole world (reproduced on Linux, Iris Xe, with
  the player's settings; each of TAA alone, FSR 1 alone and FSR 2 did it). The cockpit's picture is now drawn at full
  size with MSAA 4× whenever the flight uses TAA or an upscaler ([cockpit.md](cockpit.md)).
- **Finding the Mac's black world (2026-11-11):** a flight's start on the Mac ended in a black world under a fine 3D
  cockpit. A bisect switch now turns graphics features off for one run (`IAF_SAFE=all ./start-modern-iaf`, then half
  the names back on per run); after the first 10 frames the log lists every shader in use and whether it compiled,
  and a failed one opens the crash page; the start watch covers those frames too, and a pause no longer counts as a
  hang (a 30 s frame only logs `hang:`: a Mac's first start can compile shaders that long in one frame) ([front-end.md](front-end.md) §11.1). Fixed on suspicion, not yet seen on a Mac:
  the Levant sky's `acos` of a direction a hair over 1 gave NaN, which Metal carries into the radiance map, the fog
  and the ambient light (`atmosphere.gdshader`, also `normalize` of a zero vector looking straight down and two
  reversed `smoothstep` edges; the same `acos` in `cloud_layer.gd`, an `exp` overflow in `city_glow.gdshaderinc`); and
  the cockpit's picture no longer goes through MetalFX, whose output need not keep its alpha (an opaque cockpit
  picture would lay black over the world; `cockpit_origin.gd`). Open: the Mac's log with these.
- **A flight's start: no hang, faster, watched (2026-11-10, the Mac's P1 finding):** the mission card opened at the
  start under the loading screen and froze the flight, so the loading never ended on a player's machine (every
  scripted run skipped the card); the card is gone since 2026-11-13. The jet, the 3D cockpit and the pilot's body parse on
  worker threads from the start; the jet, the cockpit and the weapons are each drawn first in their own frame, named
  on the bar. Ramon's take-off from the flight scene: first start (no shader cache) 18.1 s, was 26–48 s; warm 4.4 s,
  was 5.1 s ([front-end.md](front-end.md) §7). A watchdog opens the crash page (§11) when the loading stops; every log
  line starts with its time ([../../docs/logs.md](../../docs/logs.md) §2). `test_start_watch.gd`.
- **The folder `modern-iaf/` (2026-11-10, [plan.md](plan.md#decisions-of-10-november-2026)):** the code folder was `iaf-2026/`; the game
  launcher is `./start-modern-iaf` (+ `.ps1`). Built data in `assets/converted/iaf-2026` moves to `converted/modern-iaf` on the
  first run of a launcher, the wizard or `iaf-sim` ([setup.md](setup.md)).
- **[D3](plan.md#d3-f-15c-baz-at-tel-nof), the F-15C Baz's data and Tel Nof (2026-11-09):** the Baz's unit record
  (`data/db/units/f15c.json`) compiles into the sim's bdb, and Tel Nof (LLEK, from OpenStreetMap and OurAirports) is
  the fifth base `iaf-sim airbases` compiles, with a Baz parking spot and a paved taxi path to 33L
  ([airbases.md](airbases.md)). `sim::tests::every_data_file_compiles_and_loads`,
  `sim_bases::tests::the_departure_is_paved`.
- **Compact JSON (2026-11-09, [plan.md](plan.md#rules-the-user-3-november-2026) rules):** every JSON file the
  sim writes is on one line ([data-formats.md](data-formats.md) §7).
- **The cockpit sound model (2026-11-09, Approvals A13, branch `wt/iaf-2026-cockpit-sound`, waits for the user's
  listening):** from the cockpit the outside sounds (engine, airframe, weapons, the world) come through the canopy and
  the HGU-55/P's ear cups: a 166 Hz low-pass and a level per class; the radio, Betty and the tones are unchanged; the
  external views hear everything unmuffled. The gun comes through the structure (a 700 Hz low-pass) and sits 5 dB
  over the engine and the wind, as in a cockpit recording (it was 6 dB, unfiltered). The wind stops at its row's level from 450 kt ([sound.md](sound.md) §1.9). The original
  game keeps its buses. `test_mvp.gd`, the original's `test_sounds.gd`.
- **The core sounds against real references (2026-11-09, Approvals A12, branch `wt/iaf-2026-core-sound`):** the
  dry engine plays its idle recording at its own pitch at idle (it was 4.2 semitones up) and rises to 1.3 and 6 dB at
  military; the start plays a JFS whine (its partials measured on an F-16 start), the engine's pitch and level by its
  RPM, a light-off thump and the JFS winding down at the generators; the gun buzzes at 100 rounds a second (it was
  48); the wind follows the dynamic pressure; the canopy closes at its checklist step; the touchdown is an airplane
  tyre skid with a thump, not a bicycle squeal ([sound.md](sound.md) §1.3–§1.8). The original game keeps its rules.
  `test_mvp.gd`, the original's `test_sounds.gd`.
- **The ground as the original game's (2026-11-13, the user's order):** the sim renders the ground with the
  original game's values (one set of terrain shader globals in both projects; Sky Atmospheric, Colour grading
  Original): no gold tint, no detail gain, no Levant haze; the Judean hills' gold speckle is gone. Its 2 m photo is
  levelled per sheet as the original game's (no match to Sentinel-2), its 4 m and 8 m levels built from it, its grey
  hills warmed as that layer's: the ground reads as the original game's photo. A rebuild of the theatre's photo
  (setup's terrain step "will run", nothing to download). Open: Ramon's base reads as a tan block (its Sentinel-2
  fill). Pictures in [terrain.md](terrain.md) §15.
  `test_sim_look.gd`, the original's `test_terrain.gd`.
- **Towns in the air photo's colours, the roads to the buildings' range (2026-11-13, look study A20):** each roof in
  its own colour from the air photo with solar heaters, the walls in the palette's colours chosen by the photo around
  each building, ribbon windows, a sun / shade step, grey city pavement (moot since the gold tint went), and every road drawn
  as dark asphalt to 5.5 km (was 1.5 km). Needs the scenery step again (no download) ([scenery.md](scenery.md) §7).
  Open: Scenery Detailed keeps its own near roofs; far shadows and contact shading (the grounding round).
- **The ground against a photo of Makhtesh Ramon (2026-11-11, Approvals A17, causes 1 and 2; dropped 2026-11-13,
  [terrain.md](terrain.md) §15.1):** a golden tint
  on the land at every hour, through Colour grading Natural (the albedo × `terrain_grade_tint` 0.86 / 0.78 / 0.43; the
  sea, inland water and the airbases' pavement keep their colour), and the photo's detail ×4.5 (it was ×2.5). The Ramon view's ground reads
  150 / 118 / 66 against the photo's 149 / 118 / 63 (it was 160 / 134 / 105); its spread 18.4 within the photo's 23.4.
  No GPU cost. Pictures and numbers in [terrain.md](terrain.md) §15.1. `test_sim_look.gd`, the original's
  `test_terrain.gd`.
- **[B4](plan.md#b4-ground-look-parity), the ground as good as the original game's (2026-11-09):** the pale,
  washed-out desert (sand 208 / 192 / 171) now reads tan with its relief (177 / 152 / 120): Colour grading Natural
  takes the photo toward a real ground's reflectance, with a little contrast and saturation after the tone mapper
  (docs/rendering.md §1.9). The close up's patches are back in tone only, the ground textures hold farther out by the
  photo's land cover, a macro tint breaks the photo's repeats, and the sim's setup fetches the ambientCG textures
  itself. Pictures beside the original game's in [terrain.md](terrain.md) §9.1. `test_sim_look.gd`, the original's
  `test_terrain.gd` (its picture unchanged with the rows off).
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
- **The Mac play test's findings (2026-11-08, [plan.md](plan.md#f-the-probe) F):** the mission card (removed 2026-11-13), the radio lines
  in the sim's band wholly in the game's language, the key hint; the pause menu centred at any size in Hebrew;
  Preferences without an aid or realism row and the aids off; Home on every start;
  clickable breadcrumbs ([front-end.md](front-end.md) §1, §8). `test_flight_ui.gd`, `test_front_end.gd`.
- **Keys and Joystick (P1, 2026-11-08, the Mac run's "keys / joystick mapping"):** Preferences → Devices opens a
  Keys screen (every command the sim has, by group; click and press to rebind, Cmd on macOS, conflicts with Swap /
  Use it here, Default, Reset all) and a Joystick screen (the devices, each axis' role with a live bar, Invert and a
  dead zone, the buttons and hat bound by pressing them, Reset all), in English and Hebrew. One compact store,
  `user://devices.json`, read, written and merged by Rust (`IafDevices`); the flight reads the merged key table and
  the axes. The Thrustmaster Hotas X has its own default map (`modern-iaf/data/devices/`), and a joystick connecting no
  longer asks for the install's `menu/joy` ([front-end.md](front-end.md) §9). On macOS the keys start from the
  laptop map, no numpad: the rudder on Z / X, the snap views on Alt + 1–9 (§9.1). `test_devices.gd`, the M0 probe
  with a fake joystick.
- **The Mac findings batch, devices and front end (P1, 2026-11-11, [front-end.md](front-end.md) §1, §2, §9):** the
  Joystick screen's bars show each role as the flight reads it (`Joystick.role_value`, one sense for the poller and the
  bars): the throttle forward is a full bar, checked against the 1998 game's events axis by axis (`test_devices.gd`);
  the afterburner detent on Preferences → Devices (reborn's Detent = MIL rule, `Joystick.detent_choice`); the hat is
  reborn's POV again (the sim's own four hat buttons dropped the diagonals), its eight directions the snap views; the Keys and Joystick side lists follow the scroll and both
  screens have Back; one head-look key set (the snap views; F2 rear view and the Shift free look are empty slots);
  on macOS the keys say ⌘ and Option; Home has Guides and Training has Missions and campaign, both greyed with
  "Coming in a later version"; Pick a plane picks on a click (no Next, no card picked on entry, the arrows move the
  focus, Enter picks).
- **The play test's polish (2026-11-09):** the Preferences back to the side layout (the sections listed, the picked
  one beside them, no line under an option); a Sound slider plays a sample of its class; Devices → Joystick greyed
  until a stick is plugged in; the Pilot screen (name, nickname shown on every screen, a 3:4 ID photo; records schema
  version 2); the loading bar follows the flight's real loading steps, named under it; the throttle up from OFF is the
  start-up's idle step (Ctrl+I gone); no drag-chute warning per flight ([front-end.md](front-end.md) §1, §4, §7, §9.2;
  [training.md](training.md) §7.1). `test_front_end.gd`, `test_devices.gd`, `test_mvp.gd`, the pilot_log unit tests.
- **The Pilot screen's findings (2026-11-10):** the nickname field editable (a hint in place of the name); Save and
  Back (a discard prompt); the picture opens the file picker; Reset the log after a warning and a second confirm;
  several pilots (a list, New pilot, the active one in `settings.cfg`); the first start makes the profile before Home;
  the logbook per plane on the Pilot screen, Home with the name and nickname only (records schema version 3, the
  sortie's plane) ([front-end.md](front-end.md) §1, §3; [storage.md](storage.md) §5). `test_front_end.gd`, the
  pilot_log unit tests.
- **Home's pilot block and Delete profile (2026-11-10):** Home's nickname, name and picture are one button to the
  Pilot screen; the Pilot screen keeps only the fields' labels and hints; Delete profile removes the pilot, its log
  and its picture after two confirms ([front-end.md](front-end.md) §1, §3). `test_front_end.gd`, the pilot_log unit
  tests.
- **The engine shutdown (2026-11-11):** Throttle OFF (Shift+1) cuts the fuel: the RPM winds down over about a minute,
  the generators drop at 52 % with the displays, the HUD and the avionics, the FTIT falls, the engine loop pitches
  down and fades; the recording's `checklist` step `cutoff` with fault `shutdown` / `no_start` fails a training
  mission; the JFS below 20 % and the throttle up from OFF restart it ([training.md](training.md) §7.2). `test_mvp.gd`
  (shutdown), the start.rs and training.rs unit tests. Open: the EPU and windmilling in the air.
- **The HUD's light (2026-11-09, Approvals A10):** the F-16s' HUD in the P43 green, drawn over the scene, bright by day
  and dimmed to a night floor as the sun sets, with a faint halo, the original's thin pen and the combiner glass
  untinted (2026-11-13; a quarter of 14 % before); the 3D cockpit's SYM wheel sets the day level (hover, wheel, drag; kept in the settings file) and Shift + H steps
  it, on the general clickable-control layer `cockpit3d_controls.gd` ([cockpit.md](cockpit.md) §5.1). The F-35I's HMD
  BRT knob turns the same level, its MFD BRT knob the displays' brightness (kept in the settings file too); the F-35I's
  helmet display lights as the HUD does, in P43 at that level. `test_hud.gd`, `test_mvp.gd` `_knob`. The F-16s' DAY / AUTO BRT / NIGHT switch on the right console (2026-11-11):
  clicked or scrolled, DAY keeps the day level at night, NIGHT the night floor by day, AUTO follows the sun; kept in
  the settings file (`test_mvp.gd` `_hud_mode`).
- **The HUD on a 2× display (2026-11-11, the Mac play test):** the HUD keeps its angular size, stroke and text crispness
  at every display scale: the pen's least width and the texts' raster size are physical pixels
  ([real-hud.md](../../docs/real-hud.md#modern-iafs-hud-light) "Display scale"; the rule holds in both games). The
  stroke is the original game's thin pen (0.87 mrad), the halo 0.73 mrad outside it and at least one pixel (an angle
  since 2026-11-13: one pixel at every size before), and the HUD is drawn over the scene instead of
  added (no white core over the sky), so it reads as crisp as the original game's Real HUD. The Mac's pictures matched Linux at scale 1: its "closer view" and
  "twice the size" came from an enlarged crop, and the glass is untinted. The side edge strips beside the
  HUD are removed (2026-11-12). The AoA indexer and AR / NWS bodies beside the posts' feet take the glareshield's
  paint (they drew flat black) and stand 2.5 cm outboard of them, clear of the posts as in the F-16C photo
  (2026-11-13). The combiner plate is fitted inside the curved posts.
  A 1× monitor beside a Retina screen (the user's Dell, 2026-11-13): Godot rendered it at twice its pixels and the
  system halved the picture; the game now turns hiDPI off there and renders the monitor's own 2,560 x 1,440, full
  Retina on the MacBook's screen (real-hud.md "A 1× monitor beside a Retina screen"). Open: a window dragged to the
  other screen keeps its start-up scale until the next start.
- **The start-up switches (2026-11-09):** the F-16s' start-up checklist by the mouse in the 3D cockpit: MAIN PWR, the
  JFS switch, the throttle, the AVIONIC POWER switches, the INS knob (their own nodes of `f16.glb`, each turning to its
  on position) and the canopy handle (a hit area), each sending its key's command; the card names each switch and its
  place ([cockpit.md](cockpit.md) §5.2). The F-35I's the same on its own panels: BATT, IPP, ENG (or START, or the
  throttle) and CANOPY, new nodes of `f35i.glb` at inferred places. `test_mvp.gd` (the Sufa's and the F-35I's
  start-up by clicks). Open: the JFS switch's spring back to OFF, the INS knob mostly hidden by the right sill from
  the eye, the F-35I's ENG guard.
- **AVIONIC POWER switches one by one, the AoA at rest on the ground (2026-11-11, from the user's Mac):** a click
  throws one AVIONIC POWER switch with its click; the four on take the step; MFD powers the MFDs, UFC the DED
  ([cockpit.md](cockpit.md) §5.2). The AoA gauge, indexer and HUD rest at 0° below 60 kt and follow the flow above it
  through a 0.25 s lag (§5.4). `test_mvp.gd`. FCR and RDR ALT: FlightGear's console has both as own parts; clickable since
  2026-11-13.
- **Town labels: dropped from the sim (2026-11-11, the Mac play test):** the sim draws no town names over the view and
  Preferences has no "Town labels" row; the sim's profile fixes the switch off. The 1998 game keeps its own (Extras →
  "Town labels", [../../docs/scenery.md](../../docs/scenery.md) §3.5). [scenery.md](scenery.md) §7. `test_sim_look.gd`,
  `test_front_end.gd`.
- **Wall shading and long shadows (2026-11-09, the look study's proposal 5):** the buildings' walls away from the sun
  take less sky light, and Preferences → Graphics "Long shadows" (on by default) draws the sun's shadows to 2.5 km with
  the near buildings casting them; +0.5 ms on the Iris Xe ([scenery.md](scenery.md) §7). `test_scenery.gd`. Open: at
  the Shoham pose the change is small (the sun behind the camera), so the reference's shaded street sides are still
  apart.
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
- **[E2](plan.md#e2-the-front-end), the front end (2026-11-08):** `./start-modern-iaf` opens Home; Pick a plane, Training, Pick a mission, Fly,
  the flight, its debrief sheet, the Pilot log, Preferences and Attributions, in English and Hebrew (mirrored), in the
  round-3 look ([front-end.md](front-end.md)). Esc over a flight opens the pause menu. `test_front_end.gd`.
- **The mission briefing (2026-11-09, awaiting the user's approval):** Pick a mission shows the picked mission's
  objectives, steps with their keys, base, runway and heading, time and wind on a Briefing page; on a Map page one
  zoomable map (the theatre's ground colour, roads, towns, the route, the whole airbase); on an Arming page each jet's
  front view with its stores (the Adir's two AIM-120 in its bays, 2026-11-10), an inventory column of the stores it may
  carry and the take-off weight; the subtitles name the tail number and squadron, no wing; the missions' titles are their kinds ([front-end.md](front-end.md) §10, `IafBriefing`). `test_front_end.gd`, `cargo test -p iaf-tools --lib briefing`.
- **The briefing's switch pictures (2026-11-11, awaiting the user's approval):** a start-up's How shows each
  step's switch cut from the jet's 3D cockpit with a ring round it, the state to wait for under the step
  (`modern-iaf/data/switches`, `modern-iaf/tests/_switch_crops.gd`; [front-end.md](front-end.md) §10). `test_front_end.gd`.
- **The loadout editor (2026-11-10, awaiting the user's approval):** on the briefing's Arming page a store drags from
  the inventory onto a slot, between slots and back; each station takes only what the unit record's `allowed` lists
  (re-sourced per jet, data-formats.md §3; each store its own record with its weight and size), racks (a TER of three
  Mk 82, two GBU-38, four GBU-39) with a "×n" badge that cycles the count, the stores without a model greyed, an
  amber imbalance warning past the F-16's asymmetric moment limit, the front views traced without pylons, a refused drop shakes its slot; a drop
  fills the mirror station too unless Shift is held; the keyboard path (Enter on a slot, Enter on a store); the fuel
  and the take-off weight follow, over the maximum it reads red and Fly is off; the loadout is the pilot's per jet in
  the records database and flies with the mission (mass, drag, tanks' fuel, the stores' models), Reset brings back
  the record's ([front-end.md](front-end.md) §10). Since 2026-11-11 the racks' weight rides in flight too (the
  BRU-57/A's 120.2 kg sourced; every rack's drag open), the bombs, guided bombs and tanks hang by their lugs under the
  F-16's pylons, and the Python 5, SPICE 2000 and Delilah fly as `modern_weapons.gd` records with their public figures
  (the Delilah as the GPS class, its cruise a long glide). Open: models of the Delilah and the 600 gal tank, a Sufa /
  Barak station chart, the racks' drag.
- **Inventory counts:** no public source gives the IAF's store counts; the records list none, so the inventory is
  unlimited. `cargo test -p iaf-tools --lib loadout`, `test_front_end.gd`,
  `test_mvp.gd --only loadout`.
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
  the user's next round. Since 2026-11-09 Done's **Start the game** opens the front end in the same process
  (Close quits), and Install shows "this step" in the running row and "all steps" from the durations measured on
  earlier runs, or the step count before any run ([setup.md](setup.md) "Time left").
  Since 2026-11-12 every optional step (Buildings, trees and roads; Ground and model textures) has an Include tick
  with its download and disk sizes: a left-out step is neither downloaded nor built, the choice is remembered, and
  unticking a built one offers to remove its data. Each step has its own Run again tick, and a skipped or failed step
  shows its reason (in Hebrew too) with Retry ([setup.md](setup.md) §3). Since 2026-11-13 a required step has no tick
  at all (an older choice file that left one out is ignored for it), and a long "about … left" wraps inside the
  state column instead of pushing the row aside.
- **[B3](plan.md#b3-scenery-roads-and-inland-water), scenery and inland water (2026-11-03):** `iaf-sim scenery` builds the original's buildings, trees, road
  layer and city lights in the sim's UTM theatre from the shared open-data cache ([scenery.md](scenery.md)); the sim
  shows them over its own ground when Scenery is on (Preferences → Graphics → "Buildings and trees": Off / On /
  Detailed, On by default, greyed without the step, 2026-11-08); `iaf-sim airbases` flags the Dead Sea, the Sea of
  Galilee, the evaporation pans and the reservoirs as inland water ([terrain.md](terrain.md) §11). Since 2026-11-12
  the sim draws its own road layer (Roads Detailed on by default when the step made it; the probe asked for the
  original game's path before, [scenery.md](scenery.md)).
- **[E3b](plan.md#e3-the-training-missions), the training missions in the game (2026-11-03):** `./start-modern-iaf -- --mission 2011` (… 2032) flies a start-up or
  take-off mission without the front end: parked cold, the start command (Ctrl+E) runs the jet's start sequence on
  the 6-DoF, the screens and the HUD come alive at the real moments; the radio menu (Ctrl+T) asks the base's
  tower for start-up, taxi, line-up and take-off, since 2026-11-13 listing every ground call on the ground (the next one
  marked) and landing in the air, line-up its own call, a call out of order answered "negative, hold position, request
  … first", each subtitle shown as its voice starts; the pilot's own voice makes the call through the helmet chain, then the English TTS tower answers (since 2026-11-12, item A21, [sound.md](sound.md) §5.2); at the end the flight is scored, the
  sortie and its debrief record stored in the records database ([training.md](training.md) §7–§10).
  `modern-iaf/tests/test_mvp.gd` flies both missions for the Sufa, the Barak and the F-35I to a Pass. Since 2026-11-08
  a crash, any damage or the wheels off the pavement fail a mission at once with that reason first; a pass is kept
  and the flight goes on until the player ends it (since 2026-11-13); the debrief sheet shows only the mission's goals
  ([training.md](training.md) §3.0, §4). A banner says "Mission complete" (fly on, or Esc → End the flight), or the Fail and its
  reason, then the flight ends into the debrief; an ejection ends the sortie: silent, outside view, Fail "ejected" (§9). Since 2026-11-13 (the
  user: "missions should fail if I start without tower permissions") a take-off mission fails at once on a phase
  without the tower's clearance (the engine start, leaving the spot, entering the runway, the roll), the tower saying
  so; lined up on another runway end the tower names it and the roll there fails; airborne, the goal still missing
  shows live ("To complete: raise the gear.") ([training.md](training.md) §3.3, §9). The start-up
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
  records in `modern-iaf/data/db/drafts/`, every figure sourced; `iaf-sim db` skips them, and a test compiles them as if
  approved ([threat-records.md](threat-records.md)).
- **[A1](plan.md#a1-the-project-skeleton), the project (2026-11-02):** the `modern-iaf/` Godot project with its `shared` link, `sim_settings.gd`, the
  `install_dir()` / `own_dir()` / `keys_file()` calls in the shared code (the original game reads the same files as
  before), the launchers `./start-modern-iaf` and `./modern-iaf-setup` (+ `.ps1`), `tools/test.sh` over `modern-iaf/tests` and
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
- **The voices (item A5, 2026-11-09, branch wt/iaf-2026-voices, waiting for the user's ear):** every speech clip is
  Kokoro text to speech in American voices, made by `iaf-sim voices` as Ogg: Betty measured against two real
  recordings (pace, pitch, repeat), the tower's calls in one breath, the radio chain with key clicks around each
  call ([sound.md](sound.md) §5).
- The setup wizard's headings use Heebo's weights since 2026-11-08 (the font axis is set by its tag number; a "wght"
  string key had left every weight at the regular).

## Open
- **The F-35I's CANOPY switch cannot be seen from the eye** (2026-11-11): our model puts it 0.31 m aft on the left
  console (`tools/f35i/cockpit3d.py` panel L4), behind the seat's side, so the briefing shows its `where` text, no
  picture (`_switch_crops.gd` `HIDDEN`); moving the panel forward would let the pilot see and click it.
- **A first start's shader compilation** (2026-11-10): 14 s of the 18 s first start here; with Metal on a Mac it
  takes about ten times as long. Godot compiles a material's shaders when the material is first drawn. The loading
  steps spread this work over named frames, but a single frame cannot show progress while it compiles. Godot keeps the
  compiled shaders across restarts (`user://shader_cache`, the driver's pipeline cache in `user://vulkan`): the next
  start is the warm 4.4 s. A warm-up in the front end was weighed and not built (2026-11-10). The compilation blocks
  the main thread wherever it runs, so the wait would move from the loading screen to a frozen menu; it would not get
  shorter. What remains open: compiling shaders off the main thread, which needs Godot's export-time shader baking
  (Godot 4.5+, for exported builds only).
- **CI for the sim (2026-11-09):** [ci.md](ci.md) recommends parse-checking `modern-iaf/` in the godot job and adding
  `modern-iaf/tests/` to the sweep; the workflow is unchanged.
- **[D3](plan.md#d3-f-15c-baz-at-tel-nof), the Baz is not flyable:** it has no 3D cockpit and no model of its own,
  so the front end does not offer it and no mission flies it; type 110 flies the F-15I's flight-model row. Tel Nof's
  apron is placed by eye ([airbases.md](airbases.md) §5).
- **The core sounds' open points** ([sound.md](sound.md) §1.3–§1.8): the cockpit's idle-to-military step, the
  wind's real spectrum, the gun's spin-up, a real canopy's run time, the gear and flaps clips against a real F-16, the
  F-35I's own IPP, the tower's key clicks (on `wt/iaf-2026-voices`).
- **The cockpit sound model's open points** ([sound.md](sound.md) §1.9): the canopy's measured transmission loss, the
  helmet in flight, the air-conditioning hiss, the engine and wind levels by ear.
- **The afterburner's open points** ([sound.md](sound.md) §1.2): the light-off delay after the detent, the level in
  the cockpit, FlightGear's F-16 sounds not compared, the F-35I's own burner.
- **Keys and Joystick's open points** ([front-end.md](front-end.md) §9): one joystick flies (the first; a separate
  throttle or pedals as a second device is listed but not read); a joystick plugged in during a flight takes its map's
  buttons at the next flight or when the Preferences close; the hat's diagonals press two look commands, the last one
  wins; maps for more sticks than the Hotas X; the Hotas X's button choice is ours, untried on the stick.
- **[B3](plan.md#b3-scenery-roads-and-inland-water)'s open points** ([scenery.md](scenery.md) §9).
- **The scenery over a dense town is over its budget (2026-11-11):** on the Iris Xe at 500 m it takes 14 % of the GPU
  time over Tel Aviv (3.1 ms) and 13 % over Beersheba (2.7 ms), against the 7 % budget; 17 % and 15 % before the
  buildings' colours per vertex and their 250 m tiles, which keep the picture ([scenery.md](scenery.md) §6).
- **The 6-DoF's wave drag is a fit ([C2](plan.md#c2-the-6-dof), the 6-DoF):** fit to each jet's published top speeds, not a sourced table; open: a public
  F-16 drag rise, the high-speed g onset, the take-off roll, the flaps' sourced aerodynamics and the approach speed
  ([flight-model.md](flight-model.md) §9.6, §9.16).
- **[E3b](plan.md#e3-the-training-missions)'s open points** ([training.md](training.md) §6): the Hebrew voice (the user), the
  pilot's request voice (sound.md §7); the 6-DoF's short take-off roll.
- **[E2](plan.md#e2-the-front-end)'s open points** ([front-end.md](front-end.md)): a pilot list (the name is the computer's user
  name); the debrief sheet and the pilot log in the original game ([shared.md](shared.md)); the missions'
  own Hebrew briefings in `modern-iaf/data/missions/` still use the masculine imperative (the front end shows its own
  gender-neutral ones).
- **[Floating origin / camera-relative cockpit](plan.md#floating-origin--camera-relative-cockpit)**: open; the 3D
  cockpit's screens hold their depth out to 100 km from the flight's start (the F-35I's depth pull).
- **The airbases' open points** ([airbases.md](airbases.md) §9): the towers of Ramon, Hatzerim and Ramat David (their
  reference points stand in), one taxi hub per base. The temp-root run of item F finds any read of the
  original's data still left.
