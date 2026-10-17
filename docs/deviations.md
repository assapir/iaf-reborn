# Changes from the original

This page lists every place where we knowingly differ from the original game (v1.1 logic), so all differences can be
reviewed in one spot. The rule is to follow the original exactly; each entry here is a decided exception.

- **§1 Always-on changes:** active for every player, with no switch. Each row gives the original's behaviour, ours,
  and why.
- **§2 Opt-in switches:** off by default, so the game plays as the original until the player turns them on.
- **§3 Original quirks we keep on purpose.**

Keep this page updated whenever a change is made or removed.

**Terms:** AA = air-to-air; AB = afterburner; AGL = height above ground level; AI = computer-controlled units; AWACS =
airborne early warning aircraft; EEGS = enhanced envelope gun sight (F-16 HUD gun cue); EO = electro-optical (FLIR /
TV) sensor; FLIR = forward-looking infrared; FF = force feedback; FM = flight model; HARM = anti-radiation missile;
HUD = head-up display; IR = infrared; LCOS = lead-computing optical sight (gun sight); LOD = level of detail; MFD =
multi-function display; MIL = military power (full throttle without afterburner); MSAA / FXAA / TAA = anti-aliasing
methods; NAV = navigate mode; NM = nautical miles; RPM = engine revolutions (%); RWR = radar warning receiver; SDL =
the input library under Godot's joypad API; TSD = tactical situation display (map); UAV = unmanned aerial vehicle (the
camera drone of the TSD target window); UNCERTAIN = the original's code did not settle this.

