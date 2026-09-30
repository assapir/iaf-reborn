# Changes from the original

The rule is to follow the original (v1.1 logic) exactly. This is the list of every place where we knowingly don't,
so it can be reviewed in one spot. Keep it updated whenever a change is made or removed.

## 1. Always-on changes (no switch)
| area | original | ours | why | where |
|---|---|---|---|---|
| Ground height (physics) | 5-tap smoothed sample of the finest decoded tile, 1.24 m height steps (`FUN_004047a0`) | the triangle-interpolated surface that is drawn (level 6 heights) | wheels sit on what you see; < 1 m on runways, can differ more over hills | formats/ptt.md, terrain.gd `height_at` |
| Terrain rendering | software renderer, row by row, nearest-pixel level by distance | GPU mesh quadtree with LOD and skirts | modern renderer; same data and level choice | formats/ptt.md |
| View distance | `min(100 km, (AGL·1e-4 + 0.7) × base)` ≈ 21 km on the ground, 30 km at 3 km AGL | drawn to 200 km with fog | better visibility (rendering) | terrain.gd |
| Cockpit camera field of view | the original 3D projection (not traced yet) | invented (`HUD_REAL_FOV = 25`) | **to fix** (queued: original projection) | cockpit.gd |
| Keyboard stick edges | a DirectInput key event per press / release | Godot key state polled once per frame for edges | a press + release within one frame is lost; a modifier pressed while an arrow is held counts as its release | terrain_view.gd `_read_controls` |
| g readout on the ground | not traced | 1.0 | display only | flight.rs |
| Envelope math | float32 / x87 | f64 | last-digit rounding only | flight-model.md §15.9 |
| Flight channels | sampled with the X-axis time; angles fmod 2π | each channel's own base time (re-based together); angles wrapped ±180° | negligible difference | flight-model.md §15.11 |
| Lift-ramp / β slopes | globals from the **last aircraft type set up** (leak between types) | each aircraft keeps its own | only matters with several flight-model types | flight-model.md §10 |
| Ejection camera | fly-by camera | our external view | fly-by placement not traced | part-animation.md "Ejection" |
| Low ejection | opens the in-flight TSD | ends the flight | no in-flight TSD yet | part-animation.md |
| Parachuter | freezes at "land − 10 s" (factor 4) | descends to 20 m AGL | original bug; flight has ended by then in single player | part-animation.md |
| Frame-rate-dependent effects | canopy spin 10°/frame, smoke puffs once per frame, flame flicker per frame | time-based (smoke 30 Hz) except the flame flicker | same look at any frame rate | damage.md, aircraft.md |
| Explosions, smoke, afterburner flame | 1998 sprites / blend modes (partly not decoded) | our soft billboards / additive glow, original sizes and timings | rendering | damage.md §6, aircraft.md |
| Hit shake | flight-model side not traced | 2° camera shake for 0.5 s | stand-in | damage.md |
| Sounds | DirectSound 3-D | Godot 3-D audio with the DirectSound distance rule; a busy voice channel queues | queue vs replace not traced | sound.md |
| Text and art | GDI text, 8-bit art | smooth text, 4× Lanczos art (never AI upscaling) | rendering (user decision) | — |
| Airbase underlay models (ul_rw*: runways, taxiways, aprons) | drawn over the terrain (how is not traced) | not drawn (the units stay for the mission logic) | the terrain's inset imagery already shows the airbase; drawn, they z-fought with it and do not register with it (the model is half the imagery's size) — user decision | terrain_view.gd `_spawn_mission_objects` |
| Model textures | 8-bit textures as the 1998 renderer sampled them | mipmaps + anisotropic filtering on every runtime-loaded model texture | without mipmaps distant models shimmer | util/gltf.gd `open` |
| Ground preload | the mission loads behind the progress bar after Fly | the ground around the chosen flight leader's start also loads in the background while the TSD / briefing / Arming screens are open | Fly starts almost at once | terrain_preload.gd, front_end.gd |
| Runway numbers | two mirrored "33" at Ramat David | re-flipped at conversion | 1998 art error | formats/ptt.md |
| In-flight subtitles in Hebrew mode | — (no Hebrew exists) | English | user decision | — |
| Weapon HUD geometry | the HUD projector (not traced) | seeker / circle offsets at 12 px/deg from the boresight | projector untraced | weapons.md §5.1 |
| AA gun LCOS start | rate filters from untraced first values | start from the attitude at mode entry | avoids a 1 s pipper jump | weapons.md §3.7 |
| Gun candidate list order | the spatial query's order | nearest first | order untraced | weapons.md §3.3 |
| Weapon targets | every object in the spatial database | units with a model (sensors / logic nodes left out) | UNCERTAIN whether they are in it | player_weapons.gd |
| Weapon effects look | muzzle flash scale / blend, splash, missile explosion (partly not decoded) | muzzle flash 1 m additive, white puff splash, fireball + puff | rendering | weapons.md §3.5–3.6 |
| HUD weapon line | MFD sprite font | HUD font at the original position | rendering | weapons.md §6 |
| Jettisoned tanks | fall as objects | vanish | the falling store comes with the bombs | weapons.md §2.6 |
| Keys Esc / C / F2 / F12 | TSD toggle / time compression / back view / I-mode | ours (quit box / view toggle / external / info line) until those commands exist | not built yet | controls.md |

## 2. Opt-in switches (original by default)
- **Preferences → Physics**: the "Better physics" options and the original-bug fixes (falling-jet heading, tougher
  enemies on easy AI levels) — flight-model.md §10, damage.md.
- **Preferences → Physics → "Stores weight fix"**: every store counted in the stores weight, in kg, and the fuel
  tanks' fuel in kg (the original: one store per station, pounds in the kg field, tank fuel = the pounds number as
  kg) — weapons.md §2.5–2.6.
- **Preferences → Extras → Weapon data (Original / Real)**: public missile weights, top speed, range and gun rounds /
  rate / muzzle velocity — real-weapons.md.
- **Preferences → Extras**: Flight data (Original / Real aircraft), HUD pitch ladder (conformal), flight info line,
  blackbox, language, "All keys on the Keyboard page" (the original lists 92 of the 117 key records; the option lists
  all 115 labelled ones so the stick, rudder, RPM ± 5 and pans can be rebound — controls.md §3). Later: Real HUD, extra sounds, canopy open (docs/roadmap.md).

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
