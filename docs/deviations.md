# Changes from the original

The rule is to follow the original (v1.1 logic) exactly. This is the list of every place where we knowingly don't,
so it can be reviewed in one spot. Keep it updated whenever a change is made or removed.

## 1. Always-on changes (no switch)
| area | original | ours | why | where |
|---|---|---|---|---|
| Ground height (physics) | 5-tap smoothed sample of the finest decoded tile, 1.24 m height steps (`FUN_004047a0`) | the triangle-interpolated surface that is drawn (level 6 heights) | wheels sit on what you see; < 1 m on runways, can differ more over hills | formats/ptt.md, terrain.gd `height_at` |
| Terrain rendering | software renderer, row by row, nearest-pixel level by distance | GPU mesh quadtree with LOD and skirts | modern renderer; same data and level choice | formats/ptt.md |
| View distance | `min(100 km, (AGL·1e-4 + 0.7) × base)` ≈ 21 km on the ground, 30 km at 3 km AGL | drawn to 200 km with fog | better visibility (rendering) | terrain.gd |
| Keyboard stick edges | a DirectInput key event per press / release | Godot key state polled once per frame for edges | a press + release within one frame is lost; a modifier pressed while an arrow is held counts as its release | terrain_view.gd `_read_controls` |
| g readout on the ground | not traced | 1.0 | display only | flight.rs |
| Envelope math | float32 / x87 | f64 | last-digit rounding only | flight-model.md §15.9 |
| Flight channels | sampled with the X-axis time; angles fmod 2π | each channel's own base time (re-based together); angles wrapped ±180° | negligible difference | flight-model.md §15.11 |
| Lift-ramp / β slopes | globals from the **last aircraft type set up** (leak between types) | each aircraft keeps its own | only matters with several flight-model types | flight-model.md §10 |
| Low ejection | opens the in-flight TSD | ends the flight | no in-flight TSD yet | part-animation.md |
| Parachuter | freezes at "land − 10 s" (factor 4) | descends to 20 m AGL | original bug; flight has ended by then in single player | part-animation.md |
| Frame-rate-dependent effects | canopy spin 10°/frame, smoke puffs once per frame, flame flicker per frame | time-based (smoke 30 Hz) except the flame flicker | same look at any frame rate | damage.md, aircraft.md |
| Explosions, smoke, afterburner flame | 1998 sprites / blend modes (partly not decoded) | our soft billboards / additive glow, original sizes and timings | rendering | damage.md §6, aircraft.md |
| Shadows | the original's shadow method | Godot sun shadows (8192 atlas, 4 cascades to 400 m, soft filter); Graphics SHADOWS turns them off | rendering | terrain_view.tscn |
| Shatter pieces (flag 0x2) | one per model polygon; > 6 vertices = large | one per triangle of our model (max 600, else neighbours together); largest 10 % = large; a flared piece stays drawn | our models are triangulated / subdivided | damage_effects.gd `_shatter_model` |
| Resting debris (explosion flag 0x1000) | pieces stop at the explosion altitude − 0.5 m | on the terrain under each piece | a low explosion (up to 10.5 m above ground) or a slope left pieces hanging in the air | damage_effects.gd `_update_pieces` |
| Hit shake | flight-model side not traced | 2° camera shake for 0.5 s | stand-in | damage.md |
| Engine-off sound | landing.wav (86 samples of near-silence) looped | not played (silence) | the short loop beeps as a tone | flight_sounds.gd |
| Sounds | DirectSound 3-D | Godot 3-D audio with the DirectSound distance rule; a busy voice channel queues | queue vs replace not traced | sound.md |
| Text and art | GDI text, 8-bit art | smooth text, 4× Lanczos art (never AI upscaling) | rendering (user decision) | — |
| Airbase underlay models (ul_rw*: runways, taxiways, aprons) | drawn over the terrain (how is not traced) | not drawn (the units stay for the mission logic) | the terrain's inset imagery already shows the airbase; drawn, they z-fought with it and did not register with it before the Present scale (0x65e, ×2) was ported; at that scale they do — user decision, **to revisit** | terrain_view.gd `_spawn_mission_objects` |
| Model textures | 8-bit textures as the 1998 renderer sampled them | mipmaps + anisotropic filtering on every runtime-loaded model texture | without mipmaps distant models shimmer | util/gltf.gd `open` |
| Ground preload | the mission loads behind the progress bar after Fly | the ground around the chosen flight leader's start also loads in the background while the TSD / briefing / Arming screens are open | Fly starts almost at once | terrain_preload.gd, front_end.gd |
| Runway numbers | two mirrored "33" at Ramat David | re-flipped at conversion | 1998 art error | formats/ptt.md |
| In-flight subtitles in Hebrew mode | — (no Hebrew exists) | English | user decision | — |
| Autopilot leaving NAV | throttle re-sync (`FUN_005a29d0`) gated on a vehicle getter == 0x1e (not traced) | re-sync (0.74 airborne, no throttle axis) on every exit from NAV | gate not traced | autopilot.md §1, controls/autopilot.gd |
| Joystick input | DirectInput: the first joystick found at startup, named axes lX / lY / lZ / lRz (slider 0 or lRz decides "has a rudder"), DirectInput's ranges and 25 % dead zone, buffered buttons | Godot's joypad API (SDL): the first connected joypad, hot-plug; axes by number (`[devices] joy_axes`, default 0 / 1 / 2 / 3); the 25 % dead zone computed by us; a device counts as having all four axes; the hat from Godot's D-pad buttons 11–14; `.joy` files matched against SDL's device name | DirectInput is Windows-only; Godot does not name the axes | controls.md §5.2, controls/joystick.gd |
| Joystick force feedback | `iaforce.ifr` effects on FF sticks | none | not ported | controls.md §5.1 |
| Autopilot level mode, ground watch | KeepOrientation posts an uninitialised throttle slot when the ground watch takes over | that slot starts at 0 (the watch's 250 m/s law applies) | undefined value in the original | autopilot.md §2.1 |
| Waypoint sequencing | each pass schedules the "waypoint report" radio at +3 s; next waypoint also calls `440e90(index)` | neither (radio not built; target of `440e90` not traced) | not built | autopilot.md §2.2 |
| Weapon HUD geometry | the HUD projector (not traced) | seeker / circle offsets at 12 px/deg from the boresight | projector untraced | weapons.md §5.1 |
| AA gun LCOS start | rate filters from untraced first values | start from the attitude at mode entry | avoids a 1 s pipper jump | weapons.md §3.7 |
| Gun candidate list order | the spatial query's order | nearest first | order untraced | weapons.md §3.3 |
| Weapon targets | every object in the spatial database | units with a model (sensors / logic nodes left out) | UNCERTAIN whether they are in it | player_weapons.gd |
| Weapon effects look | muzzle flash scale / blend, splash, missile explosion (partly not decoded) | muzzle flash 1 m additive, white puff splash, fireball + puff | rendering | weapons.md §3.5–3.6 |
| HUD weapon line | MFD sprite font | HUD font at the original position | rendering | weapons.md §6 |
| Jettisoned tanks | fall as objects | vanish | the falling store comes with the bombs | weapons.md §2.6 |
| Arming loads on the aircraft | both members of the flight (and every flight on Yes / DEFAULT) | the player's jet only (the tables are kept for every flight) | AI aircraft carry no stores yet | front-end.md §15 |
| Esc on the Arming screen | not traced | acts as BACK (checks, "Use weapon load?", TSD) | the generic Esc went to Main without the question | front_end.gd |
| AI watch-ground line of sight | terrain ray `0x4020d0` | 8 terrain samples along the segment | ray not decoded | ai.md §8.4 |
| AI landing pattern height | terrain height at the lineup point | the lineup point's iaf.ibx altitude | the loop runs without terrain access (they agree to a few m) | ai.md §8.3 |
| FM data per type, Flight data = Real | Kfir and Mirage share one parameter block, loaded once per game session: the second type flies on the first's data | Real: each jet its own section (Original: shared, as the original) | original bug, fixed with the Real set (user decision) | flight-model.md §1 |
| AI radio (FlightController reports, contact calls, "Roger" replies of wingman commands) | spoken | not yet | AI voices wait for the radio work | ai.md §10 |
| Decoy look | missFLR sprite (blend state not traced); chaff bursts and flare smoke once per rendered frame | the flare additive; bursts and smoke at a fixed 30 Hz | rendering; same density at any frame rate | decoy_fx.gd, weapons.md §10 |
| Radar MAP picture | isr.bmp sampled per pixel, nearest, the centre truncated to whole isr pixels (`FUN_0053b0a0`) | the 4× isr art as a textured polygon (smooth scrolling and turning), same window, scale, centre and green channel | rendering | mfd.gd `map_picture`, mfd.md §4 |
| MAP / GMT cross-hair | drawn while the MFD owns the cursor (a click inside it first) | while the mouse is over the display | no cursor ownership in ours | mfd.gd `_cross_hair` |
| Radar line of sight | `FUN_004020d0` (sampling not traced) | terrain sampled every 100 m along the segment | UNCERTAIN original sampling | radar.gd, radar.md §8 |
| Pilot records storage | `Pilots.dat` + `Pilots\<id>.mis` / `.bmp` next to the exe | our own JSON with the same data in the user data dir (`user://pilots`: `pilots.json`, `<id>.json`, custom photo `<id>.png`); original files are not imported | user decision | front-end.md §13.13 |
| Pilot list box during panel slides | a frame child created after the slide-in (destroy order on leaving not traced) | drawn only while the left panel is fully in | order untraced | pilot_records.gd |
| Pilot list / Dossier details | the scrollbar's track click page step not traced; an empty pilot list never occurs | track click pages 11 rows (as Arming / Controls); the last pilot is kept when the list is written even if blank | untraced / edge case | pilot_records.gd, pilots.gd |
| Our keys Ctrl+F1 / F2 / F12 | — (no table record uses them) | quit box / cockpit ↔ external / info line (were on Esc, C, F2, F12 before those commands were built) | user decision | controls.md |
| FlyTSD (Esc) | Fly can switch to another formation's aircraft; Visit; Ctrl+P there; units probably live | Fly / Esc / BACK return to your jet; Visit does nothing; no pause there; units at their mission start | not built (one flyable jet, Visit untraced) | views.md §1 |
| Views: unknown conventions | — | fly-by offset axes (x right, y forward, z up), orbit signs, object size = largest scaled-model dimension, visual lock at the screen centre | UNCERTAIN in the trace | views.md §4.4 |
| HUD-only view (F1 twice) | viewport grows to 480 rows (projection centre moves) | the cockpit projection kept, no panel / MFDs drawn | keeps the HUD registered | views.md §4.4 |
| Cockpit zoom keys | 20 / 21 enter free look with no motion (the zoom only sets culling) | our cockpit art zoom, one step per press | ours (kept) | views.md §4.4 |
| Wreck circle | circles the attacker when it is within 1000 m | always the wreck | no attacker field yet | views.md §4.4 |
| Pause / menu sim freeze | the sim clock stops | the scene tree pauses (sim nodes stop); sounds paused by `stream_paused` | engine mechanism | views.md §1 |

## 2. Opt-in switches (original by default)
- **Preferences → Physics**: the "Better physics" options and the original-bug fixes (falling-jet heading, tougher
  enemies on easy AI levels) — flight-model.md §10, damage.md.
- **Preferences → Physics → "Locked enemies know who locked them"** (`fix_lock_threat`): the player's radar lock
  makes the player the AI target's threat (brain+0x7c; the original writes the target itself) — rwr.md §2.
- **Flight data = Real**: the RWR display lists every used slot (the original copies the first `count` slots without
  compacting, so an entry can vanish after a removal) — rwr.md.
- **Preferences → Physics → "Stores weight fix"**: every store counted in the stores weight, in kg, and the fuel
  tanks' fuel in kg (the original: one store per station, pounds in the kg field, tank fuel = the pounds number as
  kg) — weapons.md §2.5–2.6.
