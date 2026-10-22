# Status — 2026-10-21

This page says what works today, what comes next and what is still open. Details live in the linked docs; plans
beyond the original are in [roadmap.md](roadmap.md), every difference from the original in
[deviations.md](deviations.md).

**Terms:** AA / AG = air-to-air / air-to-ground; AI = computer-controlled units; AoA = angle of attack; AWACS =
airborne early warning aircraft; CCIP = continuously computed impact point (bomb sight); DASH = the helmet sight; DLZ
= dynamic launch zone (missile range band); ECM = electronic countermeasures (jamming); EO = electro-optical (FLIR /
TV) sensor; FLIR = forward-looking infrared; FM = flight model; FPM = flight path marker; HARM = anti-radiation
missile; HUD = head-up display; ILS = instrument landing system; IR = infrared; LCOS = lead-computing optical sight
(gun sight); LOD = level of detail; MFD = multi-function display; MRM = medium-range missile; NAV = navigate (fly the
waypoints); PPI = plan position indicator (radar picture); RWR = radar warning receiver; SAM / AAA = surface-to-air
missile / anti-aircraft guns; STT = single-target track (radar lock); TSD = tactical situation display (map). OFF /
STBY / STT / BORE / LRS / TWS / ACM / GMT / MAP are the radar modes (radar.md).

## Where we are
- **Playable missions: 61 of 68 by the coverage report** (every feature they need is built; mission-coverage.md).
  - Flown end to end: 311, 312, 315 (bombing).
  - Checked in part: 313 / 322 ground fire; 134 (Delta flight dive-bombs and destroys both P-40 radars) and 406 (the
    AI wingman destroys its target). The player's own targets there were not flown.
  - Left: the 7 multiplayer missions (511–516, 777). 666 flies in single player as the Mission Creator's mission.
- **Flyable jets:** the Jet list's seven — F-15, F-16, F-4E, F-4 Kurnass 2000, Lavi, Kfir, Mirage (the Jet list or a
  mission's jet; aircraft.md §5); the MiG-23 / MiG-29 with their own cockpits wherever a mission puts the player in
  one (the Mission Creator does; no campaign mission does); our F-35I in one jet's slot (Extras, f35i.md). A mission
  whose player jet is any other type flies it as the F-16.
- **Game version: v1.1 logic**, with v1.1 data when setup is given the patch; v1.0 data still plays. Doc addresses
  are v1.1 (v1.1.md maps them to v1.0).
- Everything comes from the player's own ISO; the repo (github.com/assapir/iaf-reborn, GPL-3.0) holds no game data.

## Priorities (user decision: 1. player experience, 2. enemies, 3. missions and general fixes)
1. **Player experience:** built (Done table). Open: the stores that look detached (Small bugs).
2. **Enemies:** built (Done table, "AI combat"). Next, behind its own switches: "Better AI" (roadmap.md).
3. **Missions and general fixes:** the mission sweep (`tools/mission_sweep.sh`) and the small bugs below.

**Parked (roadmap.md):** imagery SPOT 5 outside Israel, better AI, sea level west of Suez, extra sounds, multiplayer,
modern aircraft / weapons, the Pi 5 profile.

