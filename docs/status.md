# Status — 2026-09-30

## Where we are
- **Playable missions: 2 of 68** — Training "Engines ON" (311) and "Landing" (312), start to debrief.
- **Flyable jet: F-16 only.** Other jets have models and cockpits, but no flight data set yet.
- **Game version: v1.1 logic**, v1.1 data when setup is given the patch (`--patch`); v1.0 data still plays. Doc
  addresses are v1.1 (docs/v1.1.md maps them to v1.0). Flight model v1.1 port in progress.
- Everything comes from the player's own ISO; the repo (github.com/assapir/iaf-reborn, GPL-3.0) holds no game data.
- Rule: logic, layout, timing and colours as the original. Improvements are opt-in switches, original by default.

## In progress (one job at a time)
— (terrain finished; next: item 2)

## To do next (ordered by overall progress: missions unlocked first)
1. ~~Terrain (original data) — convert all of `map.ptt`~~ — done (see Done).
2. **Combat core** (unlocks the first ~9–11 missions): player weapons first (gun + IR missiles, stores on the
   pylons, the weapon HUD / MFD pages; targets already take damage; its own Extras switch "Weapon data: Original /
   Real" (separate from Flight data), public data per weapon, docs/roadmap.md "Real weapons") → AI brain flight → AI air-to-ground /
   air-to-air → AAA, radar SAMs, RWR → script ops 2 / 21 / 22.
3. **Arming screen** (right after weapons; 9 missions need a different loadout): port whatever the original enforces
   (per-station counts, CURRENT LOAD vs MAX T.O.W.; if it does not block overweight loads, "Enforce max take-off
   weight" becomes an Extras option).
4. **Bombs + CCIP**, armed vehicles / boats (→ ~20 missions).
5. **Other jets**: flight data + cockpit per jet — Phantom 2000 (19 missions), F-4E (17), F-15 (16), Lavi / Mirage
   (13), Kfir (8) (→ ~30 more missions).
6. Radar missiles with lock, IR SAMs, TV / IR-guided weapons, night, anti-radiation missiles, rockets.
7. Smaller items (no missions unlocked; fit in between milestones): **autopilot** (A key, incl. the approach mode
   of Landing 312), **cockpit camera = the original projection** (HUD ladder lines up; drop the conformal option if
   redundant) + Tu-22 Real row (the variant flown in the missions), **pilot records** / login / unlocking.
8. Remaining front-end screens, multiplayer.
9. Joystick / throttle / pedals (original input handling; Devices page).
10. **Original cheats / hidden keys** (docs/controls.md §4; live in the retail exe, the keys.trx labels are wrong):
   Shift+F refuel internal tank, Shift+S safety off (fire with gear down), Shift+R reload weapons (single player),
   Shift+D mission text messages on/off, Ctrl+W re-read weapons.ibx, U RWR page, Ctrl+Return HARM target step,
   SysRQ screenshot (IafJets000.bmp…); port them (cheats behind an Extras "Cheats" switch), show corrected labels
11. **Sea level west of Suez**: map.ptt has no elevation there (sea, Nile delta and Western desert are a flat plane
   at −557 m, ships placed at −557 m); kept as the original for now — decide a fix (e.g. shift that plane and its
   objects to 0 m) later.
12. Later (docs/roadmap.md): Better AI, Real weapons, Extra sounds, mission replayer, 3D cockpit, satellite imagery,
   canopy open.

Order source: `docs/mission-coverage.md` (greedy "most missions unlocked"), user decisions.

## Small bugs (fix between jobs)
- Keyboard page: the scrollbar arrows are cropped on the right side.

## Done
| area | state |
|---|---|
| Setup | `tools/setup.sh [--patch <v1.1>] <ISO> [Hebrew packs]` builds everything; ISO + `setup.esa` extraction; `iaf-patch` applies the official v1.1 patch (RTPatch) without Windows, before the Hebrew packs and every conversion |
| v1.1 | `docs/v1.1.md` (v1.0→v1.1 diff and address map); ported outside the flight model: HUD (FPM, 12 px/deg ladder on the marker, gun cross at GunRetPositionY), ejection throw straight up, training debrief → Jet list, event counter order / missing-entity skip / combat ops 21–22, landed handler on every landing; v1.1 rules of unported systems recorded (damage.md §4.4, front-end.md §17); docs and code comments on v1.1 addresses |
| Front end | original screens, animations, sounds, music; training + campaign; Jet list; Hebrew packs |
| Preferences | original 5 pages (Graphics, Sound, Keyboard, Devices, Gameplay) + our **Extras** (flight data, language, info line, blackbox, HUD pitch ladder) and **Physics** (14 improvement switches) tabs, EN + HE |
| Controls | original key table, rebinding on the Keyboard page, in-flight keys through the table (keyboard only) |
| TSD / briefing | vector map, units, flights, waypoints, fly any flight, briefing texts and links |
| Mission runtime | scripts, triggers, events, voices + subtitles, win / lose rules, mission boxes, debrief; player = the default (or chosen) flight's leader |
| Flight model | original ground + airborne logic ported line by line (docs/flight-model.md §14–§15): envelope, stall, spin, landing / crash check, afterburner delay, gear / flaps / brakes, start rules, Gameplay prefs |
| Physics switches | 12 "Better physics" options (incl. F-16 deep stall, ground effect) + 2 original-bug fixes (falling-jet heading, enemies tougher on easy AI) |
| Real aircraft data | Real set for all 6 flyable jets (F-16, F-15C, F-4E / Kurnass 2000, Kfir C7, Lavi, Mirage IIICJ): weights, thrust, drag, roll, fuel, stall, pedal steering (docs/real-aircraft.md); the flight data loader reads the v1.1 files (`bdgen.dat`, `*gen.skp`, XOR-encoded); AI types: reference table only |
| Damage | original damage model: hits, blast formula, destruction, falling jets, explosions / smoke, the player's systems damage, collisions |
| Eject | E ×3: seat, canopy, parachute, mission lost |
| Cockpit | all 9 original 2D cockpits, gauges, HUD (11 colours), panel lights, MFDs (radar, TSD, RWR, NAV, stores, damage) |
| Aircraft models | all 22 models: moving parts per the original rules, gear, afterburner flame, canopy / pilot, damage visuals |
| Sounds | original sound table: engine, gear, flaps, air brake, AoA tone, Betty warnings, touchdown, crash; volume sliders |
| Terrain | all of `map.ptt` (levels 11..6 + all 51 insets, 2342 nodes) as a streamed quadtree with distance LOD to 200 km, level-6 heights with the original's inset interpolation, skirts; runway digits surveyed on every airbase (2 mirrored fixed); `terraintype.dat` surface types (water / rough / runway) feed the flight model; loaded behind the wait screen (docs/formats/ptt.md) |
| Tests | `tools/test.sh`: Rust + 20 headless Godot tests, isolated from the player's settings; fails on any script error |

## Open gaps (by area)
- **Terrain**: map-edge push-back / EndWorld and craters (terraintype bits known, systems missing); no elevation
  west of Suez in the original data (flat −557 m, kept).
- **Flight**: only the F-16; systems damage doesn't affect flying yet; no hook, map-edge push-back.
- **Combat**: no weapons, no AI flight or combat, no AAA / SAMs (so no combat mission can be won).
- **Cockpit / MFDs**: radar contacts and lock, radar map, RWR threats, weapon pages, NAV distances; AI / SAM / ECM /
  autopilot lights have no systems; night lighting.
- **Controls**: no joystick; not built: views other than cockpit / chase, autopilot, time compression, pause
  (Ctrl+P) and the in-flight menu (Ctrl+O), in-flight TSD.
- **Sounds**: damage / RWR / weapon / AI sounds wait for those systems.
- **Front end**: pilot records and mission unlocking, Reference, Arming, QUIT confirmation, TSD 3D-model / target
  windows; most stored prefs have no effect yet.
- **Eject details**: the original fly-by camera, callsign in the radio call, parachute landing.

## Decisions (agreed with the user)
- Every change from the original is listed in `docs/deviations.md`.
- Game logic from v1.1 only ("logic v1.1"); v1.0 data must still work. A v1.1 fix that makes one of ours redundant → ours
  is deleted (so far only the HUD: the projected FPM is v1.1's own, the conformal ladder became an Extras option).
- Improvements over the original are opt-in switches, original by default: Physics tab (flight + gameplay bugs),
  Extras tab (visual / sound additions), Flight data (Original / Real).
- Rendering may be better: smooth text, 4× Lanczos art (never AI upscaling), fixed runway digits.
- In-flight subtitles stay English in Hebrew mode (no Hebrew source exists).
- g readout on the ground shows 1.0; the wheels follow our terrain (the original's runways are flat).
- Work order: by missions unlocked, not menu order.
