# Status — checkpoint 3 (2026-09-30)

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
| **Aircraft parts (all planes)** | generic, data-driven (docs/aircraft.md): `iaf-convert aircraft` writes a descriptor per plane (22 models: 8 flyable jets, AI jets, transports, helicopters; parts / hinges / nozzles / stations / type codes from the object database); one component ports the flight-model part callback per type (control surfaces, flaperons, pitch mixer, flaps, speed brakes, gear legs / doors with the per-type signs and vanish points, hook, drag chute) and the afterburner flame (level 75 + 12.5·stage, 3D-card double cone, afterburn.tga); the F-16 follows the flight model's gear ramp. Canopy / pilot hidden in flight as the original; Extras "Show canopy and pilot" shows them (ours). Test: test_aircraft_parts |
| Terrain | `map.ptt` imagery + heights, chunk streaming, original georeference (docs/formats/ptt.md); **airbase detail tiles** from the level 0–2 insets (~1.24 m/px, 149 tiles, streamed within 6 km) |
| Runway numbers | rendering fix over the 1998 art: Ramat David's two mirrored "33" re-flipped at conversion (data: `crates/iaf-tools/data/runway_number_fixes.json`, docs/formats/ptt.md); wrong-but-upright numbers (template 09/27, 15/33 copies) left as original |
| Mission objects | every entity of the mission + base missions with its original model (bdb object → Present → `.x`, 219 models); hidden / moved by the mission scripts |
| **Mission runtime** | generic (docs/mission-runtime.md): timer queue, trigger/motion scripts, 4 s reached/left checks, events (max count, voice + subtitle, debrief notes, script jumps), role win/lose rules, "Mission Accomplished!" / "Mission failed." box (DEBRIEF / CONTINUE / EXIT), Esc "quit mission?", debrief screen (headline + notes, Replay / New / Next). Instructor voices from `resource/soundfiles`. Tested: Engines ON start to finish |
| Subtitles | the original console: 40 slots, empty line every 3 s of sim time, newest 14 drawn (~40 s lifetime), x=4 y=10+15n, Arial 12/4, HUD colour; English only (no Hebrew exists — user decision) |
| **Flight model** | Rust port (docs/flight-model.md), audited against the exe (§14 ground, §15 airborne; §15.11 port checklist): exact envelope (per-level point lists + plane fit), stall latch, spin mode (the F-16 / Lavi are exempt in the original), landing / crash check with Easy landing / No crashes / Invulnerable, AB light-up delay, original gear / flap / brake ramps (gear 3.1 s), start rules (airborne above 800 m away from a base), preference gates, envelope on the ground, flaps, friction 0.05, brake flag, nose-wheel side force (stick X), 5 Hz touchdown / lift-off / stop rule, aero update re-bases the acceleration; engine off at a ground start ("1" starts it); gear lever rules (no gear-up on the ground, no gear-down > 300 kt); **original / real data sets** (Preferences); validation suite vs public F-16 data |
| Real data set | real F-16 weights / thrust / roll / fuel / stall; geometric pedal nose-wheel steering; no ×4 ground-lift quirk; lift-off ~159 kt |
| Blackout / redout | original accumulators and tunnel / red overlays, "Over G" voice and G sound; "No blackouts" option (Preferences > Gameplay) |
| Cockpit | original 2D panels of all cockpits from `cockpit.ibx`, gauges, ADI, standby horizon, conformal HUD in the original HUD colour table (H cycles 11 colours) |
| **MFDs** | generic per cockpit (placement and default pages from the ini): radar (B-scope, horizon bars, range), TSD (map.emf, heading-up, route), RWR, MENU, NAV, stores, damage, ADI; OSB clicks; keys T / D / Q / R / S / . / , / W (docs/mfd.md) |
| **Panel lights** | all cockpits (docs/cockpit.md): gear lamps per leg (grey up / red moving 2 s / green locked) + animated gear handle, flaps lamp, air brake, blink rule |
| Controls | original keys from the default key table (0x647ff8) and the instructor texts: 1–8 throttle presets (1 starts the engine), 0 / 9 throttle ±5 %, B brakes, G gear, F flaps, arrows stick (← → steer on the ground), Ins / Del rudder, MFD / radar / waypoint keys, H HUD colour |
| **Front end** | original screens / buttons / animations / sounds / music (docs/front-end.md), training + campaign navigation, Jet list with per-mission locks, Hebrew via the community packs |
| **Preferences** | original Graphics / Sound / Controls / Devices / Gameplay pages (§12): art with lit controls, sliders, scoring strip, DEFAULT, working copy + "Save changes?" Yes/No/Cancel, all original prefs stored with their defaults (only No blackouts, music volume and Mute have an effect so far); our own **Extras** tab (Flight data / Language / Flight info / Blackbox) and **Physics** tab (one switch per "Better physics" option, ALL ON / ALL OFF), EN + HE |
| **TSD** | EMF vector map (+ grid / text), units (known flag, icons, sides, headings), flights and default flight, waypoints (drag to edit, route goes to the flight), double-click a leader to fly, zoom / scrollbars, mission title / clock, briefing window with links (lesson RTF, instructor card), message boxes |
| Briefings | RTF with colours → BBCode (EN + HE pack), `.brl` link types |
| Tests | `tools/test.sh`: Rust tests + 13 headless Godot tests (mission start, taxi, gear rules, menu → TSD → fly, Preferences, mission runtime, console, G effects, takeoff roll, the ground-pull glitch, real steering, crash, aircraft parts); fails on any GDScript error; `IAF_DEFAULT_SETTINGS=1` isolates tests from the player's settings and data |
| Better physics | 12 opt-in options, each its own switch (docs/flight-model.md §10): flight-path 1 g hold, force angles, air start (no jolt / engine spooled / trimmed), real landing limits, realistic spins, **F-16 / Lavi deep stall** (MPO rocking recovery), low-speed lift / roll fixes, no nose-wheel lift quirk, ground effect |
| Tools | `iaf-mission-report` → docs/mission-coverage.md (what each mission needs); Blackbox flight recorder `user://last_flight.csv` (Preferences > Extras); replay of a recorded path through the mission runtime (ad hoc, see roadmap) |