## 1. Always-on changes (no switch)
Each row: Original = the 1998 game; Ours = this port, for everyone.

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
| Parachuter | freezes at "land − 10 s" (factor 4) | descends to 20 m AGL | original bug; flight has ended by then in single player | part-animation.md |
| Frame-rate-dependent effects | canopy spin 10°/frame, smoke puffs once per frame, flame flicker per frame | time-based (smoke 30 Hz) except the flame flicker | same look at any frame rate | damage.md, aircraft.md |
| Explosions, smoke, afterburner flame | 1998 sprites / blend modes (partly not decoded) | our soft billboards / additive glow, original sizes and timings | rendering | damage.md §6, aircraft.md |
| Shadows | the original's shadow method | Godot sun shadows (4096 atlas, 4 cascades to 400 m, soft filter); Graphics SHADOWS turns them off | rendering | terrain_view.tscn |
| Shatter pieces (flag 0x2) | one per model polygon; > 6 vertices = large | one per triangle of our model (max 600, else neighbours together); largest 10 % = large; a flared piece stays drawn | our models are triangulated / subdivided | damage_effects.gd `_shatter_model` |
| Resting debris (explosion flag 0x1000) | pieces stop at the explosion altitude − 0.5 m | on the terrain under each piece | a low explosion (up to 10.5 m above ground) or a slope left pieces hanging in the air | damage_effects.gd `_update_pieces` |
| Hit shake | flight-model side not traced | 2° camera shake for 0.5 s | stand-in | damage.md |
| Engine-off sound | landing.wav (86 samples of near-silence) looped | not played (silence) | the short loop beeps as a tone | flight_sounds.gd |
| Sounds | DirectSound 3-D | Godot 3-D audio with the DirectSound distance rule; a busy voice channel queues | queue vs replace not traced | sound.md |
| Text and art | GDI text, 8-bit art | smooth text, 4× Lanczos art (never AI upscaling) | rendering (user decision) | — |
| HUD sprite font | the 5×5 pixel font drawn as pixels (FUN_00525890) | each glyph's lit pixels joined by antialiased strokes at screen resolution (same shapes) | at a non-integer scale the pixels came out uneven | hud.gd `_sprite` |
| Airbase underlay models (ul_rw*: runways, taxiways, aprons) | drawn over the terrain (how is not traced) | not drawn (the units stay for the mission logic) | the terrain's inset imagery already shows the airbase; drawn, they z-fought with it and did not register with it before the Present scale (0x65e, ×2) was ported; at that scale they do — user decision, **to revisit** | terrain_view.gd `_spawn_mission_objects` |
| Model textures | 8-bit textures as the 1998 renderer sampled them | mipmaps + anisotropic filtering on every runtime-loaded model texture | without mipmaps distant models shimmer | util/gltf.gd `open` |
| Ground preload | the mission loads behind the progress bar after Fly | the ground around the chosen flight leader's start also loads in the background while the TSD / briefing / Arming screens are open | Fly starts almost at once | terrain_preload.gd, front_end.gd |
| OBJECT DETAIL LOD | `_h` / `_m` / `_l` by the projected size on the view depth (F = 640 px / tan(fov/2)), every root object | the same switch distances on the camera distance (visibility ranges), for the mission units; jets keep `_h` | Godot LOD by distance; jets' switching not traced | terrain_view.gd `_add_lods` |
| Terrain detail render resolution | levels 1–3 draw the terrain at 0.7 / 0.8 / 0.9 of the viewport | full resolution | a 1998 performance measure | front-end.md §12.4 |
| Cloud layer | drawn against the current far plane (0x6284cc), cut at +0x1098 (`407c70`), over a plain clear colour / time-of-day table | far = 30000 (the static value); drawn at the far plane behind all terrain (no cut), over our gradient sky (with the layer off too) | same result as the cut at the terrain's horizon (our terrain reaches 200 km); the per-frame far is not traced; our sky is ours | cloud_layer.gd |
| Credits roll (§4.1 front-end.md) | credits.trx only; scroll step `__ftol(0.5 + dt/16)` px and palette steps of ≥ 8 ms per loop pass (so the speed followed the loop / flip rate) | our lines (project, author, source, licence) and the converted imagery layers' credits roll before the original's (game/menu/credits_ours.json, docs/credits.md); scroll a steady 1 px per 16 ms, fades a steady 400 ms | crediting the port and the CC BY imagery; smooth rendering | credits_roll.gd |
| Trail blending | global blend state (UNCERTAIN) | alpha blend, crossed quads as the original | rendering | trails.gd |
| Damaged stick (hydraulics 18 / flight control 24) | scaled in the stick motion, so it applies at the next stick event (a keyboard: the next key change) | the host sends the stick every frame, so it applies at the next frame | per-frame input (same as the keyboard-edge row) | aircraft.rs `set_controls` |
| AI systems damage | the pick has AI rules (no 2, 3, 5, 7), the AI's reaction is not traced | AI jets take no systems damage | untraced | damage.md §5.3 |
| Runway numbers | two mirrored "33" at Ramat David | re-flipped at conversion | 1998 art error | formats/ptt.md |
| In-flight subtitles in Hebrew mode | — (no Hebrew exists) | English | user decision | — |
| Autopilot leaving NAV | throttle re-sync (`FUN_005a29d0`) gated on a vehicle getter == 0x1e (not traced) | re-sync (0.74 airborne, no throttle axis) on every exit from NAV | gate not traced | autopilot.md §1, controls/autopilot.gd |
| Joystick input | DirectInput: the first joystick found at startup, named axes lX / lY / lZ / lRz (slider 0 or lRz decides "has a rudder"), DirectInput's ranges and 25 % dead zone, buffered buttons | Godot's joypad API (SDL): the first connected joypad, hot-plug; axes by number (`[devices] joy_axes`, default 0 / 1 / 2 / 3); the 25 % dead zone computed by us; a device counts as having all four axes; the hat from Godot's D-pad buttons 11–14; `.joy` files matched against SDL's device name | DirectInput is Windows-only; Godot does not name the axes | controls.md §5.2, controls/joystick.gd |
| Joystick force feedback | `iaforce.ifr` effects on FF sticks | none | not ported | controls.md §5.1 |
| Autopilot level mode, ground watch | KeepOrientation posts an uninitialised throttle slot when the ground watch takes over | that slot starts at 0 (the watch's 250 m/s law applies) | undefined value in the original | autopilot.md §2.1 |
| Waypoint sequencing | each pass schedules the "waypoint report" radio at +3 s; next waypoint also calls `440e90(index)` | the report is posted (radio.gd `waypoint_passed`), the `440e90` call is not | target of `440e90` not traced | autopilot.md §2.2 |
| Weapon HUD geometry | the HUD projector (not traced) | seeker / circle angles at 12 px/deg from the camera ray through the HUD centre | projector untraced | weapons.md §5.1 |
| Helmet sight in snap views | the seeker's helmet branch tests the view type (free look 0x12 / padlock 0x16); the snap views' slot-2 type is not traced | snap views (numpad / F2) stay on the nose case | type UNCERTAIN | weapons.md §5.4 |
| AA gun LCOS start | rate filters from untraced first values | start from the attitude at mode entry | avoids a 1 s pipper jump | weapons.md §3.7 |
| Gun candidate list order | the spatial query's order | nearest first | order untraced | weapons.md §3.3 |
| Weapon targets | every object in the spatial database | units with a model (sensors / logic nodes left out) | UNCERTAIN whether they are in it | player_weapons.gd |
| Weapon effects look | muzzle flash scale / blend, splash, missile explosion (partly not decoded) | muzzle flash 1 m additive, white puff splash, fireball + puff | rendering | weapons.md §3.5–3.6 |
| Bomb HUD terrain ray (cockpit views) | the pick of the rendered picture at the impact's screen point (`FUN_0045ed40` → TgenAPI slot 0x2c) | the first terrain on the line of sight from the jet to the impact, from the terrain heights (1 % steps, bisection); a point off the screen is not special-cased | the pick is a renderer read-back | weapons.md §9.4 |
| AI ripple before a weapon-change action | W+0xe8..0xf0 not set by the handler's constructor (`FUN_00453ab0`): an uninitialised quantity until 350 / 360 / 380 | 1 store, 10 m, 0.1 s | UNCERTAIN initial value | combat.gd `_setup_aircraft`, weapons.md §9.9 |
| AI bomb / rocket aim | T + V·t + ½A·t² (t = \|T − own\| / own speed) | T + V·t (no target acceleration kept) | ours | combat.gd `_ripple_tick` |
| AI rockets' pool | each jet's handler has its own ring pool of the rocket station | the AI jets' rockets share the player's rocket pool (`player_weapons._rockets`) | enough rounds for the missions' few | player_weapons.gd `release_store` |
| Stores on a model without `Station*` helpers | the attach point without the helper (not traced) | not drawn (weight / drag still count) | UNCERTAIN | stores.gd `setup`, weapons.md §2.2 |
| Mode-5 HUD rectangle | PtInRect on the HUD clip R+0x2770 in cockpit views | our HUD symbology field (the HUD Control) when the HUD is shown; the target ray through the clipped point from our camera | same geometry, our projector | weapons.md §9.4 |
| Bomb time-to-go speed | the speed of the entity's selector 6 (not decoded) | the ground speed | UNCERTAIN which speed | weapons.md §9.4 |
| Rocket flight (560) | `FUN_0047a491` with a positive acceleration (branch not traced) | the gun rounds' formula with +100 m/s² up to _limitVel; aim = the ripple point | UNCERTAIN | weapons.md §9.7 |
| Cluster opening (510) | the canister opens 1000 m above the terrain (`FUN_00463ec0`, a model change) | not drawn | visual only | weapons.md §9.5 |
| Rocket box | drawn per FUN_0053e430 (empty box behaviour not traced) | one LAU-61 box per rocket pylon, kept when empty | UNCERTAIN | weapons.md §9.7 |
| HUD lines and text | GDI 1 px pen, Arial h10 w5, the 5x5 sprite font, at 640x480 | the same geometry ×ui scale: lines max(1, 0.6·scale) px, Arial squeezed to the 5 px average width, sprite glyph pixels as scale-sized squares | crisp at screen resolution | cockpit.md "HUD symbology", hud.gd |
| HUD text rows of the weapon timers | mode 4's "%2d" of S+0x380 and "AUD" (S+0x3a4) (modes 1, 2, 8 "%2d SEC" and mode 5's "%2d SEC" / "XX SEC" are built) | left empty | mode 4's timer and AUD are not traced | cockpit.md "HUD symbology", weapons.md §11.3 |
| HUD waypoint marker behind the eye | the projection's result (`FUN_00402000`, untraced for points behind) | held on the field's edge toward the point's direction | untraced | hud.gd `_draw_waypoint_marker` |
| HUD NAV cues rate | S+0x58 / 0x5c / 0x60 / 0x324 refreshed when the waypoint object runs (`FUN_00452e60`, state 5; rate UNCERTAIN) | every frame | UNCERTAIN rate | hud.gd `nav_cues` |
| Arming loads on the aircraft | both members of the flight (and every flight on Yes / DEFAULT) | the player's jet only (the tables are kept for every flight); AI jets carry the mission's / object's load (combat.gd `_setup_aircraft`) | not wired to the AI jets yet | front-end.md §15 |
| Esc on the Arming screen | not traced | acts as BACK (checks, "Use weapon load?", TSD) | the generic Esc went to Main without the question | front_end.gd |
| AI watch-ground line of sight | terrain ray `0x4020d0` | 8 terrain samples along the segment | ray not decoded | ai.md §8.4 |
| AI landing pattern height | terrain height at the lineup point | the lineup point's iaf.ibx altitude | the loop runs without terrain access (they agree to a few m) | ai.md §8.3 |
| FM data per type, Flight data = Real | Kfir and Mirage share one parameter block, loaded once per game session: the second type flies on the first's data | Real: each jet its own section (Original: shared, as the original) | original bug, fixed with the Real set (user decision) | flight-model.md §1 |
| Radio reports | AWACS contact calls, airborne / landed / crashed / kill reports | not yet (waypoint and eject reports, tower, wingman commands are built) | need the take-off / landing loop hooks and the combat job | radio.md §4 |
| Mission voices and radio phrases | one phrase channel: the mission voices (`FUN_004c5470(wav, 0, 1)`) queue with the radio's word wavs | the radio queues on the phrase channel; the mission voices keep their own player (a new one replaces the old) and can overlap a radio phrase | the voice player predates the radio; the channel policy is UNCERTAIN | radio.md §1, sound.md §2 |
| Tower: hangar −1 | `5521c0` returns −1 beyond 1000 m and the "at the hangar" test reads the entry before the table (uninitialised) | no hangar | undefined memory | radio.md §2 |
| Decoy look | missFLR sprite (blend state not traced); chaff bursts and flare smoke once per rendered frame | the flare additive; bursts and smoke at a fixed 30 Hz | rendering; same density at any frame rate | decoy_fx.gd, weapons.md §10 |
| Missile chasing a decoy that ended | it keeps chasing the decoy's pool object (which a later decoy of the ring reuses: UNCERTAIN) | the decoy's end point | pool reuse not traced | player_weapons.gd `target_state` |
| Radar MAP picture | isr.bmp sampled per pixel, nearest, the centre truncated to whole isr pixels (`FUN_0053b0a0`) | the 4× isr art as a textured polygon (smooth scrolling and turning), same window, scale, centre and green channel | rendering | mfd.gd `map_picture`, mfd.md §4 |
| EO (FLIR / TV) picture | the 3D engine's viewport 1 at the MFD's 112 × 112 screen px, colour | a SubViewport camera of the same world at the display's on-screen size (same 50° / zoom, eye, attitude, roll 0), only while page 5 / 6 shows with the cockpit drawn | rendering | mfd.md "FLIR (6), TV (5)", terrain_view.gd `_update_eo_view` |
| EO camera eye | the store's pylon position | the jet's position | pylon offsets are metres | player_weapons.gd `_eo_from` |
| EO centre point | the depth pick of the picture's centre pixel (terrain, buildings, units: what is drawn there) | the nearer of the terrain under the line of sight (ray-marched, 2 % steps, 8 halvings, 100 km) and the visible units' damage boxes (`DamageModel.size_of` cubes, ray-tested) | the pick is a renderer read-back | player_weapons.gd `_eo_update`, eo.rs `unit_pick` |
| NAV page distance | 3-D to the waypoint | horizontal (our route has no waypoint heights) | data | mfd.gd `_draw_nav` |
| MAP / GMT cross-hair | drawn while the MFD owns the cursor (a click inside it first) | while the mouse is over the display | no cursor ownership in ours | mfd.gd `_cross_hair` |
| Terrain line of sight (radar, HARM, ground units' sensors and fire) | `FUN_004020d0` (sampling not traced) | stepped by the clearance (at most 1.5 rise per metre assumed), at least every 20 m: no ridge is stepped over (before: every 100 m, the ground units capped at 32 samples, which saw through narrow ridges) | UNCERTAIN original sampling | radar.rs `line_of_sight`, radar.md §8 |
| Decoy / rocket aim cut at the terrain | `FUN_004020d0` (sampling not traced) | steps of 2 % of the distance (at least 25 m), then 8 halvings | UNCERTAIN original sampling | gun.rs `terrain_cut`, weapons.md §10 |
| Pilot records storage | `Pilots.dat` + `Pilots\<id>.mis` / `.bmp` next to the exe | our own JSON with the same data in the user data dir (`user://pilots`: `pilots.json`, `<id>.json`, custom photo `<id>.png`); original files are not imported | user decision | front-end.md §13.13 |
| Pilot list box during panel slides | a frame child created after the slide-in (destroy order on leaving not traced) | drawn only while the left panel is fully in | order untraced | pilot_records.gd |
| Pilot list / Dossier details | the scrollbar's track click page step not traced; an empty pilot list never occurs | track click pages 11 rows (as Arming / Controls); the last pilot is kept when the list is written even if blank | untraced / edge case | pilot_records.gd, pilots.gd |
| Our keys Ctrl+F1 / F2 / F12 | — (no table record uses them) | quit box / cockpit ↔ external / info line (were on Esc, C, F2, F12 before those commands were built) | user decision | controls.md |
| FlyTSD (Esc) | Fly can switch to another formation's aircraft; Visit; Ctrl+P there; units probably live | Fly / Esc / BACK return to your jet; Visit does nothing; no pause there; units at their mission start | not built (taking over another jet; Visit untraced) | views.md §1 |
| Views: unknown conventions | — | fly-by offset axes (x right, y forward, z up), orbit signs, object size = largest scaled-model dimension, visual lock at the screen centre | UNCERTAIN in the trace | views.md §4.4 |
| HUD-only view (F1 twice) | viewport grows to 480 rows (projection centre moves); the HUD drawn at scale 2 around (320, 240) (`FUN_00530b70` case 5) | the cockpit projection kept, no panel / MFDs drawn, the HUD at the cockpit scale and place | keeps the HUD registered | views.md §4.4 |
| Cockpit zoom keys | 20 / 21 enter free look with no motion (the zoom only sets culling) | our cockpit art zoom, one step per press | ours (kept) | views.md §4.4 |
| Wreck circle | circles the attacker when it is within 1000 m | always the wreck | no attacker field yet | views.md §4.4 |
| Briefing links of type 0 naming a model / bitmap | two .brl records (`/3dobjects/groundforces/sa6lcr/sa6lcr_h.x`, `/brief/bmp/interc.bmp`) are type 0: streamed as RTF (no useful window) | opened as the 3D-model / picture window | the link works | front-end.md §6, tsd.gd |
| TSD target window | a still image of the live mission world, rendered on paint; the UAV orbit UNCERTAIN | rendered every frame; the mission at its start (units at their placed positions); UAV 300 m up and 300 m south, 45° down | engine / untraced | front-end.md §10, model_view.gd |
| TSD 3D-model window | the engine renders the model (lighting: engine defaults, UNCERTAIN) | a Godot SubViewport: one sun, grey ambient, MSAA 4×, Camera3D fov 50° across | engine | front-end.md §11, model_view.gd |
| Pause / menu sim freeze | the sim clock stops | the scene tree pauses (sim nodes stop); sounds paused by `stream_paused` | engine mechanism | views.md §1 |
| Script Path movers | `initialDeltaYaw` turns the unit onto its path (`FUN_0047c4cf`, rate not traced); the mover's terrain handling not traced | the unit faces along its leg at once; a flyer (classes 2, 3, 0x1c) holds the points' z above the ground | untraced turn rate; the data's z are heights (0 on runways, 100–1000 m over 700–2,800 m terrain) | mission-runtime.md §4, mission_runtime.gd `_move_on_path` |

## 2. Opt-in switches (original by default)
Each entry names the switch and where it lives, then the difference: "Original: X. Ours, with the switch: Y."

**Preferences → Physics**
- **"Better physics" options and original-bug fixes** (falling-jet heading, tougher enemies on easy AI levels):
  see flight-model.md §10, damage.md.
- **"Locked enemies know who locked them"** (`fix_lock_threat`). Original: the player's radar lock writes the target
  itself into the AI target's threat (brain+0x7c). Ours, with the switch: the lock makes the player the target's
  threat — rwr.md §2.
- **"Bombs burst at the ground"** (`fix_bomb_burst`). Original: a falling bomb is checked only every 0.5 s and bursts
  at the first check point at or below terrain + 1 m, up to ~0.5·|vz| (70 m) under the ground, where the blast's
  height term weakens or cancels the damage. Ours, with the switch: the burst moves up to where the bomb met the
  terrain — weapons.md §9.5.
- **"No collisions with hidden units / wrecks"** (`fix_ghost_collision`). Original: the collider stays for a hidden
  unit (e.g. the invisible houses used as audio markers) and for a destroyed building or vehicle whose model
  vanished, so the jet can die on an invisible obstacle. Ours, with the switch: those colliders are skipped —
  damage.md §7.
- **"Stores weight fix"**. Original: one store per station, pounds in the kg field, tank fuel = the pounds number as
  kg. Ours, with the switch: every store counts in the stores weight, in kg, and the fuel tanks' fuel in kg —
  weapons.md §2.5–2.6.

**Flight data = Real**
- **RWR display.** Original: the display copies the first `count` slots without compacting, so an entry can vanish
  after a removal. Ours, with the switch: it lists every used slot — rwr.md.

**Preferences → Extras**
- **Weapon data (Original / Real).** Original: the 1998 weapon data. Ours, with Real: public missile weights, top
  speed, range, rear-aspect seekers (ours: a target-moving-away test), seeker cones, the AIM-9D's 12 g, the radar
  ranges of the seven jets and gun rounds / rate / muzzle velocity — real-weapons.md.
- **HARM targets (Original / RWR).** Original: the HARM page lists its sensor's own scan (the radar classes within
  20 NM in the ±15° cone, emitting or not, friendlies too, best 15). Ours, with RWR: the page lists the RWR's active
  emitters inside that cone, the nearest 5, the nearest preselected, recaptured with the RWR's 2 s refresh and on a
  click (harm.rs `Source::Rwr`, mfd.md "HARM (10)"). Ctrl+Return steps either list.
