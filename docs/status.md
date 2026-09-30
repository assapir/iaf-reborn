# Status — checkpoint 2

Milestone 1: **start the game → Training → Basic → "Engines ON" (311) → briefing / TSD → take off from Ramat David
→ "Mission Accomplished!" → debrief**, in the original F-16 with the original 2D cockpit, everything extracted from the
original data. **Playable end to end** (`tools/test.sh` covers it).

Rule of the project: logic, layout, timing and colours follow the original exactly (from its data or its exe); rendering
may be better (smooth text, Lanczos upscaling). Deviations and "better physics" choices are decided with the user and
listed below.

## Done (working, committed, tested where noted)
| area | state |
|---|---|
| **Pipeline** | `tools/setup.sh <ISO> [Brief.zip Menu.zip]`: extraction, models, all 9 cockpits, fonts, menus (+ Hebrew pack), briefings, missions, object models, terrain + airbase detail, Godot extension |
| Install extraction | ISO 9660 + EA `setup.esa` (PKWARE DCL) → `assets/install` (docs/formats/esa.md) |
| Aircraft models | `.x/.xfr` → glTF, Lanczos 4× textures, smoothing (docs/formats/x.md); moving parts with the original hinge rules (docs/part-animation.md) |
| Terrain | `map.ptt` imagery + heights, chunk streaming, original georeference (docs/formats/ptt.md); **airbase detail tiles** from the level 0–2 insets (~1.24 m/px, 149 tiles, streamed within 6 km) |
| Mission objects | every entity of the mission + base missions with its original model (bdb object → Present → `.x`, 219 models); hidden / moved by the mission scripts |
| **Mission runtime** | generic (docs/mission-runtime.md): timer queue, trigger/motion scripts, 4 s reached/left checks, events (max count, voice + subtitle, debrief notes, script jumps), role win/lose rules, "Mission Accomplished!" / "Mission failed." box (DEBRIEF / CONTINUE / EXIT), Esc "quit mission?", debrief screen (headline + notes, Replay / New / Next). Instructor voices from `resource/soundfiles`. Tested: Engines ON start to finish |
| Subtitles | the original console: 40 slots, empty line every 3 s of sim time, newest 14 drawn (~40 s lifetime), x=4 y=10+15n, Arial 12/4, HUD colour; English only (no Hebrew exists — user decision) |
| **Flight model** | Rust port (docs/flight-model.md), audited against the exe (§14): envelope on the ground, flaps, friction 0.05, brake flag, nose-wheel side force (stick X), 5 Hz touchdown / lift-off / stop rule, aero update re-bases the acceleration; engine off at a ground start ("1" starts it); gear lever rules (no gear-up on the ground, no gear-down > 300 kt); **original / real data sets** (Preferences); validation suite vs public F-16 data |
| Real data set | real F-16 weights / thrust / roll / fuel / stall; geometric pedal nose-wheel steering; no ×4 ground-lift quirk; lift-off ~159 kt |
| Blackout / redout | original accumulators and tunnel / red overlays, "Over G" voice and G sound; "No blackouts" option (on our stand-in Preferences page for now) |
| Cockpit | original 2D panels of all cockpits from `cockpit.ibx`, gauges, ADI, standby horizon, conformal HUD in the original HUD colour table (H cycles 11 colours) |
| **MFDs** | generic per cockpit (placement and default pages from the ini): radar (B-scope, horizon bars, range), TSD (map.emf, heading-up, route), RWR, MENU, NAV, stores, damage, ADI; OSB clicks; keys T / D / Q / R / S / . / , / W (docs/mfd.md) |
| **Panel lights** | all cockpits (docs/cockpit.md): gear lamps per leg (grey up / red moving 2 s / green locked) + animated gear handle, flaps lamp, air brake, blink rule |
| Controls | original keys from the default key table (0x647ff8) and the instructor texts: 1–8 throttle presets (1 starts the engine), 0 / 9 throttle ±5 %, B brakes, G gear, F flaps, arrows stick (← → steer on the ground), Ins / Del rudder, MFD / radar / waypoint keys, H HUD colour |
| **Front end** | original screens / buttons / animations / sounds / music (docs/front-end.md), training + campaign navigation, Jet list with per-mission locks, Hebrew via the community packs |
| **TSD** | EMF vector map (+ grid / text), units (known flag, icons, sides, headings), flights and default flight, waypoints (drag to edit, route goes to the flight), double-click a leader to fly, zoom / scrollbars, mission title / clock, briefing window with links (lesson RTF, instructor card), message boxes |
| Briefings | RTF with colours → BBCode (EN + HE pack), `.brl` link types |
| Tests | `tools/test.sh`: Rust tests + 10 headless Godot tests (mission start, taxi, gear rules, menu → TSD → fly, mission runtime, console, G effects, takeoff roll, the ground-pull glitch, real steering); `IAF_DEFAULT_SETTINGS=1` isolates tests from the player's settings and data |
| Tools | `iaf-mission-report` → docs/mission-coverage.md (what each mission needs); flight recorder `user://last_flight.csv` |