## Known gaps (open)
1. **Front end** (all decoded in docs/front-end.md, not built): the in-game effect of the stored prefs other than
   No blackouts, Login / Pilot Records and mission unlocking (§13), Reference (§14), Arming (§15), QUIT confirmation (msg 7), TSD 3D-model and target
   windows (§10–§11), TSD selected-unit label (§8.1). Out of scope for now: Multiplayer, Mission Creator, Jump In.
2. **Only the F-16 is flyable**: other jets are shown disabled; campaign missions start in the F-16 whatever the mission says.
3. **MFDs**: radar contacts / lock / STT, radar MAP (isr.bmp) and GMT content, RWR threats, HARM / TV / FLIR content,
   full-screen weapon MFD, NAV distances / ETA, stores stations. Initial radar mode / range not traced (LRS, 20 NM used).
4. **Panel lights**: master caution, fire, AI / SAM, ECM and autopilot lights have no systems driving them yet
   (no damage / RWR / ECM / autopilot); night dimming, the `[TEXTMESSAGE]` line and chaff / flare counters are not drawn.
5. **Terrain**: level-3 regions outside the airbases, insets outside the level-4 Israel rectangle, far theatre levels.
6. **Mission objects**: level-of-detail models, damage states, moving units / AI, weapons.
7. **Flight model** (ported through §15; remaining): terrain types (water / rough ground / runway surface; our
   terrain has no type data), map-edge "Tornado" push-back, damage-forced spins, hook drag, crash explosion and
   touchdown / crash sounds; the start velocity source of airborne starts is not traced (180 m/s used).
8. **Loading**: terrain chunks / detail tiles still stream in after the cockpit appears; load them behind the
   loading screen and enter the cockpit when done.
9. **In-flight sounds / pause** (docs/sound.md): the player's sounds are ported from SoundProp.trx (engine, gear, flaps, air brake,
   AoA tone, Betty altitude / fuel / over-G, touchdown, crash explosion, eject voice hook, Preferences volumes); the rest needs
   damage / RWR / weapons / terrain types (docs/sound.md §5). Ctrl+P pause and the Ctrl+O On-The-Fly menu are traced
   (docs/front-end.md §16) but not built (in-flight input is being reworked).

