# Status — 2026-10-01

## Where we are
- **Playable missions: 2 of 68** — Training "Engines ON" (311) and "Landing" (312), start to debrief.
- **Flyable jet: F-16 only.** Other jets have models and cockpits, but no flight data set yet.
- **Game version: v1.1 logic**, v1.1 data when setup is given the patch (`--patch`); v1.0 data still plays. Doc
  addresses are v1.1 (docs/v1.1.md maps them to v1.0). Flight model v1.1 port in progress.
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
  §4); nothing locks the player until AI combat / SAMs. Other MFD pages (FLIR / TV / HARM).
- Detached-looking stores.
- ~~Joystick / throttle / pedals~~ — done, untested on hardware (docs/controls.md §5).
- Other jets flyable (Phantom 2000, F-4E, F-15, …): flight data + cockpit each (incl. the Kfir / Mirage shared
  data per the Flight data switch — only matters once they fly).

**2. Enemies:** AI air-to-air / air-to-ground (bomb ballistics), AAA, radar / IR SAMs with RWR threats, enemy
flares / chaff and decoy rules, script op 2, armed vehicles / boats; then the demo video (H.264).

**3. Missions and general fixes:** remaining small bugs below, player flight by
formation id, Jump In, remaining front-end screens, more weapons (radar missiles, TV / IR,
anti-radiation, rockets), night.

**PARKED (docs/roadmap.md):** modern imagery outside Israel + georeference, 1:1 world scale, better AI, cheats,
sea level west of Suez, extra sounds, multiplayer, setup wizard + launcher, modern aircraft / weapons, Pi 5 profile.

## Small bugs (fix between jobs)
- Stores look detached: no pylon models drawn (stores float under the wing), triple-rack side bombs touch the wing
  (original formula). (The flat white fins seen from behind are gone since the Present scale / smoothing work.)
