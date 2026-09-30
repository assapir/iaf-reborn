# Status — 2026-09-30

## Where we are
- **Playable missions: 2 of 68** — Training "Engines ON" (311) and "Landing" (312), start to debrief.
- **Flyable jet: F-16 only.** Other jets have models and cockpits, but no flight data set yet.
- **Game version: v1.1 logic** (switch in progress, see below). Players with only v1.0 data must still be able to play.
- Everything comes from the player's own ISO; the repo (github.com/assapir/iaf-reborn, GPL-3.0) holds no game data.
- Rule: logic, layout, timing and colours as the original. Improvements are opt-in switches, original by default.

## In progress (running now)
| work | what | then |
|---|---|---|
| Cleanup | remaining ~30 over-engineering items (pure refactor) | — |
| v1.1 comparison | Ghidra on the v1.1 exe, v1.0→v1.1 function map, what changed in our ported systems → `docs/v1.1.md` | port the changes (below) |
| Real aircraft data | real-world data sets for all flyable jets → `docs/real-aircraft.md` | rename "Real F-16" → "Real aircraft" |

## To do next (in this order)
1. **Switch to v1.1**: patch step in `tools/setup.sh` (patch before the Hebrew pack; skip when no patch is given),
   port every v1.1 logic change in our systems, move doc addresses to v1.1, keep v1.0 data working, delete our
   fixes that v1.1 makes redundant.
2. **Terrain (original data)**: the whole theatre (levels 6–11: today there is *no ground* outside the Israel
   rectangle), the remaining insets (foreign airbases, target areas, level 3), decode `terraintype.dat` (water /
   rough / runway), load terrain behind the loading screen.
3. **Combat core** (unlocks the first ~9–11 missions): AI brain flight → player gun + IR missiles, stores on the
   pylons → AI air-to-ground / air-to-air → AAA, radar SAMs, RWR → script ops 2 / 21 / 22.
4. **Bombs + CCIP**, armed vehicles / boats (→ ~20 missions).
5. **Other jets**: flight data + cockpit per jet — Phantom 2000 (19 missions), F-4E (17), F-15 (16), Lavi / Mirage
   (13), Kfir (8).
6. Radar missiles with lock, IR SAMs, TV / IR-guided weapons, night, anti-radiation missiles, rockets.
7. Arming screen, pilot records / unlocking, remaining front-end screens, multiplayer.
8. Joystick / throttle / pedals (original input handling; Devices page).
9. Later (docs/roadmap.md): Better AI, Real weapons, Extra sounds, mission replayer, 3D cockpit, satellite imagery,
   canopy open.

Order source: `docs/mission-coverage.md` (greedy "most missions unlocked"), user decisions.

## Done
| area | state |
|---|---|
| Setup | `tools/setup.sh <ISO> [Hebrew packs]` builds everything; ISO + `setup.esa` extraction; `iaf-patch` applies the official v1.1 patch (RTPatch) without Windows |
| Front end | original screens, animations, sounds, music; training + campaign; Jet list; Hebrew packs |
| Preferences | original 5 pages (Graphics, Sound, Keyboard, Devices, Gameplay) + our **Extras** (flight data, language, info line, blackbox) and **Physics** (14 improvement switches) tabs, EN + HE |
| Controls | original key table, rebinding on the Keyboard page, in-flight keys through the table (keyboard only) |
| TSD / briefing | vector map, units, flights, waypoints, fly any flight, briefing texts and links |
| Mission runtime | scripts, triggers, events, voices + subtitles, win / lose rules, mission boxes, debrief; player = the default (or chosen) flight's leader |
| Flight model | original ground + airborne logic ported line by line (docs/flight-model.md §14–§15): envelope, stall, spin, landing / crash check, afterburner delay, gear / flaps / brakes, start rules, Gameplay prefs |
| Physics switches | 12 "Better physics" options (incl. F-16 deep stall, ground effect) + 2 original-bug fixes (falling-jet heading, enemies tougher on easy AI) |
| Real F-16 data | real weights, thrust, roll, fuel, stall; pedal nose-wheel steering |
| Damage | original damage model: hits, blast formula, destruction, falling jets, explosions / smoke, the player's systems damage, collisions |
| Eject | E ×3: seat, canopy, parachute, mission lost |
| Cockpit | all 9 original 2D cockpits, gauges, HUD (11 colours), panel lights, MFDs (radar, TSD, RWR, NAV, stores, damage) |
| Aircraft models | all 22 models: moving parts per the original rules, gear, afterburner flame, canopy / pilot, damage visuals |
| Sounds | original sound table: engine, gear, flaps, air brake, AoA tone, Betty warnings, touchdown, crash; volume sliders |
| Terrain | Israel rectangle (level 4) with heights + 149 airbase detail tiles; mirrored runway digits fixed |
| Tests | `tools/test.sh`: Rust + 16 headless Godot tests, isolated from the player's settings; fails on any script error |

## Open gaps (by area)
- **Terrain**: no ground outside the Israel rectangle; foreign / target insets missing; no terrain types; visible
  loading after the cockpit appears.
- **Flight**: only the F-16; systems damage doesn't affect flying yet; no hook, map-edge push-back, water / rough crashes.
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
- Game logic from v1.1 only; v1.0 data must still work. A v1.1 fix that makes one of ours redundant → ours is deleted.
- Improvements over the original are opt-in switches, original by default: Physics tab (flight + gameplay bugs),
  Extras tab (visual / sound additions), Flight data (Original / Real).
- Rendering may be better: smooth text, 4× Lanczos art (never AI upscaling), fixed runway digits.
- In-flight subtitles stay English in Hebrew mode (no Hebrew source exists).
- g readout on the ground shows 1.0; the wheels follow our terrain (the original's runways are flat).
- Work order: by missions unlocked, not menu order.