## Small bugs (fix between jobs)
- **Mission sweep 2026-10-14** (`tools/mission_sweep.sh`: all 60 playable missions headless, the player parked
  300 s, then the targets destroyed):
  - No script errors; every mission passes once its targets die.
  - Lost early with the player idle: 114, 115, 116, 117, 122, 215, 223, 234, 236, 237, 402. Checked against the exe
    (2026-10-20): no deviation makes the enemy quicker.
    - 115, 215, 223, 234, 236, 237, 402 (and 117's helicopter path) are scripted kill shots. An event jumps a
      shooter's trigger list to miss shots, a wait and a kill shot (op 2 with 0x852 ≠ 0, `FUN_004aae40` →
      `FUN_004d6130`). The player is meant to kill the shooter in that window.
    - 114, 116, 117, 122 have interceptors (brain 13) whose primary target is the escorted jet. They shoot it down
      with AA-2s and guns; the escorted jets never fight back, as in the exe. The AI's missile q, blast damage,
      skill periods, Launch cone and gate match the exe (ai.md §13). The AI gun burst is the exe's 14 ticks (about
      2.6 s; it was 1 s before).
    - Open: only a run of the original would compare the interceptors' arrival times.
  - 132's "LEADER KILLED" and 132 / 133's "FRIENDLY HIT" end nothing in the exe either. Event ops only play, count,
    add debrief items and jump (`FUN_004ba7a1` → `FUN_004c3425`); only the role rules end a mission (`FUN_00599da0`).
    132 has two role-1 targets (the leader's jeep and the PHOTO SENSOR). The evNotDestroy debrief item of a unit
    still alive at the end (`FUN_004a63c0`, e.g. 132's "The terrorist leader escaped.") is built.
- **Stores look detached** (user report: "not in place" from behind):
  - The pylons are quads in each jet's model, edge-on and nearly invisible from ahead / behind / below, as in the
    original (weapons.md §2.2).
  - The TER (triple ejector rack) shoulder slots (2–3 bombs) hang at the pylon height ±Pilon sideways (original
    `FUN_0053c990`), so they touch the wing.
  - Checked: the stations sit on the model (F-16 tip rails at x ±4.78, airframe ±4.73; each single store's Pilon
    point on its station; test_arming.gd). The flat white fins seen from behind went with the Present scale /
    smoothing work.
  - Next: the user says which view is wrong (original vs better).
- **Lavi skin** (user report: "wrong"): checked — the texture is the original's `lavi_h.bmp`, and every model's UVs
  match the `.x` / `.xfr` exactly (formats/x.md). The plain brown nose top and the white-tinted glass are the
  original's.
- **`--smooth` bows the stadium** (`stationary/stdum_h/stadum_h`): its straight walls curve and the seats show. Seen in
  the UV check; open.
- **Tests hang under load:** in a full `tools/test.sh` run while other Godot runs are busy, a test (test_ui_smoke,
  test_damage, test_arming) sometimes hangs until the 300 s timeout with no output. Alone they pass every time (8/8 on
  2026-10-01). test.sh prints "FAIL timeout" and the last output lines: use them next time to find the cause.

## Done
| area | state |
|---|---|
| Setup | the setup wizard (`./setup`) and `tools/setup-cli.sh` run the same steps (`crates/iaf-setup`), only what changed (setup.md); ISO + `setup.esa` extraction; `iaf-patch` applies the official v1.1 patch (RTPatch) without Windows, before the Hebrew packs and every conversion; the Hebrew CD or packs; a desktop launcher (an .app on macOS); uninstall from the CD launcher; Scenery by kind (buildings and trees, buildings only, trees only; scenery.md §1.6); the wizard's expected size of `assets/` on Extras and Summary |
| v1.1 | v1.1.md (v1.0→v1.1 diff and address map); all of the flight model's changes (flight-model.md §16); outside it: HUD (FPM, 12 px/deg ladder on the marker, gun cross at GunRetPositionY), ejection throw straight up, training debrief → Jet list, event counter order / missing-entity skip / combat ops 21–22, landed handler on every landing; v1.1 rules of unported systems recorded (damage.md §4.4, front-end.md §17) |
| Front end | start-up straight to the main menu (the intro videos are not played: front-end.md §18); original screens, animations, sounds, music; training + campaign; Jet list; Jump In (front-end.md §13.11); the Reference screen with our pilot guides (§14); Mission Creator (single player, §19: all controls, RANDOM, LOAD / SAVE of the original's files (formats/mcr.md), FLY builds mission 0x29a as the exe, the By Kills score and the "… team won." headline; ours: its WIND / FROM combos, Extras "Mission Creator: Better"); Hebrew packs; QUIT box and credits roll; ours: the CD autorun launcher (Extras) |
| Mission editor | ours, a separate tool (`./mission-editor`, mission-editor.md): names, add / remove units, ground routes (motion op 16 Path), flights Alpha..Delta, the mission year (1966–1998: the year's map, bases, jets and warnings; red flights from a red base), the terrain height, the Fly and ground check (calibrated on the 131 original files), Fly from the editor (the TSD with the edited briefing, the debrief back to the editor); win and lose (units marked Target / Must survive, the pass / fail summary, the debrief headlines, the "can never pass" check); intel (units shown on the pilot's TSD, the intel preview, the briefing's model links) and randomness (a chance to appear and a start spread per unit or flight, rolled at each Fly, the roll preview); the sanity check (fuel for the route, a target SAM rings cover from every side, a route without points, a target no loadout can destroy); Duplicate, Copy / Paste of units; a year on another map moves the mission to that map's original; Remove for an enemy flight; the Scenario tab ("when X then Y" rules written as the original's events, slots, scripts and sensors; an AI flight that waits parked until a rule makes it take off, with our trigger op 40 run only for editor missions; mission-editor.md §18); the editor scene `game/editor/mission_editor.tscn` |
| Pilot records | screen 0 at startup (front-end.md §13): pilot list, Dossier (edit boxes, photo, rank, score, missions), Records / Kills / Losses, New / Remove / Login; each debriefed flight recorded (result, MissBonus, destroyed units as kills / losses, score multiplier), best-attempt score and rank, the briefing's "<rank> <name>"; Future Missions 2–7 locked until the previous pass; JSON in the user dir; the Debrief's DEBRIEFING / KILL TALLY / LOSSES pages |
| Preferences | the original 5 pages (Graphics, Sound, Keyboard, Devices, Gameplay) + our **Extras** and **Physics** (23 switches: 17 Better physics + 6 bug fixes) tabs and Graphics → MORE, EN + HE (front-end.md §12; our rows: §12.9, deviations.md §2) |
| Controls | original key table, rebinding on the Keyboard page, in-flight keys through the table; the retail cheats (controls.md §4); joystick (one device: stick / throttle / rudder axes per the Devices page, hat = snap views, buttons bound on the Keyboard page, menu/joy/*.joy), tested by the user on Linux (2026-10-20) and macOS (a T.Flight Hotas X, `SDL_JOYSTICK_MFI=0`); ours: Devices "Stick response" Soft centre and "Detent = MIL" |
| TSD / briefing | vector map, units, flights, waypoints, fly any flight, briefing texts and links (picture windows fit their bitmap whole and, as in the exe, do not zoom; ours: the mouse wheel scrolls the texts, front-end.md §12.9); the selected-unit label, the ruler (right-drag), the map keys; in flight (FlyTSD, views.md §1) the live battle, Fly into another formation's jet (any flyable type, the wingman's seat when the leader is down), Visit, Ctrl+P |
| Mission runtime | scripts, triggers, events, voices + subtitles, win / lose rules, mission boxes, debrief; player = the default (or chosen) flight's leader |
| Flight model | original ground + airborne logic ported line by line (flight-model.md §14–§15): envelope, stall, spin, landing / crash check, afterburner delay, gear / flaps / brakes, start rules, Gameplay prefs; the ground pedal as a stick event, the ground attitude's shake off the runway and on the belly, the map edge (EndWorld.wav, "Tornado" push-back) |
| Physics switches | 17 "Better physics" options (incl. fly-by-wire deep stall, ground effect, brake pitch, asymmetric stores, wind and turbulence with the runway into the wind (autopilot.md §2.4), engine spool-up per real engine; flight-model.md §10) + 6 original-bug fixes (falling-jet heading, enemies tougher on easy AI, lock threat, stores weight / tank fuel, bomb burst depth, collisions with hidden units / wrecks; deviations.md §2) |
| Real aircraft data | Real set for all seven flyable jets (six data sets: F-16, F-15C, F-4E / Kurnass 2000 shared, Kfir C7, Lavi, Mirage IIICJ): weights, thrust, drag, roll, fuel, stall, pedal steering, drag chute, the low-speed indicated airspeed fix (real-aircraft.md); the flight data loader reads the v1.1 files (`bdgen.dat`, `*gen.skp`, XOR-encoded); AI types: their own Real rows (real-aircraft.md §9); every type checked against public figures (`crates/iaf-flight/tests/validation.rs`) |
| AI flight | ai.md: the bdb brains (rule engine, conditions, sub-brains, combat ops 21 / 22) and the original's autopilot control loops fly every brain-controlled jet through the same flight model: routes with timed waypoints, formations, take-off from the hangar, go home and land, hold; the player's wingman follows the player; `ai.contacts()` for radar / RWR |
| AI combat | AAA, radar / IR SAMs, ground rockets (ai.md §14); AI jets and ground units with a brain lock the player, a site without one never does; AI air-to-air / air-to-ground, enemy flares / chaff, script ops 1 / 2 (ai.md §13, `game/ai/combat.gd`); the AI's ripple / rockets / laser bombs, Arming loads and stores on AI jets, action 430, STT locks, the player's ECM in the AI sensors (the original has no AI ECM), helicopters and scripted aircraft, turrets / dishes / rotors, AI systems damage and engine sound; the decoys' effect on missiles (weapons.md §10) |
| Autopilot | autopilot.md: A key off → level → NAV → off, lamp 8, HUD `AP LVL` / `AP NAV`, stick / rudder break-out, NAV = Fly2WayPt with waypoint sequencing, a land waypoint = the AI's go-home circuit and landing; 312's demonstration lands on the centreline (also with every Better physics switch on: unbalanced stores trimmed, §2.5) and the instructor's markers fire in both world scales (§3) |
| Player weapons | weapons.md: gun (LCOS / strafe pippers), IR seeker + missiles (shoot cue, AI afterburners seen past R/2), radar missiles (600 / 610: DLZ, MRM HUD sight, shoot cue, "SEC" row, STT DLZ ticks, semi-active rule), HARM / Shrike (590: the original HARM scan, Ctrl+Return steps targets; Extras HARM targets: Real), TV weapons (635 Maverick, 640 TV missile: guided motion, the camera riding the weapon, TRA / TER, HUD mode-7 diamond), bombs (MK-82/83/84, M117, CBU-87/97 cluster, laser bombs: guided, FLIR designation) and rockets (ZUNNI, LAU-61) with ripple, CCIP (terrain ray) / delayed release, jettison (tanks, then bombs); stores on the pylons, master / HUD modes, weight / drag, external fuel tanks, stores MFD page; chaff / flares; helmet sight DASH (§5.4); Extras "Weapon data: Real" (real-weapons.md) |
| Radar | radar.md: modes OFF / STBY / STT / BORE / LRS / TWS / ACM / GMT / MAP with the per-jet tables, scan, terrain line of sight, lock keys, MFD B-scope / PPI, HUD target box, slaves the IR seeker, feeds the gun range |
| Arming screen | original screen 0x1f (front-end.md §15): jet front views + stations, weapon list AA / AG / Misc, drag and drop with the per-station allowed counts, right-click, DEFAULT, CURRENT LOAD / MAX T.O.W., the original's blocking checks (overweight, wing balance) and "Use weapon load?"; the load goes on both jets of its flight, the player's and the AI's; Yes / DEFAULT also load table slots 7..10 (§15). What the loads unlock: mission-coverage.md (315 "Cold Steel" bombed end to end destroys all 7 targets, test_bomb_missions.gd) |
| Damage | damage.md: hits, blast formula, destruction, falling jets, explosions / smoke (water splash and ring, the fatal-hit fireball, two explosions at a falling unit's impact), systems damage, collisions, the friendly-hit voice |
| Eject | E ×3: seat, canopy, parachute and its swing, mission lost |
| Views | views.md: pause, On-The-Fly menu (GDI layout, Arial metrics and hit test as the exe; front-end.md §16.2), the in-flight render message box (§16.4), FlyTSD (Esc), time compression, the original cameras (snap views, free look, padlock, external / fly-by, radar target, threat, wingman, weapon); the cockpit camera is the original projection, so the HUD ladder lines up (cockpit.md "3D view") |
| Graphics / rendering | the Graphics page wired (terrain / object detail, effects, smoke trails, textured sky with the cloud layer, shadows, external stores; front-end.md §12.4); ours on Graphics → MORE (rendering.md): upscaling, the water shader (§1.3), night lights (the original's light points and cockpit darkening, §4–§5), night-vision goggles (Shift+N, §8), the detailed effects (§6), Detailed airbases (runway / taxiway / apron surface with markings at all ten iaf.ibx bases, §7), Ground textures (CC0 ambientCG asphalt, concrete and ground near the camera, §1.4), Model detail (CC0 surface detail on the original models up close, §9), Scenery (buildings and trees over the Survey 2 m photo, scenery.md; solid for the jets, weapons, sensors and the EO pick, damaged by blasts, §4; scenery targets set in the mission editor, with a stand-in model when Scenery is off, §5), the detailed F-16D model (aircraft-models.md), rolling wheels |
| Cockpit | all 9 original 2D cockpits (cockpit.md): round gauges, attitude indicators, vario / AoA tapes, HUD (11 colours, traced symbology incl. ILS and the waypoint marker), I-mode (F12: marks toward the aircraft out of view), panel lights; MFDs (mfd.md: radar incl. the MAP picture, TSD, RWR page, NAV, stores, damage, FLIR / TV with the EO camera, HARM); RWR (rwr.md: list, lights, sounds, MFD page / panel dial, F5 threat; Extras "RWR: Real" adds the radars searching the jet, rwr.md §7). Ours: Real HUD for every flyable jet and the MiGs (real-hud.md); the F-35I's modelled cockpit and built-in EOTS (f35i.md §3–§4); Better cockpit (Extras: deviations.md §2, cockpit.md "Better cockpit") |
| Aircraft models | all 22 models: moving parts per the original rules, gear, afterburner flame, canopy / pilot, damage visuals. Ours: the F-35I's gear doors, its wing pylons at the real stations 1 / 3 / 9 / 11 (f35i.md §3.1), rolling wheels (part-animation.md §2.2) |
| Sounds | original sound table: engine, gear, flaps, air brake, AoA tone, Betty warnings, touchdown, crash; volume sliders |
| Radio | radio.md: the phrase engine (word wavs + subtitle; the runway numbers the install lacks and World scale Real's runway letters from our TTS clips, game/extra/tower_numbers); the tower by itself on the ground (taxi / line up / hold / take-off) and Ctrl+T in the air (proceed to runway, cleared to land, gear not down, go around, taxi to hangar); wingman commands Alt+P/B/E/W/T/C on the AI wingman's brain; waypoint, airborne, landed, crashed, eject and kill reports; the AWACS contact calls |
| Terrain | all of `map.ptt` (levels 11..6 + all 51 insets, 2342 nodes) as a streamed quadtree with distance LOD to 200 km, level-6 heights with the original's inset interpolation, skirts; runway digits surveyed on every airbase (2 mirrored fixed); `terraintype.dat` surface types (water / rough / runway) feed the flight model; loaded behind the wait screen (formats/ptt.md), ≈ 3 s from Fly on an Iris Xe with no frame over 250 ms (rendering.md §1.5) |
| Terrain imagery | georeference (thin-plate spline, 610 control points, georef.md); Sentinel-2 10 m outside Israel and the Survey of Israel 2015 2 m over Israel, each in 1998 / modern colours, picked per region on Graphics → MORE; the Survey photo up to the airbases' footprints (imagery.md §3) |
| World scale Real 1:1 | world-scale.md (Extras → World scale), all nine steps: true-size models, jets, gear clearance and weapons; every airbase at its real place on its real main runway, with its mission units, markers and routes; the AI's final approach on the real centreline; the old site painted over, the new site's close-up ground warped from the old; the real runway designators (L / R, re-lettered taxi signs) and widths; ships at their real length; with Weapon data Real, the gun's hit test and the sourced blast radii (real-weapons.md §1.4) |
| Tests | `tools/test.sh`: Rust + 96 headless Godot tests (`tests/godot/test_*.gd`), isolated from the player's settings; fails on any script error or a 300 s timeout |

## Open gaps (by area)
Checked against the code on 2026-10-21 (each doc's own "not built" notes have the details).
- **Terrain**: the original data has no elevation west of Suez (flat −557 m, kept). A modern DEM (digital elevation
  model) is not built.
- **Flight**: the OutRunway force feedback; the map-edge console line (`FUN_0044a060`, flight-model.md §15.5a).
- **F-35I cockpit**: the panel pans as one flat picture, like the originals'; its side-stick and throttle are fixed
  in the render; the portals show the original MFD pages (pixel font) in the F-35 colours; looking 15–90° aside shows
  the panel strip's edge.
- **Controls**: one joypad (the first connected), as the original's one DirectInput device; no force feedback; chat
  is unhandled (multiplayer only; records 104–107, controls.md §3).
- **Pilot guide PDFs** (not urgent): some pictures land at the top of the next page above the following heading; one
  nearly empty page (F-16 "Not drawn"); the MFD pictures are the ~128 px original art scaled (blocky; Better cockpit's
  crisp MFD pages draw them sharp, mfd.md §8).
- **Pilot guide pictures**: the stamps' rule changed on 2026-10-20 (inputs only, no game code), so the next
  `tools/guide_shots.sh` renders all of them once. That render brings in 2026-10-19's changes: the F-16 / F-15 / Lavi
  Real HUD scales moved in (real-hud.md "What ours draws") and the Real AIM-9L's 10 NM range scale (real-weapons.md;
  the guides' text already says 16.1 km). New pictures since: the F-16's delayed CCIP, `hud_ccip_delay` /
  `hud_ccip_designated` (guides/f16.md §11).
- **World scale Real 1:1**: the real blast radii of the missiles / SAMs without a published lethal radius.
- **Setup wizard**: the pages wait for the user's review (roadmap.md).
- **Imagery**: SPOT 5 outside Israel not started.
- **Multiplayer**: not started (missions 511–516, 777), with its RWR network messages. Research and discussion:
  [multiplayer.md](multiplayer.md).

## Decisions (agreed with the user)
- Logic, layout, timing and colours follow the original. Improvements are opt-in switches, original by default:
  Physics tab (flight + gameplay bugs), Extras tab (visual / sound additions), Flight data (Original / Real). Every
  change from the original is listed in deviations.md.
- Game logic from v1.1 only; v1.0 data must still work. When a v1.1 fix makes one of ours redundant, ours is
  deleted. So far this happened only to the HUD: the projected FPM is v1.1's own, and with the original cockpit
  projection the v1.1 ladder matches the world near the marker; our conformal ladder stays an Extras option for the
  few px further out.
- Work order: by missions unlocked, not menu order.
- Airbase runway / apron underlay models stay hidden (the imagery shows the airbase) unless it stops looking good.
- Modern-imagery work may use GDAL as a setup dependency. Modern imagery defaults to the 1998 colours; "modern
  colours" is its own choice.
- Keys: when an original command gets built, the original key wins; our own functions move to Ctrl+F-keys.
- Pilot records: our own JSON format with the same data as the original (Pilots.dat + Pilots\<id>.mis); no import of
  original files (maybe a converter later if easy).
- Screenshots (SysRQ): PNG, timestamped, in the user data folder (original: IafJets000.bmp in the game folder).
- Multiplayer (incl. the original's TCP/IP lobby mode) is not approved; if it goes ahead, it comes after the
  single-player game is finished, with the Mission Creator's multiplayer screen (multiplayer.md §3.5).
- Setup ends with one launcher you can click / call (a run script + a .desktop entry, on macOS an .app, with the
  game's icon from the CD). CI and release packages: not urgent.
- Rendering may be better: smooth text, 4× Lanczos art (never AI upscaling), fixed runway digits.
- In-flight subtitles stay English in Hebrew mode (no Hebrew source exists).
- g readout on the ground shows 1.0; the wheels follow our terrain (the original's runways are flat).