- Kfir / Mirage data: the original loads one shared block (the second type flies on the first's data) — do that
  with Flight data = Original; each jet's own section only with Flight data = Real (user decision).

- Stores seen from behind (user report: "not in place"): checked — the stations sit on the model (F-16 tip rails at
  x ±4.78, airframe ±4.73; each single store's Pilon point on its station; test_arming.gd). What can look wrong: the
  TER shoulder slots (2–3 bombs) hang at the pylon height ±Pilon sideways (original `FUN_0053c990`), so they touch
  the wing. User to say which view is wrong (original vs better).
- Tests: in a full `tools/test.sh` run while other Godot runs are busy (parallel jobs), a test (test_ui_smoke,
  test_damage, test_arming) occasionally hangs until the 300 s timeout with no output; alone they pass every time (8/8
  on 2026-10-01). test.sh now prints "FAIL timeout" and the last output lines — use that next time to find the cause.

## Done
| area | state |
|---|---|
| Setup | `tools/setup.sh [--patch <v1.1>] <ISO> [Hebrew packs]` builds everything; ISO + `setup.esa` extraction; `iaf-patch` applies the official v1.1 patch (RTPatch) without Windows, before the Hebrew packs and every conversion |
| v1.1 | `docs/v1.1.md` (v1.0→v1.1 diff and address map); ported outside the flight model: HUD (FPM, 12 px/deg ladder on the marker, gun cross at GunRetPositionY), ejection throw straight up, training debrief → Jet list, event counter order / missing-entity skip / combat ops 21–22, landed handler on every landing; v1.1 rules of unported systems recorded (damage.md §4.4, front-end.md §17); docs and code comments on v1.1 addresses |
| Front end | original screens, animations, sounds, music; training + campaign; Jet list; Hebrew packs |
| Preferences | original 5 pages (Graphics, Sound, Keyboard, Devices, Gameplay) + our **Extras** (flight data, weapon data, language, info line, blackbox, HUD pitch ladder, all keys, window) and **Physics** (16 improvement switches, the Keyboard page's scrollbar once there are more than 15) tabs, EN + HE |
| Controls | original key table, rebinding on the Keyboard page, in-flight keys through the table; joystick (one device: stick / throttle / rudder axes per the Devices page, hat = snap views, buttons through the table and bound on the Keyboard page, menu/joy/*.joy), untested on hardware |
| TSD / briefing | vector map, units, flights, waypoints, fly any flight, briefing texts and links |
| Mission runtime | scripts, triggers, events, voices + subtitles, win / lose rules, mission boxes, debrief; player = the default (or chosen) flight's leader |
| Flight model | original ground + airborne logic ported line by line (docs/flight-model.md §14–§15): envelope, stall, spin, landing / crash check, afterburner delay, gear / flaps / brakes, start rules, Gameplay prefs |
| Physics switches | 12 "Better physics" options (incl. F-16 deep stall, ground effect) + 3 original-bug fixes (falling-jet heading, enemies tougher on easy AI, stores weight / tank fuel) |
| AI flight | docs/ai.md: the bdb brains (rule engine, conditions, sub-brains, combat ops 21 / 22) and the original's autopilot control loops fly every brain-controlled jet through the same flight model (all AI types, Original / Real data, the FM's AI rules): routes with timed waypoints, close / tactical formation, take-off from the hangar (taxi, pivot turns, rotation), go home and land (left-hand pattern, 6° final, roll-out, taxi to a hangar, engine off), hold, straight; the player's wingman follows the player; `ai.contacts()` for radar / RWR |
| Autopilot | docs/autopilot.md: A key off → level → NAV → off, on at an airborne start, lamp 8, HUD `AP LVL` / `AP NAV`, stick / rudder break-out at ±51 %, throttle keys dropped in NAV and re-synced on exit; level = wings level + heading / flight-path hold (no autothrottle), NAV = Fly2WayPt to the current waypoint with the waypoint sequencing (`FUN_00452960`), a land waypoint = the AI's go-home circuit and landing (312's demonstration); the AI's control loops, the player's FM rules |
| Player weapons | gun (0.2 s timer, analytic rounds, 25 / 50 m hit sphere, candidate list, muzzle flash, sounds, LCOS / strafe pippers), IR seeker + missiles (per-generation lock, tones, q, dog / proportional chase), stores on the pylons, selection / master / HUD modes, release, weight / drag, external fuel tanks + jettison, HUD weapon line / missile circle / seeker diamond, stores MFD page; Extras "Weapon data: Real" (docs/weapons.md, docs/real-weapons.md) |
| Radar | docs/radar.md: the player's radar (OFF / STBY / STT / BORE / LRS / TWS / ACM / GMT / MAP, per-jet tables, 2 s scan, 60° cone, terrain line of sight, 15 contacts, lock keys, STT track + auto-range), MFD B-scope / PPI symbols, HUD target box and "R" range, slaves the IR seeker, feeds the gun / LCOS range; chaff / flares (keys, counters, decoy flight); Real: F-16 APG-68 range, missile rear-aspect / cone / g |
| Arming screen | original screen 0x1f (docs/front-end.md §15): jet front views + stations, weapon list AA / AG / Misc, drag and drop with the per-station allowed counts, right-click, DEFAULT, CURRENT LOAD / MAX T.O.W., the original's blocking checks (overweight, wing balance) and "Use weapon load?"; the load goes on the player's pylons (stores, weight / drag). Coverage: of the 9 missions whose default load cannot kill the targets (116, 122, 136, 212, 214, 215, 216, 227, 237), 8 now need a player weapon instead of the AI (bombs for 215 / 227 / 237, bombs / rockets / guided for the rest; 136 has none loadable); none becomes playable before the bombs |
| Real aircraft data | Real set for all 6 flyable jets (F-16, F-15C, F-4E / Kurnass 2000, Kfir C7, Lavi, Mirage IIICJ): weights, thrust, drag, roll, fuel, stall, pedal steering (docs/real-aircraft.md); the flight data loader reads the v1.1 files (`bdgen.dat`, `*gen.skp`, XOR-encoded); AI types: reference table only |
| Damage | original damage model: hits, blast formula, destruction, falling jets, explosions / smoke, the player's systems damage, collisions |
| Eject | E ×3: seat, canopy, parachute, mission lost |
| Cockpit | all 9 original 2D cockpits, gauges, HUD (11 colours), panel lights, MFDs (radar incl. the MAP ground picture, TSD, RWR page and panel dial, NAV, stores, damage); RWR (docs/rwr.md) |
| Aircraft models | all 22 models: moving parts per the original rules, gear, afterburner flame, canopy / pilot, damage visuals |
| Sounds | original sound table: engine, gear, flaps, air brake, AoA tone, Betty warnings, touchdown, crash; volume sliders |
| Terrain | all of `map.ptt` (levels 11..6 + all 51 insets, 2342 nodes) as a streamed quadtree with distance LOD to 200 km, level-6 heights with the original's inset interpolation, skirts; runway digits surveyed on every airbase (2 mirrored fixed); `terraintype.dat` surface types (water / rough / runway) feed the flight model; loaded behind the wait screen (docs/formats/ptt.md) |
| Pilot records | screen 0 at startup (docs/front-end.md §13): pilot list, Dossier (edit boxes, photo, rank, score, missions), Records / Kills / Losses, New / Remove / Login; each debriefed flight recorded (result, MissBonus, destroyed units as kills / losses, score multiplier), best-attempt score and rank, the briefing's "<rank> <name>"; Future Missions 2–7 locked until the previous pass; JSON in the user dir. Not filled yet: kills / losses only from what the damage code destroys (no AI weapons / SAMs), the debrief page's own statistics |
| Tests | `tools/test.sh`: Rust + 34 headless Godot tests, isolated from the player's settings; fails on any script error |

## Open gaps (by area)
- **Terrain**: map-edge push-back / EndWorld and craters (terraintype bits known, systems missing); no elevation
  west of Suez in the original data (flat −557 m, kept).
- **Flight**: only the F-16; systems damage doesn't affect flying yet; no hook, map-edge push-back.
- **Combat**: player gun, IR missiles, radar lock, chaff / flares (no bombs, rockets, radar missiles, TV / laser,
  HARM); no AI combat (AI jets fly, don't fight), no AAA / SAMs (so no combat mission can be won yet).
- **Cockpit / MFDs**: ECM, FLIR / TV / HARM pages, NAV distances; the RWR's feeds (AI sensors, SAMs, enemy missiles);
  ECM light has no system; night lighting; what uses the radar's designated point.
- **Controls**: joystick untested on real hardware (one device; no force feedback); not built: the EO weapon camera, FlyTSD Fly into another
  aircraft / Visit (docs/views.md).
- **Sounds**: weapon / AI sounds wait for those systems (the RWR's wait for something to lock the player).
- **Front end**: Reference, QUIT confirmation, TSD 3D-model / target
  windows; most stored prefs have no effect yet.
- **Eject details**: callsign in the radio call, parachute landing.

## Decisions (agreed with the user)
- Airbase runway/apron underlay models stay hidden (the imagery shows the airbase) unless it stops looking good.
- Modern-imagery work may use GDAL as a setup dependency. Modern imagery defaults to the 1998 colours; "modern
  colours" is its own Extras switch.
- Keys: when an original command gets built, the original key wins; our own functions move to Ctrl+F-keys.
- The other camera views (padlock, back view, fly-by, weapon camera, external list) and the wingman radio commands
  are ported with the AI work.
- Pilot records: our own JSON format with the same data as the original (Pilots.dat + Pilots\<id>.mis);
  no import of original files (maybe a converter later if easy).
- Screenshots (SysRQ): PNG, timestamped, in the user data folder (original: IafJets000.bmp in the game folder).
- Multiplayer (incl. the original's TCP/IP lobby mode): after the single-player game is finished.
- Jump In after the combat core (also useful for testing). Mission Creator much later.
- Setup ends with one launcher you can click / call (a run script + a .desktop entry with the game's icon from the
  CD; macOS: an .app later). CI and release packages: not urgent.
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
