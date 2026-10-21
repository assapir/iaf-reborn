# Status — 2026-10-14

This page says what works today, what we build next, and what is still open. Details live in the linked docs.

**Terms:** AA / AG = air-to-air / air-to-ground; AI = computer-controlled units; AoA = angle of attack; AWACS =
airborne early warning aircraft; CCIP = continuously computed impact point (bomb sight); DASH = the helmet sight; DLZ
= dynamic launch zone (missile range band); ECM = electronic countermeasures (jamming); EO = electro-optical (FLIR /
TV) sensor; FLIR = forward-looking infrared; FM = flight model; FPM = flight path marker; HARM = anti-radiation
missile; HUD = head-up display; ILS = instrument landing system; IR = infrared; LCOS = lead-computing optical sight
(gun sight); LOD = level of detail; MFD = multi-function display; MRM = medium-range missile; NAV = navigate (fly the
waypoints); PPI = plan position indicator (radar picture); RWR = radar warning receiver; SAM / AAA = surface-to-air
missile / anti-aircraft guns; STT = single-target track (radar lock); TSD = tactical situation display (map). OFF /
STBY / STT / BORE / LRS / TWS / ACM / GMT / MAP are the radar modes (docs/radar.md).

## Where we are
- **Playable missions: 60 of 68 by the coverage report** (every feature they need is built; docs/mission-coverage.md).
  - Flown end to end: 311, 312, 315 (bombing).
  - Checked in part: 313 / 322 ground fire; 134 (Delta flight dive-bombs and destroys both P-40 radars) and 406 (the
    AI wingman destroys its target). The player's own targets there were not flown.
  - Left: multiplayer (8).
- **Flyable jets: all seven of the Jet list** — F-15, F-16, F-4E, F-4 Kurnass 2000, Lavi, Kfir, Mirage (Jet list or a
  mission's jet; docs/aircraft.md §5) — plus the MiG-23 / MiG-29 with their own cockpits wherever a mission puts the
  player in one (the Mission Creator does; no campaign mission does), plus our F-35I in one jet's slot (Extras,
  docs/f35i.md). A mission whose player jet is any other type flies it as the F-16.
- **Mission Creator** (single player; docs/front-end.md §19): the screen with all its controls, RANDOM, LOAD / SAVE
  of the original's files (docs/formats/mcr.md, in the user data folder), FLY builds mission 0x29a as the exe
  (files, jets, brains, positions, routes, targets, SAMs / AAA, time, weapons, roles) and flies it through the TSD and
  Arming; the By Kills score and the "blue / red team won" debrief headline (`FUN_004a8420`, `FUN_0059a480`); the
  WEAPONS choice empties every jet's other stores (`FUN_0058c9c0`).
- **Game version: v1.1 logic**, with v1.1 data when setup is given the patch (`--patch`); v1.0 data still plays. Doc
  addresses are v1.1 (docs/v1.1.md maps them to v1.0). All the flight model's v1.1 changes are ported
  (docs/flight-model.md §16).
- Everything comes from the player's own ISO; the repo (github.com/assapir/iaf-reborn, GPL-3.0) holds no game data.
- Rule: logic, layout, timing and colours follow the original. Improvements are opt-in switches, original by default.

## Priorities (user decision: 1. player experience, 2. enemies, 3. missions and general fixes)

