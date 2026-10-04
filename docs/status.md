# Status — 2026-10-02

## Where we are
- **Playable missions: 56 of 68 by the coverage report** (every feature they need is built; docs/mission-coverage.md).
  Flown end to end: 311, 312, 315 (bombing). Checked in part: 313 / 322 ground fire; 134 (Delta flight dive-bombs and
  destroys both P-40 radars) and 406 (the AI wingman destroys its target) — the player's own targets there were not
  flown. Left: multiplayer (8), brain-driven vehicles (2), motion op 5 (224), trigger op 1 (215).
- **Flyable jets: all seven of the Jet list** — F-15, F-16, F-4E, F-4 Kurnass 2000, Lavi, Kfir, Mirage (Jet list or a
  mission's jet; docs/aircraft.md §5). The MiGs are AI-only, as in the original; a mission whose player jet is another
  type flies it as the F-16.
- **Game version: v1.1 logic**, v1.1 data when setup is given the patch (`--patch`); v1.0 data still plays. Doc
  addresses are v1.1 (docs/v1.1.md maps them to v1.0). The flight model's v1.1 changes are all ported (docs/flight-model.md §16).
- Everything comes from the player's own ISO; the repo (github.com/assapir/iaf-reborn, GPL-3.0) holds no game data.
- Rule: logic, layout, timing and colours as the original. Improvements are opt-in switches, original by default.

## Priorities (user decision: 1. player experience, 2. enemies, 3. missions and general fixes)
**1. Player experience** (in order):
- ~~Radar contacts / lock / STT, HUD target box, IR missile slaved to the radar; chaff / flares (player side); Real
  weapon capabilities~~ — done (see Done).
- ~~Autopilot (A key; the AI control loops; Landing 312 approach mode)~~ — done (see Done; 312's demonstration lands on
  the centreline: docs/autopilot.md §3).
- ~~Cockpit camera = the original projection (HUD ladder lines up)~~ — done (docs/cockpit.md "3D view").
- ~~Views, time compression, pause / in-flight menu~~ — done (docs/views.md).
- ~~RWR (list, lights, sounds, MFD page / panel dial, F5 threat), radar MAP picture~~ — done (docs/rwr.md, docs/mfd.md
  §4); nothing locks the player until AI combat / SAMs. ~~Other MFD pages (FLIR / TV / HARM)~~ — done (docs/mfd.md;
  open: Open gaps → Cockpit / MFDs).
- Detached-looking stores.
- ~~Helmet sight DASH~~ — done (weapons.md §5.4: the helmet display in `Dash` 1 cockpits, the IR seeker off-boresight in
  free look / padlock within the generation cone).
- ~~Joystick / throttle / pedals~~ — done, untested on hardware (docs/controls.md §5).
- ~~Other jets flyable~~ — done: the Jet list's seven (tests/godot/test_jet_list.gd), the Kfir / Mirage shared data
  with Flight data = Original.

**2. Enemies:** ~~AAA, radar / IR SAMs, ground rockets~~ (done: docs/ai.md §14), the decoys' effect on missiles, AI air-to-air / air-to-ground (bomb ballistics), enemy
flares / chaff and decoy rules, script op 2, armed vehicles / boats; then the demo video (H.264).

**3. Missions and general fixes:** remaining small bugs below,
Jump In, remaining front-end screens, more weapons (radar missiles, TV / IR,
anti-radiation, laser guidance with the FLIR), night.

**PARKED (docs/roadmap.md):** imagery phase 2 (Survey of Israel 2 m conversion, SPOT 5), 1:1 world scale, better AI, cheats,
sea level west of Suez, extra sounds, multiplayer, setup wizard + launcher, modern aircraft / weapons, Pi 5 profile.

## Small bugs (fix between jobs)
- Stores look detached (user report: "not in place" from behind): the pylons are quads in each jet's model, edge-on
  and nearly invisible from ahead / behind / below, as in the original (docs/weapons.md §2.2), and the TER shoulder slots (2–3 bombs) hang at the pylon height ±Pilon sideways (original `FUN_0053c990`), so
  they touch the wing. Checked: the stations sit on the model (F-16 tip rails at x ±4.78, airframe ±4.73; each single
  store's Pilon point on its station; test_arming.gd). User to say which view is wrong (original vs better). (The flat
  white fins seen from behind are gone since the Present scale / smoothing work.)
- Lavi skin (user report: "wrong"): checked — the texture is the original's `lavi_h.bmp` and every model's UVs match
  the `.x` / `.xfr` exactly (docs/formats/x.md); the plain brown nose top and the white-tinted glass are the original's.
- `--smooth` bows the stadium (`stationary/stdum_h/stadum_h`): its straight walls curve and the seats show; seen in the
  UV check, not yet fixed.
- Tests: in a full `tools/test.sh` run while other Godot runs are busy (parallel jobs), a test (test_ui_smoke,
  test_damage, test_arming) occasionally hangs until the 300 s timeout with no output; alone they pass every time (8/8
  on 2026-10-01). test.sh now prints "FAIL timeout" and the last output lines — use that next time to find the cause.

## Done
| area | state |
|---|---|
| Setup | `tools/setup.sh [--patch <v1.1>] <ISO> [Hebrew packs]` builds everything; ISO + `setup.esa` extraction; `iaf-patch` applies the official v1.1 patch (RTPatch) without Windows, before the Hebrew packs and every conversion |
| v1.1 | `docs/v1.1.md` (v1.0→v1.1 diff and address map); the flight model's changes (docs/flight-model.md §16); outside it: HUD (FPM, 12 px/deg ladder on the marker, gun cross at GunRetPositionY), ejection throw straight up, training debrief → Jet list, event counter order / missing-entity skip / combat ops 21–22, landed handler on every landing; v1.1 rules of unported systems recorded (damage.md §4.4, front-end.md §17); docs and code comments on v1.1 addresses |
| Front end | original screens, animations, sounds, music; training + campaign; Jet list; Hebrew packs; QUIT box and credits roll |
| Terrain imagery | georeference (thin-plate spline, 610 control points, docs/georef.md); Sentinel-2 10 m layers outside Israel (1998 / modern colours, docs/imagery.md), picked per region on the Extras page; `setup.sh --imagery` (sentinel2; Survey of Israel sheets download only) |
| Preferences | original 5 pages (Graphics, Sound, Keyboard, Devices, Gameplay) + our **Extras** (flight data, weapon data, language, info line, blackbox, HUD pitch ladder, Real HUD (every jet's real HUD / sight / helmet display: docs/real-hud.md), all keys, window, anti-aliasing, terrain close up, sky — docs/rendering.md; imagery per region — docs/imagery.md; scrolls 8 rows at a time) and **Physics** (18 improvement switches, the Keyboard page's scrollbar, 15 rows shown) tabs, EN + HE; VSYNC (ours) on the Graphics page (docs/front-end.md §12) |
| Controls | original key table, rebinding on the Keyboard page, in-flight keys through the table; joystick (one device: stick / throttle / rudder axes per the Devices page, hat = snap views, buttons through the table and bound on the Keyboard page, menu/joy/*.joy), untested on hardware |
| TSD / briefing | vector map, units, flights, waypoints, fly any flight, briefing texts and links |
| Mission runtime | scripts, triggers, events, voices + subtitles, win / lose rules, mission boxes, debrief; player = the default (or chosen) flight's leader |
| Flight model | original ground + airborne logic ported line by line (docs/flight-model.md §14–§15): envelope, stall, spin, landing / crash check, afterburner delay, gear / flaps / brakes, start rules, Gameplay prefs |
| Physics switches | 12 "Better physics" options (incl. F-16 deep stall, ground effect; docs/flight-model.md §10) + 6 original-bug fixes (falling-jet heading, enemies tougher on easy AI, lock threat, stores weight / tank fuel, bomb burst depth, collisions with hidden units / wrecks; docs/deviations.md §2) |
| AI flight | docs/ai.md: the bdb brains (rule engine, conditions, sub-brains, combat ops 21 / 22) and the original's autopilot control loops fly every brain-controlled jet through the same flight model: routes with timed waypoints, formations, take-off from the hangar, go home and land, hold; the player's wingman follows the player; `ai.contacts()` for radar / RWR |
| Autopilot | docs/autopilot.md: A key off → level → NAV → off, lamp 8, HUD `AP LVL` / `AP NAV`, stick / rudder break-out, NAV = Fly2WayPt with waypoint sequencing, a land waypoint = the AI's go-home circuit and landing (312's demonstration lands on the centreline) |
| Player weapons | docs/weapons.md: gun (LCOS / strafe pippers), IR seeker + missiles, radar missiles (600 / 610: DLZ, MRM HUD sight, shoot cue, "SEC" row, STT DLZ ticks, semi-active rule), HARM / Shrike (590), TV weapons (635 Maverick, 640 TV missile: guided motion, the camera riding the weapon, TRA / TER, HUD mode-7 diamond), bombs (MK-82/83/84, M117, CBU-87/97 cluster, laser bombs: guided, FLIR designation) and rockets (ZUNNI, LAU-61) with ripple, CCIP / delayed release, jettison (tanks, then bombs); stores on the pylons, master / HUD modes, weight / drag, external fuel tanks, stores MFD page; Extras "Weapon data: Real" (docs/real-weapons.md) |
| Radar | docs/radar.md: modes OFF / STBY / STT / BORE / LRS / TWS / ACM / GMT / MAP with the per-jet tables, scan, terrain line of sight, lock keys, MFD B-scope / PPI, HUD target box, slaves the IR seeker, feeds the gun range; chaff / flares (docs/weapons.md §10) |
| Arming screen | original screen 0x1f (docs/front-end.md §15): jet front views + stations, weapon list AA / AG / Misc, drag and drop with the per-station allowed counts, right-click, DEFAULT, CURRENT LOAD / MAX T.O.W., the original's blocking checks (overweight, wing balance) and "Use weapon load?"; the load goes on the player's pylons (stores, weight / drag). What the loads unlock: docs/mission-coverage.md (315 "Cold Steel" bombed end to end destroys all 7 targets, test_bomb_missions.gd) |
| Real aircraft data | Real set for all seven flyable jets (six data sets: F-16, F-15C, F-4E / Kurnass 2000 shared, Kfir C7, Lavi, Mirage IIICJ): weights, thrust, drag, roll, fuel, stall, pedal steering, drag chute, the low-speed indicated airspeed fix (docs/real-aircraft.md); the flight data loader reads the v1.1 files (`bdgen.dat`, `*gen.skp`, XOR-encoded); AI types: their own Real rows, used by the AI jets (docs/real-aircraft.md §9) |
| Damage | docs/damage.md: hits, blast formula, destruction, falling jets, explosions / smoke, the player's systems damage, collisions |
| Eject | E ×3: seat, canopy, parachute, mission lost |
| Views | docs/views.md: pause, On-The-Fly menu, FlyTSD (Esc), time compression, the original cameras (snap views, free look, padlock, external / fly-by, radar target, threat, wingman, weapon) |
| Graphics / rendering | the Graphics page wired (terrain / object detail, effects, smoke trails, textured sky with the cloud layer, shadows, external stores; docs/front-end.md §12.4); Extras render options (docs/rendering.md) |
| Cockpit | all 9 original 2D cockpits (docs/cockpit.md): round gauges, attitude indicators, vario / AoA tapes, HUD (11 colours, traced symbology incl. ILS and the waypoint marker), panel lights; MFDs (docs/mfd.md: radar incl. the MAP picture, TSD, RWR page, NAV, stores, damage, FLIR / TV with the EO camera, HARM); RWR (docs/rwr.md); helmet sight DASH (docs/weapons.md §5.4) |
| Aircraft models | all 22 models: moving parts per the original rules, gear, afterburner flame, canopy / pilot, damage visuals |
| Sounds | original sound table: engine, gear, flaps, air brake, AoA tone, Betty warnings, touchdown, crash; volume sliders |
| Radio | docs/radio.md: the phrase engine (word wavs + subtitle); the tower by itself on the ground (taxi / line up / hold / take-off) and Ctrl+T in the air (proceed to runway, cleared to land, gear not down, go around, taxi to hangar; a click elsewhere); wingman commands Alt+P/B/E/W/T/C on the AI wingman's brain (its bdb "Roger" replies, "negative" when it cannot); waypoint and eject reports. Not yet: AWACS contact calls, airborne / landed / crashed / kill reports |
| Terrain | all of `map.ptt` (levels 11..6 + all 51 insets, 2342 nodes) as a streamed quadtree with distance LOD to 200 km, level-6 heights with the original's inset interpolation, skirts; runway digits surveyed on every airbase (2 mirrored fixed); `terraintype.dat` surface types (water / rough / runway) feed the flight model; loaded behind the wait screen (docs/formats/ptt.md) |
| Pilot records | screen 0 at startup (docs/front-end.md §13): pilot list, Dossier (edit boxes, photo, rank, score, missions), Records / Kills / Losses, New / Remove / Login; each debriefed flight recorded (result, MissBonus, destroyed units as kills / losses, score multiplier), best-attempt score and rank, the briefing's "<rank> <name>"; Future Missions 2–7 locked until the previous pass; JSON in the user dir. Not filled yet: kills / losses only from what the damage code destroys (no AI weapons / SAMs), the debrief page's own statistics |
| Tests | `tools/test.sh`: Rust + 57 headless Godot tests (`tests/godot/test_*.gd`), isolated from the player's settings; fails on any script error or a 300 s timeout |

## Open gaps (by area)
- **Terrain**: map-edge push-back / EndWorld and craters (terraintype bits known, systems missing); no elevation
  west of Suez in the original data (flat −557 m, kept).
- **Flight**: the seven Jet list jets fly (the two MiGs are AI-only, as in the original); systems damage acts on the flight model (AI jets take none); no hook, map-edge push-back.
- **Combat**: player gun, IR missiles, radar missiles (AMRAAM / Sparrow with the DLZ and the MRM sight), radar lock,
  chaff / flares, bombs (CCIP / delayed, ripple, cluster), rockets, HARM / Shrike at the HARM page's emitter, TV weapons (Maverick, TV missile), laser bombs with the FLIR designation (the ground units' sensors feed the RWR); AI combat built (docs/ai.md §13: sensors, Launch, weapon changes, every manoeuvre; not yet: the AI's bomb ripple, AI
  radar locks on the RWR, decoys from AI jets), ground fire built (docs/ai.md §14: AAA, SAMs, rockets; 313 and 322 playable); decoys don't lure missiles yet.
- **Cockpit / MFDs**: ECM, the full-screen weapon MFD (Z), the HUD range scale (weapons.md §12.4); the RWR's feeds (AI sensors, SAMs, enemy missiles);
  ECM light has no system; night lighting; what the TV / laser weapons do with the radar's designated point.
- **Controls**: joystick untested on real hardware (one device; no force feedback); not built: FlyTSD Fly into another
  aircraft / Visit (docs/views.md).
- **Sounds**: AI / moving-unit sounds (AI jets fly silently), Betty "Pull up"; the RWR's wait for something to
  lock the player (docs/sound.md §5).
- **Front end**: Reference screen content (docs/front-end.md §14), TSD 3D-model / target
  windows; Graphics prefs: no terrain resolution drop
  (docs/deviations.md §1); No wind / No malfunctions have no reader in the original either.
- **Eject details**: parachute landing.

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
- Jump In after the combat core (also useful for testing). Mission Creator much later.
- Setup ends with one launcher you can click / call (a run script + a .desktop entry, on macOS an .app, with the
  game's icon from the CD). CI and release packages: not urgent.
- Every change from the original is listed in `docs/deviations.md`.
- Game logic from v1.1 only ("logic v1.1"); v1.0 data must still work. A v1.1 fix that makes one of ours redundant → ours
  is deleted (so far only the HUD: the projected FPM is v1.1's own, and with the original cockpit projection the v1.1 ladder
  matches the world near the marker; our conformal ladder stays an Extras option for the few px further out).
- Improvements over the original are opt-in switches, original by default: Physics tab (flight + gameplay bugs),
  Extras tab (visual / sound additions), Flight data (Original / Real).
- Rendering may be better: smooth text, 4× Lanczos art (never AI upscaling), fixed runway digits.
- In-flight subtitles stay English in Hebrew mode (no Hebrew source exists).
- g readout on the ground shows 1.0; the wheels follow our terrain (the original's runways are flat).
- Work order: by missions unlocked, not menu order.