10. **Keys**: of the 117 original commands only those in docs/controls.md §3 marked as built work (views other than
   cockpit / chase, autopilot, weapons, time compression, pause, TSD toggle… are not built); no joystick input yet.
11. **Eject** (not ported): the fly-by camera placement (our external view instead), the in-flight TSD after a low
   ejection / the parachuter landing (we end the flight), the "<callsign> ejected" callsign wav, the parachuter swing,
   the "eject" warning sound on a fatal hit (no damage model).

## Done since checkpoint 2
- **Original key table** (`iaf-convert keys` → keys.json; docs/controls.md: all 117 commands, record ↔ keys.trx line
  resolved), **Controls page** (key list, scrollbar, rebinding with msg 36, DEFAULT; `[keys]` in settings.cfg),
  **in-flight keys through the table** with the player's rebinds (throttle presets now the exe's p1 · 0.01). Test:
  test_controls.
- **Eject** (E ×3 within 1 s each): engine off, stick fixed, commands ignored, jet flies on to its crash; pilot off,
  canopy and seat thrown (3 m up / 1.5 m aft per 0.05 s to 100 m), seat after 2 s → parachuter; external view; the
  player counts as lost at once (role rules, debrief 5 s later); low / inverted ejection ends at once. Test: test_eject.
- Extras "Show canopy and pilot".

## Decisions / deviations (agreed with the user)
- Canopy and pilot on your own jet: hidden as in the original by default; Preferences > Extras "Show canopy and
  pilot" (ours) shows them (docs/aircraft.md §2.3).
- g readout on the ground shows 1.0 (display only; the original's ground readout is not traced).
- Terrain under a rolling aircraft: the wheels follow our terrain (the original's runways are flat).
- Real data set: pedal nose-wheel steering and no ×4 ground-lift quirk; the original set keeps the original formula
  (stick steering; steering above ~40 kt can hop the jet off).
- "Better physics": each improvement over the original model is its own switch (Preferences → Physics, all off
  by default; separate from the Original / Real data set). Original bugs found in the port go there.
- Visual additions not in the original live on the Extras tab, off / original by default (canopy and pilot; later
  canopy open).
- In-flight subtitles stay English in Hebrew mode (no Hebrew source exists).
- Rendering improvements allowed: smooth text, Lanczos-upscaled art, mirrored runway digits re-flipped.

## Plan — by missions unlocked (docs/mission-coverage.md, greedy order; user decision 2026-09-30)
Playable today: **2 / 68** (311, 312). Almost every mission needs the combat core together; no smaller feature
completes a mission on its own.
1. ~~Front end, TSD, MFDs, airbase, mission runtime, lights, flight physics + Better physics, aircraft model (all
   planes), Preferences, key table / Controls, eject~~. Running: in-flight sounds (+ pause menu spec).
2. **Player = default-flight leader** (S): the runtime only knows `player1`; campaign missions and 324 fail today.
3. **Combat core** (unlocks 11 with the F-15, 9 F-16-only): damage & destruction (M) → AI brain flight (L: route,
   formation, take-off / landing from the bdb brains) → player weapons: gun + IR missiles (M), external stores on
   the model → AI air-to-ground / air-to-air (M / L) → AAA and radar SAMs with the RWR (M each) → script ops 2 / 21 / 22.
   Closest missions: 313 Pathfinder (damage + AAA), 315 Cold Steel (AI wingman + damage + bombs), 323 Hair Pin.
4. **Bombs + CCIP, armed vehicles / boats fire, motion op 11** (→ 20 / 15 F-16-only).
5. **Other jets** (flight-model data set + cockpit each, L): Phantom 2000 (19 missions), F-4E (17), F-15 (16), Lavi /
   Mirage (13), Kfir (8) — together ~30 missions.
6. Radar missiles with lock, IR SAMs, TV / IR-guided weapons, night, anti-radiation, rockets, brain-driven vehicles.
7. Arming screen (9 missions need a different loadout), multiplayer (8), remaining front-end screens, loading screen.
8. Later: docs/roadmap.md (Better AI, Real weapons, mission replayer, 3D cockpit, satellite imagery, canopy open).