## Known gaps (open)
1. **Front end** (all decoded in docs/front-end.md, not built): original Preferences pages (Graphics / Sound / Controls /
   Devices / Gameplay art, §12 — "No blackouts" lives on the original Gameplay page; ours is a stand-in), Login / Pilot
   Records and mission unlocking (§13), Reference (§14), Arming (§15), QUIT confirmation (msg 7), TSD 3D-model and target
   windows (§10–§11), TSD selected-unit label (§8.1). Out of scope for now: Multiplayer, Mission Creator, Jump In.
2. **Only the F-16 is flyable**: other jets are shown disabled; campaign missions start in the F-16 whatever the mission says.
3. **MFDs**: radar contacts / lock / STT, radar MAP (isr.bmp) and GMT content, RWR threats, HARM / TV / FLIR content,
   full-screen weapon MFD, NAV distances / ETA, stores stations. Initial radar mode / range not traced (LRS, 20 NM used).
4. **Panel lights**: master caution, fire, AI / SAM, ECM and autopilot lights have no systems driving them yet
   (no damage / RWR / ECM / autopilot); night dimming, the `[TEXTMESSAGE]` line and chaff / flare counters are not drawn.
5. **Terrain**: level-3 regions outside the airbases, insets outside the level-4 Israel rectangle, far theatre levels.
6. **Mission objects**: level-of-detail models, damage states, moving units / AI, weapons.
7. **Flight model**: stall / spin / departure modes, AB light-up delay, landing / crash check (`5b85b0`), gear leg
   timing in the flight model (drag), gear sound, weapon-release gear lock; "stalls off" / "easy" preference branches.
8. **Loading**: terrain chunks / detail tiles still stream in after the cockpit appears; load them behind the
   loading screen and enter the cockpit when done.
9. **In-flight sounds**: engine, wind, gear, cockpit warnings (only voices, "Over G" and the G sound play); in-flight pause menu.

## Decisions / deviations (agreed with the user)
- g readout on the ground shows 1.0 (display only; the original's ground readout is not traced).
- Terrain under a rolling aircraft: the wheels follow our terrain (the original's runways are flat).
- Real data set: pedal nose-wheel steering and no ×4 ground-lift quirk; the original set keeps the original formula
  (stick steering; steering above ~40 kt can hop the jet off).
- "Better physics" option (Preferences, off by default; separate from the data set): γ-based 1 g hold (the
  original's neutral stick slowly dives at high speed). Ground effect: later, same option.
- In-flight subtitles stay English in Hebrew mode (no Hebrew source exists).
- Rendering improvements allowed: smooth text, Lanczos-upscaled art.

## Plan (in order)
1. ~~Front end~~, ~~TSD~~, ~~MFDs~~, ~~airbase~~, ~~mission runtime (Engines ON)~~, ~~lights (gear / flaps / brake)~~.
2. **Finish the flight physics** (airborne port audit §15, stall / spin / departure, AB light-up, landing / crash
   check, preference branches, airborne start), then **complete the F-16 model**: afterburner flame / nozzle and
   the other visual parts driven by the flight state.
3. Remaining front-end screens from the decoded specs: original Preferences pages (incl. "No blackouts"), QUIT
   confirmation, pilot records and mission unlocking, TSD selected-unit label and 3D-model / target windows, Arming.
4. In-flight sounds (engine, wind, gear, warnings) and the landing / crash check.
5. Next training missions (docs/mission-coverage.md): what Landing (312) and Low Level Navigation (313) need.
6. Later: see docs/roadmap.md (other aircraft, AI, weapons, better model, 3D cockpit, satellite imagery).