- **Flight data (Original / Real aircraft).**
- **HUD pitch ladder.** Original: a linear 12 px/deg ladder, a few px off away from the marker. Ours, with the
  switch: conformal, each rung projected through the camera.
- **"All keys on the Keyboard page".** Original: the page lists 92 of the 117 key records. Ours, with the switch: it
  lists all 115 labelled ones, so the stick, rudder, RPM ± 5 and pans can be rebound — controls.md §3.
- **Additions the original does not have:** flight info line, blackbox, language, Window (framed / full screen),
  "F-35I replaces" (the F-35I flies from a Jet list button, docs/f35i.md), Settings file (export / import the
  preferences, front_end.gd `_settings_file`). Later: extra sounds, canopy open (docs/roadmap.md).
- **HUD (Original (1998) / Real)** (references: [real-hud.md](real-hud.md)). Original: the 1998 HUD on every jet.
  Ours, with Real: each jet's real display:
  - the F-16C/D dash-34 HUD (also, as reconstructions, on the Kurnass 2000 and the Kfir, whose symbology is not
    public);
  - the Lavi's own wide-angle HUD (a reconstruction: its symbology is not public);
  - the F-15A/C HUD;
  - the F-4E's and the Mirage's optical gunsights;
  - the F-35I's helmet display.

  Ours where the sources stop: the EEGS wingspan (35 ft), the bingo (1500 lb), the sights' bombing depression set
  automatically, the F-35's gun / A-G graphics (the F-16's).