**1. Player experience** (in order):
- Done:
  - Radar contacts / lock / STT, HUD target box, IR missile slaved to the radar; chaff / flares (player side); Real
    weapon capabilities (see Done).
  - Autopilot (A key; the AI control loops; Landing 312 approach mode) (see Done; 312's demonstration lands on the
    centreline, the instructor's markers fire in Original and Real: docs/autopilot.md §3).
  - Cockpit camera = the original projection, so the HUD ladder lines up (docs/cockpit.md "3D view").
  - Views, time compression, pause / in-flight menu (docs/views.md).
  - RWR (list, lights, sounds, MFD page / panel dial, F5 threat), radar MAP picture (docs/rwr.md, docs/mfd.md §4);
    AI jets and ground units with a brain lock the player (docs/ai.md §14); a site without one never does. Other MFD pages (FLIR / TV / HARM) (docs/mfd.md; open: Open
    gaps → Cockpit / MFDs).
  - Helmet sight DASH (weapons.md §5.4: the helmet display in `Dash` 1 cockpits, the IR seeker off-boresight in free
    look / padlock within the generation cone).
  - Joystick / throttle / pedals (docs/controls.md §5): tested by the user on Linux (2026-10-20) and macOS. Ours:
    Devices "Stick response" Soft centre (smaller dead zone + expo) for a stick that feels too sensitive at the centre.
  - Other jets flyable: the Jet list's seven (tests/godot/test_jet_list.gd), the Kfir / Mirage shared data with
    Flight data = Original.
- Open: detached-looking stores.

**2. Enemies:**
- Done: AAA, radar / IR SAMs, ground rockets (docs/ai.md §14); the decoys' effect on missiles (docs/weapons.md §10);
  AI air-to-air / air-to-ground, enemy flares / chaff, script ops 1 / 2 (docs/ai.md §13, `game/ai/combat.gd`); the
  AI's ripple / rockets / laser bombs, Arming loads and stores on AI jets, action 430, STT locks, the player's ECM
  (electronic countermeasures) in the AI sensors (the original has no AI ECM), helicopters and scripted aircraft,
  turrets / dishes / rotors, AI systems damage and engine sound (docs/ai.md §13–§14).

**3. Missions and general fixes:** the mission sweep (`tools/mission_sweep.sh`), the remaining small bugs below,
~~Jump In~~ (done: docs/front-end.md §13.11), the Reference screen, ~~night lighting~~ (done: the
original's light points and cockpit darkening, Graphics → MORE Night lights; docs/rendering.md §4–§5), detailed
airbases (Graphics → MORE Airbases: procedural runway / taxiway / apron surface with markings at all ten iaf.ibx bases;
docs/rendering.md §7) and the airbase footprints of the Survey imagery (the 2 m photo up to the base edge,
docs/imagery.md §3).

**PARKED (docs/roadmap.md):** imagery: SPOT 5 outside Israel, better AI, cheats, sea level west of
Suez, extra sounds, multiplayer, setup wizard + launcher, modern aircraft / weapons, Pi 5 profile.

## Small bugs (fix between jobs)
- **Mission sweep 2026-10-14** (`tools/mission_sweep.sh`: all 60 playable missions headless, the player parked
  300 s, then the targets destroyed):
  - No script errors; every mission passes once its targets die.
  - Lost early with the player idle: 114, 115, 116, 117, 122, 215, 223, 234, 236, 237, 402. Checked against the exe
    (2026-10-20), no deviation makes the enemy quicker:
    - 115, 215, 223, 234, 236, 237, 402 (and 117's helicopter path) are scripted kill shots. An event jumps a
      shooter's trigger list to miss shots, a wait and a kill shot (op 2 with 0x852 ≠ 0, `FUN_004aae40` →
      `FUN_004d6130`). The player is meant to kill the shooter in that window.
    - 114, 116, 117, 122 have interceptors (brain 13) whose primary target is the escorted jet. They shoot it down
      with AA-2s and guns; the escorted jets never fight back, as in the exe. The AI's missile q, blast damage,
      skill periods, Launch cone and gate match the exe (docs/ai.md §13).
    - The AI gun burst was too short (1 s; the exe: 14 ticks, about 2.6 s). Fixed; this makes the AI stronger.
    - Open: only a run of the original would compare the interceptors' arrival times.
  - 132's "LEADER KILLED" and 132 / 133's "FRIENDLY HIT" end nothing in the exe either. Event ops only play, count,
    add debrief items and jump (`FUN_004ba7a1` → `FUN_004c3425`); only the role rules end a mission (`FUN_00599da0`).
    132 has two role-1 targets (the leader's jeep and the PHOTO SENSOR). The evNotDestroy debrief item of a unit
    still alive at the end (`FUN_004a63c0`, e.g. 132's "The terrorist leader escaped.") is now built.
- **Stores look detached** (user report: "not in place" from behind):
  - The pylons are quads in each jet's model, edge-on and nearly invisible from ahead / behind / below, as in the
    original (docs/weapons.md §2.2).
  - The TER (triple ejector rack) shoulder slots (2–3 bombs) hang at the pylon height ±Pilon sideways (original
    `FUN_0053c990`), so they touch the wing.
  - Checked: the stations sit on the model (F-16 tip rails at x ±4.78, airframe ±4.73; each single store's Pilon
    point on its station; test_arming.gd).
  - Next: the user says which view is wrong (original vs better). (The flat white fins seen from behind are gone
    since the Present scale / smoothing work.)
- **Lavi skin** (user report: "wrong"): checked — the texture is the original's `lavi_h.bmp`, and every model's UVs
  match the `.x` / `.xfr` exactly (docs/formats/x.md). The plain brown nose top and the white-tinted glass are the
  original's.
- **`--smooth` bows the stadium** (`stationary/stdum_h/stadum_h`): its straight walls curve and the seats show. Seen in
  the UV check; open.
- **Tests hang under load:** in a full `tools/test.sh` run while other Godot runs are busy (parallel jobs), a test
  (test_ui_smoke, test_damage, test_arming) occasionally hangs until the 300 s timeout with no output. Alone they pass
  every time (8/8 on 2026-10-01). test.sh now prints "FAIL timeout" and the last output lines — use that next time
  to find the cause.

## Done
| area | state |
|---|---|
| Setup | `tools/setup-cli.sh [--patch <v1.1>] <ISO> [Hebrew packs]` builds everything; ISO + `setup.esa` extraction; `iaf-patch` applies the official v1.1 patch (RTPatch) without Windows, before the Hebrew packs and every conversion; the setup wizard (`./setup`, docs/setup.md) runs the same steps in-process and only what changed |
| v1.1 | `docs/v1.1.md` (v1.0→v1.1 diff and address map); the flight model's changes (docs/flight-model.md §16); outside it: HUD (FPM, 12 px/deg ladder on the marker, gun cross at GunRetPositionY), ejection throw straight up, training debrief → Jet list, event counter order / missing-entity skip / combat ops 21–22, landed handler on every landing; v1.1 rules of unported systems recorded (damage.md §4.4, front-end.md §17); docs and code comments on v1.1 addresses |
| Front end | start-up straight to the main menu (the intro videos are not played: README "Intro videos", front-end.md §18); original screens, animations, sounds, music; training + campaign; Jet list; Hebrew packs; QUIT box and credits roll; ours: the CD autorun launcher (Extras) |
| Terrain imagery | georeference (thin-plate spline, 610 control points, docs/georef.md); Sentinel-2 10 m layers outside Israel (1998 / modern colours, docs/imagery.md), picked per region on Graphics → MORE page; Survey of Israel 2015 2 m over Israel (1998 / modern colours, `iaf-imagery mapi2015`); `setup-cli.sh --imagery` (sentinel2; Survey of Israel sheets download only) |
| Preferences | original 5 pages (Graphics, Sound, Keyboard, Devices, Gameplay) + our **Extras** (flight data, weapon data, language, info line, blackbox, HUD pitch ladder, Real HUD (every jet's real HUD / sight / helmet display, the MiG-23's АСП-17МЛ sight and the MiG-29's ИЛС-31 / Щель-3УМ included: docs/real-hud.md), all keys, window, anti-aliasing, terrain close up, sky, upscaling, water — docs/rendering.md; imagery per region — docs/imagery.md; scrolls 8 rows at a time; Mouse wheel: Regular / Natural) and **Physics** (19 improvement switches, the Keyboard page's scrollbar, 15 rows shown) tabs, EN + HE; VSYNC (ours) on the Graphics page (docs/front-end.md §12) |
| Controls | original key table, rebinding on the Keyboard page, in-flight keys through the table; joystick (one device: stick / throttle / rudder axes per the Devices page, hat = snap views, buttons through the table and bound on the Keyboard page, menu/joy/*.joy), tested on Linux and macOS hardware |
| TSD / briefing | vector map, units, flights, waypoints, fly any flight, briefing texts and links (picture windows fit their bitmap whole and, as in the exe, do not zoom; ours: the mouse wheel scrolls the texts by the arrow step, docs/front-end.md §12.9); the selected-unit label, the ruler (right-drag), the map keys; in flight (FlyTSD, docs/views.md §1) the live battle, Fly into another formation's jet (any flyable type, the wingman's seat when the leader is down), Visit, Ctrl+P, waypoints fixed |
| Mission runtime | scripts, triggers, events, voices + subtitles, win / lose rules, mission boxes, debrief; player = the default (or chosen) flight's leader |
| Flight model | original ground + airborne logic ported line by line (docs/flight-model.md §14–§15): envelope, stall, spin, landing / crash check, afterburner delay, gear / flaps / brakes, start rules, Gameplay prefs; the ground pedal as a stick event, the ground attitude's shake off the runway and on the belly, the map edge (EndWorld.wav, "Tornado" push-back) |
| Physics switches | 15 "Better physics" options (incl. F-16 deep stall, ground effect, brake pitch, asymmetric stores; docs/flight-model.md §10) + 6 original-bug fixes (falling-jet heading, enemies tougher on easy AI, lock threat, stores weight / tank fuel, bomb burst depth, collisions with hidden units / wrecks; docs/deviations.md §2) |
| AI flight | docs/ai.md: the bdb brains (rule engine, conditions, sub-brains, combat ops 21 / 22) and the original's autopilot control loops fly every brain-controlled jet through the same flight model: routes with timed waypoints, formations, take-off from the hangar, go home and land, hold; the player's wingman follows the player; `ai.contacts()` for radar / RWR |
| Autopilot | docs/autopilot.md: A key off → level → NAV → off, lamp 8, HUD `AP LVL` / `AP NAV`, stick / rudder break-out, NAV = Fly2WayPt with waypoint sequencing, a land waypoint = the AI's go-home circuit and landing (312's demonstration lands on the centreline) |
| Player weapons | docs/weapons.md: gun (LCOS / strafe pippers), IR seeker + missiles (shoot cue, AI afterburners seen past R/2), radar missiles (600 / 610: DLZ, MRM HUD sight, shoot cue, "SEC" row, STT DLZ ticks, semi-active rule), HARM / Shrike (590: the original HARM scan, Ctrl+Return steps targets; Extras HARM targets: Real), TV weapons (635 Maverick, 640 TV missile: guided motion, the camera riding the weapon, TRA / TER, HUD mode-7 diamond), bombs (MK-82/83/84, M117, CBU-87/97 cluster, laser bombs: guided, FLIR designation) and rockets (ZUNNI, LAU-61) with ripple, CCIP (terrain ray) / delayed release, jettison (tanks, then bombs); stores on the pylons, master / HUD modes, weight / drag, external fuel tanks, stores MFD page; Extras "Weapon data: Real" (docs/real-weapons.md) |
| Radar | docs/radar.md: modes OFF / STBY / STT / BORE / LRS / TWS / ACM / GMT / MAP with the per-jet tables, scan, terrain line of sight, lock keys, MFD B-scope / PPI, HUD target box, slaves the IR seeker, feeds the gun range; chaff / flares (docs/weapons.md §10) |
| Arming screen | original screen 0x1f (docs/front-end.md §15): jet front views + stations, weapon list AA / AG / Misc, drag and drop with the per-station allowed counts, right-click, DEFAULT, CURRENT LOAD / MAX T.O.W., the original's blocking checks (overweight, wing balance) and "Use weapon load?"; the load goes on both jets of its flight, the player's and the AI's (stores, weight / drag, pylon models); Yes / DEFAULT also load table slots 7..10 (the exe's first Enemy / Other / Hotel / India formation, §15). What the loads unlock: docs/mission-coverage.md (315 "Cold Steel" bombed end to end destroys all 7 targets, test_bomb_missions.gd) |
| Real aircraft data | Real set for all seven flyable jets (six data sets: F-16, F-15C, F-4E / Kurnass 2000 shared, Kfir C7, Lavi, Mirage IIICJ): weights, thrust, drag, roll, fuel, stall, pedal steering, drag chute, the low-speed indicated airspeed fix (docs/real-aircraft.md); the flight data loader reads the v1.1 files (`bdgen.dat`, `*gen.skp`, XOR-encoded); AI types: their own Real rows, used by the AI jets (docs/real-aircraft.md §9) |
| Damage | docs/damage.md: hits, blast formula, destruction, falling jets, explosions / smoke (water splash and ring, the fatal-hit fireball, two explosions at a falling unit's impact), the player's systems damage, collisions, the friendly-hit voice |
| Eject | E ×3: seat, canopy, parachute and its swing, mission lost |
| Views | docs/views.md: pause, On-The-Fly menu (GDI layout, Arial metrics and hit test as the exe; front-end.md §16.2), the in-flight render message box (§16.4), FlyTSD (Esc), time compression, the original cameras (snap views, free look, padlock, external / fly-by, radar target, threat, wingman, weapon) |
| Graphics / rendering | the Graphics page wired (terrain / object detail, effects, smoke trails, textured sky with the cloud layer, shadows, external stores; docs/front-end.md §12.4); our render options on Graphics → MORE, upscaling, the water shader (waves, sun glint, sky reflection; rendering.md §1.3), the detailed F-16D model with the IAF dorsal spine and every pylon (docs/aircraft-models.md) and the detailed effects (GPU particle explosions, smoke, missile trails, contrails, heat haze; rendering.md §6) among them (docs/rendering.md) |
| Cockpit | all 9 original 2D cockpits (docs/cockpit.md): round gauges, attitude indicators, vario / AoA tapes, HUD (11 colours, traced symbology incl. ILS and the waypoint marker), I-mode (F12: marks toward the aircraft out of view), panel lights; MFDs (docs/mfd.md: radar incl. the MAP picture, TSD, RWR page, NAV, stores, damage, FLIR / TV with the EO camera, HARM); RWR (docs/rwr.md); helmet sight DASH (docs/weapons.md §5.4). Ours: the F-35I's modelled cockpit (day / night panel art, the panoramic display with status bar, portals, lower windows and standby display, its cockpit-view model; docs/f35i.md §4); Better cockpit (Extras): the turning panel compass / HSI on the Kfir, F-4E, Mirage and MiG-23, the F-16 AoA indexer and FLCS / TO/LDG CONFIG lamps, the Mirage VVI needle; the engine gauges from the FM (real RPM, a temperature model, the throttle needle above MIL in AB), the fuel needle with the drop tanks and the F-15's live fuel counter, the Lavi / Mirage panel clock, crisp MFD pages, the F-16's, Kfir's and MiGs' needles on their labelled dials (the F-16's oil pressure and nozzle position live; the MiG-23's Mach, EGT, litre and VVI faces, the MiG-29's twin tachometers), the MiG-29's radar altimeter and AoA / g meter, metric units on the MiGs' faces, the MiG-23's range drum (open: the MiG-23's SPO-15 lamps, HSI bars and hydraulic gauge; docs/mig-cockpits.md §4), the F-16's AR/NWS lamp, needles that follow their values with an instrument's lag (docs/cockpit.md "Better cockpit"; no panel paints a G-meter, the unused shipped art is not better) |
| Aircraft models | all 22 models: moving parts per the original rules, gear, afterburner flame, canopy / pilot, damage visuals. Ours: the F-35I's gear doors (open only while the gear is not fully up, shut nose doors once it is), its wing pylons at the real stations 1 / 3 / 9 / 11 (shown while loaded; docs/f35i.md §3.1), Rolling wheels (Graphics → MORE; the F-35I's wheels; docs/part-animation.md §2.2) |
| Sounds | original sound table: engine, gear, flaps, air brake, AoA tone, Betty warnings, touchdown, crash; volume sliders |
| Radio | docs/radio.md: the phrase engine (word wavs + subtitle; the runway numbers the install lacks from our TTS clips, game/extra/tower_numbers); the tower by itself on the ground (taxi / line up / hold / take-off) and Ctrl+T in the air (proceed to runway, cleared to land, gear not down, go around, taxi to hangar; a click elsewhere); wingman commands Alt+P/B/E/W/T/C on the AI wingman's brain (its bdb "Roger" replies, "negative" when it cannot); waypoint, airborne, landed, crashed, eject and kill reports; the AWACS contact calls (bearing, range, heading) |
| Terrain | all of `map.ptt` (levels 11..6 + all 51 insets, 2342 nodes) as a streamed quadtree with distance LOD to 200 km, level-6 heights with the original's inset interpolation, skirts; runway digits surveyed on every airbase (2 mirrored fixed); `terraintype.dat` surface types (water / rough / runway) feed the flight model; loaded behind the wait screen (docs/formats/ptt.md) |
| Pilot records | screen 0 at startup (docs/front-end.md §13): pilot list, Dossier (edit boxes, photo, rank, score, missions), Records / Kills / Losses, New / Remove / Login; each debriefed flight recorded (result, MissBonus, destroyed units as kills / losses, score multiplier), best-attempt score and rank, the briefing's "<rank> <name>"; Future Missions 2–7 locked until the previous pass; JSON in the user dir; the Debrief's DEBRIEFING / KILL TALLY / LOSSES pages (headline and notes, this flight's kills and losses per type with counts, the score column) |
| Tests | `tools/test.sh`: Rust + 83 headless Godot tests (`tests/godot/test_*.gd`), isolated from the player's settings; fails on any script error or a 300 s timeout |

## Open gaps (by area)
Checked against the code on 2026-10-19 (each doc's own "not built" notes have the details).
- **Terrain**: the original data has no elevation west of Suez (flat −557 m, kept). A modern DEM (digital elevation
  model) is not built.
- **Flight**: the OutRunway force feedback; the map-edge console line (`FUN_0044a060`, docs/flight-model.md §15.5a).
- **F-35I cockpit**: the panel pans as one flat picture, like the originals'; its side-stick and throttle are fixed
  in the render; the portals show the original MFD pages (pixel font) in the F-35 colours; looking 15–90° aside shows
  the panel strip's edge.
- **Controls**: one joypad (the first connected), as the original's one DirectInput device; real-hardware use so
  far: a joystick on Linux (2026-10-20), a T.Flight Hotas X on macOS (`SDL_JOYSTICK_MFI=0`). No force feedback. Unhandled commands: chat (multiplayer only; docs/controls.md §4).
- **Pilot guide PDFs** (not urgent): some pictures land at the top of the next page above the following heading; one
  nearly empty page (F-16 "Not drawn"); the MFD pictures are the ~128 px original art scaled (blocky; Better cockpit's
  crisp MFD pages draw them sharp, docs/mfd.md §8).
- **Pilot guide pictures**: the stamps' rule changed on 2026-10-20 (inputs only, no game code), so the next `tools/guide_shots.sh` renders all of them once; later runs keep them. That render also brings the pictures up to
  2026-10-19's changes: the F-16 / F-15 / Lavi Real HUD scales moved in (docs/real-hud.md "What ours draws") and the
  Real AIM-9L's 10 NM range scale (docs/real-weapons.md; the guides' text already says 16.1 km). New pictures since:
  the F-16's delayed CCIP, `hud_ccip_delay` / `hud_ccip_designated` (docs/guides/f16.md §11).
- **World scale Real 1:1** (docs/world-scale.md, Extras → World scale): steps 1–8 built (true-size
  models, jets, gear clearance, weapons; every airbase at its real place on its real main runway, with its mission
  units, markers and routes). The AI's final approach holds the real runway's centreline; the old site is painted over without seams; the new site's ground close up is the old site's fine art warped there (§4.3). The runway numbers are the real designators (with L / R, the taxi signs re-lettered), the runway surface the real width (OurAirports' widths), the ships their real length, Bley is Marj Ruhayyil (inferred, now sourced). With
  Weapon data Real the gun's hit test and the sourced blast radii are real (docs/real-weapons.md §1.4). Open: the
  real blast radii of the missiles / SAMs without a published lethal radius.
- **Imagery**: SPOT 5 outside Israel not started.
- **Multiplayer**: not started (missions 511–516, 666, 777), with its RWR network messages. Research and plan: [multiplayer.md](multiplayer.md).

## Decisions (agreed with the user)
- Airbase runway/apron underlay models stay hidden (the imagery shows the airbase) unless it stops looking good.
- Modern-imagery work may use GDAL as a setup dependency. Modern imagery defaults to the 1998 colours; "modern
  colours" is its own Extras switch.
- Keys: when an original command gets built, the original key wins; our own functions move to Ctrl+F-keys.
- The other camera views (padlock, back view, fly-by, weapon camera, external list) — done (docs/views.md); the wingman
  radio commands come with the AI combat work.
- Pilot records: our own JSON format with the same data as the original (Pilots.dat + Pilots\<id>.mis);
  no import of original files (maybe a converter later if easy).
- Screenshots (SysRQ): PNG, timestamped, in the user data folder (original: IafJets000.bmp in the game folder).
- Multiplayer (incl. the original's TCP/IP lobby mode): after the single-player game is finished.
- Mission Creator: single player built (2026-10-20); the multiplayer screen comes with multiplayer.
- Setup ends with one launcher you can click / call (a run script + a .desktop entry, on macOS an .app, with the
  game's icon from the CD). CI and release packages: not urgent.
- Every change from the original is listed in `docs/deviations.md`.
- Game logic from v1.1 only ("logic v1.1"); v1.0 data must still work. When a v1.1 fix makes one of ours redundant,
  ours is deleted. So far this happened only to the HUD: the projected FPM is v1.1's own, and with the original
  cockpit projection the v1.1 ladder matches the world near the marker; our conformal ladder stays an Extras option
  for the few px further out.
- Improvements over the original are opt-in switches, original by default: Physics tab (flight + gameplay bugs),
  Extras tab (visual / sound additions), Flight data (Original / Real).
- Rendering may be better: smooth text, 4× Lanczos art (never AI upscaling), fixed runway digits.
- In-flight subtitles stay English in Hebrew mode (no Hebrew source exists).
- g readout on the ground shows 1.0; the wheels follow our terrain (the original's runways are flat).
- Work order: by missions unlocked, not menu order.