- **Preferences → Extras → Weapon data (Original / Real)**: public missile weights, top speed, range, rear-aspect
  seekers (ours: a target-moving-away test), seeker cones, the AIM-9D's 12 g, the F-16's APG-68 range and gun rounds /
  rate / muzzle velocity — real-weapons.md.
- **Preferences → Extras**: Flight data (Original / Real aircraft), HUD pitch ladder (conformal: each rung projected
  through the camera; the original's linear 12 px/deg ladder is a few px off away from the marker), flight info line,
  blackbox, language, "All keys on the Keyboard page" (the original lists 92 of the 117 key records; the option lists
  all 115 labelled ones so the stick, rudder, RPM ± 5 and pans can be rebound — controls.md §3). Later: Real HUD, extra sounds, canopy open (docs/roadmap.md).

- **Preferences → Graphics**: a VSYNC check (ours) in the empty strip left of DEFAULT, default on.
- **Preferences → Extras → terrain imagery** (ours, docs/imagery.md): one row per region (Israel / outside
  Israel), default "Original (1998)". A converted modern layer (Sentinel-2 10 m outside Israel, in 1998 or modern
  colours; later Survey of Israel 2 m, SPOT 5) replaces the original's ground texture only on land in its region,
  never on water, the game's airbases or the original's fine insets; heights, terrain types and missions stay the
  original's. The layer's credit (CC BY) shows on the loading screen. Data only via
  `tools/setup.sh --imagery …` (off by default).

## 3. Original quirks we keep on purpose (decided)
- The sea west of Suez (and the Nile delta / Western desert) is one flat plane at −557 m in map.ptt; ships there sit
  at −557 m. Kept as the original for now — **to revisit** (docs/status.md).
- Cyprus is marked as water in terraintype.dat, so landing there destroys the jet (outside the area you fly in).
- Upright but wrong runway numbers (template 09/27, copies of 15/33).
- The F-16 / Lavi never spin in the original (the deep stall is a Physics option).
- Everything listed as "not changed by better physics" in flight-model.md §10.
- Weapons (weapons.md): Shift+[ / Shift+] cycle forward like [ / ]; the IR seeker and the gun rounds take friendly
  units too; the gun rounds can step over the 25 m hit sphere; the limited-heat (580) gate is a ±60° bearing test,
  not tail aspect; the LCOS integrates with dt 0.15 at a 0.05 s gate; with the gear handle down Tab needs Safety off;
  no "out of ammo" message or sound.