- **Anti-aliasing / Terrain close up / Sky** (ours, docs/rendering.md). Rendering only; the first choice of each is
  the look before.
  - Anti-aliasing: MSAA 4× (as before) / + FXAA / TAA (replaces MSAA).
  - Terrain close up: detail that follows the imagery within 1.5 km (coloured ground: patches toward a deeper /
    drier version of the photo's colour, grain and normal detail; grey pavement: a faint grain; water from
    terraintype.dat: none; centred noise, so colours from afar are the imagery's) and 16× anisotropic filtering.
  - Sky: Atmospheric = a clear-day sky (tuned single scattering: deep blue zenith, pale horizon, darker with
    altitude, crisp sun disc with a narrow glare), the haze over the ground in the horizon's colour (aerial
    perspective, same fog density), and the cloud layer's alpha stretched (0.3–0.9 → 0–1) so its clouds stand apart
    with clear sky between them (without the stretch: a grey veil). The original's cloud texture choice (one of six per
    mission, Cloud256_5 nearly overcast) is kept. The sky follows the time of day's sun (rendering.md §4); at night
    the gradient sky is drawn.
- **Terrain imagery** (ours, docs/imagery.md): one row per region (Israel / outside Israel), default "Original".
  - Original: the 1998 ground texture everywhere.
  - Ours, with a converted modern layer (Sentinel-2 10 m outside Israel, Survey of Israel 2015 2 m in Israel at
    2.5 m per pixel, each in 1998 or modern colours; later SPOT 5): the layer replaces the original's ground texture
    only on land in its region. It never covers water, the game's airbases or the original's site insets (level
    0–2). The Israel layer does replace the original's level-3 (9.9 m) cover of Israel.
  - Heights, terrain types and missions stay the original's. The converted layers' credits (CC BY) roll with the
    credits on Quit (docs/credits.md).
  - Data only via `tools/setup.sh --imagery …` (off by default).

**Preferences → Devices**
- **Detent = MIL** (ours, under THROTTLE, off by default). Original: the throttle lever maps linearly. Ours, with the
  switch: "Set at lever" stores the lever position in its detent; the lever then maps piecewise so the detent is MIL
  (74), the next 3 points stay MIL, and the travel past them is afterburner from AB 1 (78) — joystick.gd
  `detent_map`, docs/controls.md §5.

**Preferences → Graphics**
- **VSYNC** (ours): a check in the empty strip left of DEFAULT, default on.

**Pilot guides** (shown only for a record that has a guide, `docs/guides/<dir>.md`; no Extras row): the Reference
screen gets a **PILOT GUIDE** button and view, with an Open PDF link when the guide's PDF was made — front-end.md
§14, reference.gd.

## 3. Original quirks we keep on purpose (decided)
Original and ours behave the same in each of these.
- **Sea west of Suez:** the sea west of Suez (and the Nile delta / Western desert) is one flat plane at −557 m in
  map.ptt; ships there sit at −557 m. Kept as the original for now — **to revisit** (docs/status.md).
- **Cyprus:** marked as water in terraintype.dat, so landing there destroys the jet (kept: it lies outside the area
  you fly in).
- **Runway numbers:** upright but wrong numbers (template 09/27, copies of 15/33).
- **F-16 / Lavi spin:** they never spin in the original (the deep stall is a Physics option).
- **Flight model:** everything listed as "not changed by better physics" in flight-model.md §10.
- **Weapons** (weapons.md):
  - Shift+[ / Shift+] cycle forward like [ / ];
  - the IR seeker and the gun rounds take friendly units too;
  - the gun rounds can step over the 25 m hit sphere;
  - the limited-heat (580) gate is a ±60° bearing test (tail aspect plays no part);
  - the LCOS integrates with dt 0.15 at a 0.05 s gate;
  - with the gear handle down, Tab needs Safety off;
  - running out of ammo gives no message or sound;
  - radar damage leaves the semi-active (610) missiles' guidance on (`FUN_004adb20` never calls `FUN_00458130`),
    while every track change drops it (weapons.md §11.4).
- **EO camera** (mfd.md):
  - zooming during a slew jumps the picture (the rates change, the slew start is kept);
  - the FLIR gimbal marker is mirrored left / right (x = 66 − 56u as the code);
  - I does not toggle;
  - a TV weapon before launch never locks on the key release.
