# Better graphics: research and options (2026-10-16)

What could make the game look better, what each option costs on our machine (Apple M4 Pro, Godot 4.7.2 Forward+ on
Metal 4.0), and in what order. Every option is an **opt-in Extras switch**; the original look stays the default
(docs/deviations.md). Research only: nothing here is built yet. Screenshots referenced below are rendered locally into
`assets/converted/research/` (they show the original art, so they are never committed).

## 1. Baseline: where the frame goes

Tools: `tests/godot/_flight_bench.gd` (frame rate over the terrain, per leg), `tests/godot/_cpu_profile.gd` (ours: each
system's `_process` timed on the main thread, the render thread's CPU time), `tests/godot/_gfx_proto.gd` (ours: one
rendering feature switched on, its frame time at 4K, a shot).

**Metal caveats (measured):** Metal presents at the display's refresh even with vsync off, so a frame that fits never
shows below it: 6.90 ms on the 144 Hz screen, 16.67 ms on the 60 Hz one. Godot reports **no GPU time on Metal**
(`viewport_get_measured_render_time_gpu` = 0). To expose a GPU cost, `_gfx_proto.gd` renders 4K at a 1.6 render scale
until the GPU, not the display, sets the frame. Xcode's Metal System Trace would give exact GPU times (not done).

| Run (1920×1080) | 150 m AGL | 1500 m | 6000 m | Note |
|---|---|---|---|---|
| 311, default settings, frozen flight | 144.9 fps (6.90 ms) | 144.9 | 144.9 | capped at the 144 Hz refresh (steady state) |
| 311, BENCH_BEST (all sliders up, MSAA 4×+FXAA, closeup, atmospheric sky, modern imagery) | 144.9 | 144.9 | 144.9 | still capped |
| 221, live simulation (13 AI jets, SAMs) | 6.91 ms | | | capped |
| 231, live simulation (MiGs, ground units, low level) | **10.9 ms (92 fps)** | | | over the cap: GPU-bound (below) |

First runs after start-up are slower (60–82 fps: shader compilation, disk cache) and runs in parallel with other Godot
processes are noisy; the numbers above are warm, alone.

**CPU split (`_cpu_profile.gd`, live simulation, per frame):**

| System (main thread) | 221 avg / worst ms | 231 avg / worst ms |
|---|---|---|
| scene (`terrain_view.gd`: flight, weapons, views, radio, aircraft parts) | 1.07 / 1.5 | 1.34 / 5.0 |
| AI flights (brains + autopilot calls) | 0.61 / 1.0 | 0.31 / 0.6 |
| AI combat (sensors, fire) | 0.27 / **13.4** | 0.52 / **5.0** |
| terrain streaming (main-thread part) | 0.03 / 2.0 | 0.04 / 2.0 |
| mission runtime | 0.02 / 0.1 | 0.04 / 0.4 |
| cockpit, HUD, MFDs (`_process`) | < 0.02 | < 0.02 |
| render thread CPU | 0.44 | 0.45 |

**Verdict:** on the M4 Pro the main thread uses ≈ 2–2.5 ms of a frame, the render thread ≈ 0.45 ms. The game is
**GPU-bound** where it drops below the refresh (231 at low level: 10.9 ms with 2.5 ms of CPU). The CPU shows as
**spikes**, not load: AI combat's sensor scans (5–13 ms worst) — the terrain line of sight samples the GDScript
`mission_ground()` through a Callable once per sample (radar.rs `line_of_sight`), terrain streaming's main-thread
part (≈ 2–3 ms worst), the mission runtime's first events (8 ms once). The earlier "13–24 fps dips" (docs/roadmap.md)
are not reproduced on this machine warm; they were on a heavier earlier build / cold caches.

## 2. Where the work runs (CPU → GPU, Rust or threads)

| Hotspot (measured) | Today | Recommendation | Payoff | Effort |
|---|---|---|---|---|
| Terrain line of sight in sensor scans: 5–13 ms spikes | Rust walk, GDScript height per sample | **Rust**: the terrain heights in Rust (the PTT level-6 grid as a Rust height field, `iaf-formats` already parses PTT), no Callable per sample; scans then < 0.5 ms | removes the worst spikes | M — **done**: `IafHeights` (iaf_avionics::heights) holds the streamed full-detail nodes terrain.gd loads; `world::terrain` answers `mission_ground` from it (same nodes and interpolation, ≤ 1 cm from the float32 GDScript path; line of sight identical on 400 pairs, test_heights.gd); 400 checks 93 → 2.4 ms; mission 221 live: AI combat worst 4.3 → 0.5 ms |
| Terrain mesh / heights | already GPU: heights sampled in the vertex shader; JPEG decode, mipmaps, BC1 on 6 worker threads | keep; the main-thread part (2–3 ms worst on splits) → batch the node swaps | small | S |
| Explosions, smoke, trails, decoys | MultiMesh billboards (GPU-instanced), positions filled by GDScript each frame | **GPUParticles3D** for smoke / fire / contrails (simulation on the GPU, collision with the heightfield): needed anyway for better effects (§3.4) | better look, ≈ 0.1–0.3 ms CPU back | M |
| HUD / MFD drawing (`_draw` every frame) | `_process` < 0.02 ms; the `_draw` canvas calls are on the main thread (not separately measured, small) | redraw only on change, or a SubViewport per MFD updated at the original's rate; not a hotspot today | low | S |
| Vegetation / clutter (new) | — | **MultiMesh**, placement from the WorldCover classes on worker threads or a compute shader | needed for §3.5 | — |
| Flight model, AI brains, mission runtime, weapons | Rust (FM, avionics) + GDScript (brains, runtime) | **not for the GPU** (branchy, serial). Rust per our rule; brains / sensors on the WorkerThreadPool (the M4 Pro has 12+ cores) | keeps headroom as missions grow | M–L |

## 3. Options

Payoff 1–5 (visual), effort S (days) / M (a week or two) / L (weeks) / XL (months). Cost = measured GPU frame time
where measured (lower bounds: base 4K×1.6 still fits a 60 Hz frame), else an estimate.

### 3.1 Sun shadows (already built: Graphics SHADOWS, docs/front-end.md §12)
Godot directional shadows on aircraft / buildings / units, 08:00–17:00 as the original's projected shadows. Measured:
on vs off and the 4-split 8192 atlas at high soft quality all fit the frame at 4K×1.6 (no measurable cost). **Payoff
already had**; a "shadows: high" Extras row (4 splits, 8K atlas) would sharpen self-shadowing on aircraft, cheaply.
Metal: shadow maps are fine on tile GPUs. Recommendation: S, add the "high" row.

### 3.2 Screen-space lighting: SSAO / SSIL / SDFGI / glow
Measured (4K×1.6, frame ms vs 16.7 base): **SSAO ≥ +4.8**, **SSIL ≥ +12.1**, **SDFGI ≥ +18**, glow ≥ +1.2.
Look (shots `gfx_none.png`, `gfx_ssao.png`, `gfx_sdfgi.png`): **no visible difference from the cockpit over the
terrain** — the ground is a heightfield draped with photos, with nothing for ambient occlusion to darken; the cockpit
is 2D art. They would matter only on detailed 3D models (§3.7) and buildings in external views. Metal: bandwidth-heavy
(several full-screen passes at full resolution) — the expensive kind on a tile GPU. Recommendation: **skip now**; SSAO
only with detailed models, external views only. Glow (bloom) for the sun / explosions: +1.2 ms, payoff 2, S.

### 3.3 Modern DEM (SRTM / Copernicus GLO-30) — payoff 4, effort L
The original's heights are coarse (level-6 grid; the physics uses the same surface). A 30 m DEM (Copernicus GLO-30:
free licence, attribution "© DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 provided under COPERNICUS
by the European Union and ESA"; SRTM: public domain) gives real ridgelines, wadis and the Golan escarpment, and normals
for lighting (relief shows in the light, not only the outline). Work: a converter like `iaf-imagery` (GDAL is already a
setup dependency) warping the DEM into the game frame (docs/georef.md), finer height nodes, the physics and AI using
the same surface (heights move: airbases must stay flat — blend to the original around bases; mission objects placed on
the original heights need re-seating). GPU: finer vertex grids near the camera, small on M4 Pro. Risk: missions tuned to
the original terrain (masking routes like 313) change — so it must stay an opt-in. Recommendation: worth it, after the
cheaper items; pairs with the modern imagery already built.

### 3.4 Effects: GPU particles (explosions, smoke, contrails, heat haze) — payoff 3, effort M
Today: soft procedural billboards in MultiMeshes (damage_effects.gd, trails.gd), sizes / timings of the original.
GPUParticles3D with flipbook textures (our own or CC0, e.g. from Kenney / ambientCG), heightfield collision, a heat-haze
distortion pass behind the engines (a Compositor effect or a refraction shader on the afterburner), contrails above a
height / temperature. GPU: modest (particles are cheap; distortion is one extra pass). Metal: fine. Recommendation:
good payoff per effort; do after the CPU spike fix.

### 3.5 Water shader — payoff 3, effort M
Today: the open sea is shaded flat; inland water from terraintype.dat is known per 96 m (render_options.gd). A sea
shader: sun glint (GGX on a scrolling normal map), Fresnel to the sky colour, foam at the shoreline (distance to land
from the same terraintype mask), wave normals by wind. GPU: one material, cheap. Risk: the imagery's sea colour must
blend at coasts. Recommendation: cheap and visible on every coastal mission; early.

### 3.6 Vegetation / ground clutter — payoff 4 (low level), effort L
Trees / orchards / scrub as MultiMesh instances near the ground, placed from the ESA WorldCover classes (CC BY 4.0,
already used for imagery: tree cover, shrubland, cropland) and the imagery's own colour; fade out by 1–2 km. Gives the
sense of speed at 50–100 ft. GPU: instancing is cheap on Metal; overdraw of alpha-tested leaves is the cost (use
impostor cards). Assets: CC0 tree models (Kenney, Quaternius) or our own. Recommendation: after DEM / water.

### 3.7 Detailed aircraft models — payoff 5, effort L per jet (XL for all)
The 1998 models are ≈ 800–3000 triangles with 256-px textures (f16_h: 57 nodes). **Candidates (licence verified where
stated):**

| Jet (variant needed) | Candidate | Licence (checked) | Notes |
|---|---|---|---|
| F-16D (two-seat) | FlightGear F-16 `github.com/NikolaiVChr/f16` | **GPL-2.0-or-later** (`copyright.txt`: "version 2 of the License, or (at your option) any later version", all files) — compatible | `Models/F-16D.ac` exists (two-seater); ≈ 26 000 triangles; liveries (no IAF one listed — paint ours); full 3D cockpit; moving parts as separate objects |
| F-15C (single) | Zaretto F-15 `github.com/Zaretto/fg-aircraft` (`aircraft/F-15`, also FGAddon `F-15`) | **unverified**: no COPYING / licence in the repo; FGAddon's copy is under the FGAddon policy (GPLv2+ since Aug 2015, older files possibly GPLv2-only) — ask the author (Richard Harrison) or take the FGAddon copy's files after checking each | external model by Enrique Laso; C and D variants; cockpit with photo textures |
| F-4E / Kurnass 2000 | FGAddon `McDonnell-F-4-Phantom`; `github.com/Zaretto/F-4X` (GPLv2+, early alpha, an F-4S) | GPLv2+ (F-4X README); FGAddon per file | F-4E differs (gun nose); Kurnass 2000 adds its own avionics bumps |
| Mirage IIICJ | FGAddon `MirageIII`, `MirageIIIE` | FGAddon policy (check files) | the IIICJ is close to the IIIC |
| Kfir C2/C7 | none open; Sketchfab "Kfir C.10 Block 60" (CC BY, but taken from War Thunder — **rights doubtful**, don't use) | — | would be our own build from the Mirage III / 5 base |
| Lavi | none | — | our own |
| F-35I | FGAddon `F-35B` | FGAddon policy (check) | our F-35I is already ours (tools/f35i) |
| MiG-21 / MiG-29 (AI) | FGAddon `MiG-21bis`, `Mig-29` | FGAddon policy (check) | |
| MiG-23 / Su-22 / Su-24 (AI) | none open (only paid CGTrader / 3dcadbrowser, not redistributable) | — | keep the originals |

CC-BY is usable with attribution; NC / ND are not; GPL-2.0-only files cannot ship in our GPL-3.0-or-later repo.
**Fitting one** (a pipeline like `tools/f35i/`): convert AC3D → glTF (Blender), scale to the original's dimensions,
name the moving parts with our `<part>1/2` hinge helpers (gear legs, flaps, ailerons, elevons, canopy, air brake,
nozzle, hook; docs/part-animation.md, docs/adding-a-plane.md), the `Station*` helpers at the original's pylon positions
(stores must hang where the original's do), the eye point and the afterburner `EngineL/R` helpers; LODs (full / 30 % /
impostor) for AI use; PBR textures (repaint in IAF camouflage: ours). The original's wheels never roll (part ids
0x21–0x26 are hidden for aircraft, docs/part-animation.md; no aircraft model has Wheels frames) — a detailed model
could add rolling wheels as an extra. Extras switch "Aircraft models: Original / Detailed". Effort per jet: L (F-16D
first, ≈ 2–3 weeks), then F-15C. GPU: 26 k triangles × a few jets is nothing on the M4 Pro; textures 2–4K per jet.

### 3.8 Cockpit: better 2D, 3D, clickable — payoff 5, effort L → XL
- **(a) Better 2D** (S–M): today the 1998 panels upscaled 4× (Lanczos, never AI). Higher resolution needs redrawn art
  (ours) — a lot of work for the 2D look; low payoff relative to (b).
- **(b) 3D virtual cockpit** (L for the F-16D): the FlightGear F-16 cockpit (GPL-2.0-or-later, above) is a complete
  modelled pit (MFDs, DED, RWR, CDU, ICP, gauges). Must be live: our MFD and RWR drawers rendered into SubViewport
  textures on the 3D screens, the Real HUD drawn on the combiner glass at its real field of view (this also fixes the
  "real FOV" TODO, docs/roadmap.md: the glass becomes the real one), the gauges' needles from our cockpit state, the
  lamps. Head movement: free look already exists (views.gd); TrackIR-style 6-DoF later; VR possible with Godot's
  OpenXR (not on macOS). Extras "Cockpit: Original 2D / 3D". GPU: a few SubViewports at MFD resolution, cheap.
  F-15C: the Zaretto cockpit (licence to clear, above).
- **(c) Clickable** (M after b): mouse-look + click with a highlight; switches mapped to our commands
  (docs/controls.md): master arm, gear, flaps, hook, chaff / flare, ECM, MFD OSBs (already clickable in 2D: docs/mfd.md),
  radar mode, autopilot; the keyboard keeps working.
Recommended path: F-16D 3D cockpit with live MFDs / HUD first, then its clickables, then the F-15C.

### 3.9 Atmosphere, clouds, fog — payoff 3, effort M
Built: the atmospheric sky and the cloud layer (docs/rendering.md). Volumetric fog measured free at our density (it
hides little at flight distances); real gain would be **volumetric clouds** (a raymarched cloud layer as a sky shader
or Compositor effect): payoff 4 but cost ≥ 3–6 ms at 1080p on tile GPUs (bandwidth) — only with upscaling (§3.10).

### 3.10 Upscaling for headroom: MetalFX — payoff (perf), effort S
Godot 4.7.2 on Metal has **MetalFX spatial and temporal** scaling (`Viewport.SCALING_3D_MODE_METALFX_SPATIAL /
_TEMPORAL`, checked in our binary) besides FSR 1 / 2. MetalFX temporal at 0.67 scale would buy back most of a 4K
frame's GPU time for the expensive options (SSAO, clouds). An Extras "Upscaling: Off / MetalFX / FSR 2" row, S.

### 3.11 Night lighting — payoff 3, effort M
Open gap (docs/status.md "Cockpit / MFDs: night lighting"): panel night shifts are known (`[PANEL]` Night R/G/B,
docs/cockpit.md). Beyond the original: runway / airbase lights (OmniLight3D sparse, or emissive point sprites — cheap),
city lights from the imagery's built-up classes (WorldCover), the moon. Godot 4.7's `AreaLight3D` exists (not needed).

### 3.12 Runway / airbase detail, buildings (OSM) — payoff 3, effort L
Runway markings and lights as decals / meshes at the three bases (real layouts: docs/roadmap.md "More airbases").
OSM buildings: ODbL (share-alike on the *database*; a derived 3D-building dataset generated at setup and kept local in
`assets/` is the safe pattern, like the imagery). The original's object placement must stay (missions place targets).

### 3.13 Detailed weapon and store models — payoff 3, effort M
Today: the 1998 stores are 117–432 triangles on one shared 256-px atlas (`weapons.png`), 38 folders under
`objects/weapons/` (bombs, missiles, tanks, pods, the ZUNI box) plus the SAM / Scud rounds under `groundforces/`
(`sa2lcr` … `sa6lcr`, `scdlcr`) and the MiG-29 tank (`controllableplanes/mig29/mig29ftk_m`). They are seen close in
the external views, on the pylons and in flight.

**Switch.** Preferences → Extras → **Models: Original / Detailed** (default Original; docs/deviations.md entry:
visual only, no behaviour change). One switch that the detailed aircraft (§3.7) join later rather than a second
toggle — the user's call.

**One hook: `Gltf.object(path)`** (`game/util/gltf.gd`). Every weapon model goes through it: the pylon stores and the
launched / dropped weapons (`player_weapons.gd` `_instance`), the AI jets' stores and rounds (`combat.gd`), the
Reference viewer (`model_view.gd`) and the mission objects (`terrain_view.gd`). With the switch on, it opens the
detailed model mapped to that original path when there is one, else the original — each model falls back on its
own, so they ship a few at a time, and later ground units / ships take the same path. The static cache key becomes
`"level:detailed:path"` (today `"level:path"` survives across scenes: toggling between flights would keep the old
models). Far away a detailed store is not worth its triangles: the original model as its far LOD
(`visibility_range`, as the mission objects' LODs in `terrain_view.gd`).

**Fit to the original, at load time, so only the look changes.** Game code reads geometry from these models:
`stores.gd` takes the store's `pilon` / `Pilon` helper (both spellings occur) for `IafStores.slots` (rack spacing),
`player_weapons.gd` the half length from the model's AABB, and every node gets the Present scale (2.0) on top. The
hook keeps those from the original (its pilon helper and AABB are what the game code reads) and places the detailed
mesh on them: its own lug point onto the original's pilon helper, its axis onto the original's. The originals are
already close to real size in the same units (Mk-84 3.93 vs 3.84 m, AIM-9 2.85 vs 2.87 m, AIM-120 3.52 vs 3.65 m,
F-16 jet 15.01 vs 15.03 m), so the detailed models stay at real size; one more than 10 % off the original's length
is scaled to it (moving rack slots would be a behaviour change, a separate question).

**Sources: download first, build only the gaps; both committed.** The models are ours or GPL-compatible, not
original game data, so they are tracked in the repo (`models/stores/<name>.glb` + `models/stores/SOURCES.md`, a few
MB), not regenerated at setup; nothing about them depends on the install, since the fit happens at load time.
- **FlightGear F-16** (`github.com/NikolaiVChr/f16`, `Models/Armament/`; `copyright.txt`: "extends to all files in
  this Flightgear F-16 package", GPL-2.0-or-later — compatible with our GPL-3.0-or-later; authors in its
  `authors.txt` → docs/credits.md): MK-82, MK-83, MK-84, AIM-9L / M, AIM-120B, AIM-7F, AGM-65B / D, AGM-88,
  CBU-87, GBU-12 / GBU-24 (stand-ins for the game's laser Mk-82L / Mk-84L), the 300 / 370 / 600 gal tanks,
  ALQ-131 / ALQ-184 ECM pods, LANTIRN (FLIR pod), LAU-68 (a stand-in for the ZUNI box). AC3D → glTF once with
  Blender, materials to PBR, textures kept; covers ≈ 18 of our 38 folders, the most-seen ones.
- **Checked, not usable**: hobby / print packs (CGTrader, Cults3D, 3dcadbrowser: personal use or paid);
  Sketchfab game rips (War Thunder / DCS: rights doubtful); no Smithsonian CC0 scan of these weapons found.
- **To check next**: FGAddon `MiG-21bis` / `Mig-29` / `MirageIII` stores (AA-2 / AA-8 / AA-10 / AA-11, Shafrir,
  the Mirage tank) — FGAddon licence per file; the Zaretto F-15 stores (AIM-7 / 9 / 120, tanks) once its licence is
  cleared (§3.7).
- **Built by us for the rest** (Israeli, Soviet and old US stores no open model covers: Python 3 / 4, Shafrir 2,
  Popeye, AGM-62 Walleye, GBU-15, M117, CBU-97, RBK-500, AS-14 / AS-16, AA-6, SA-2 / 3 / 5 / 6, Scud, the F-15 /
  F-4 / Kfir / MiG-29 tanks): a small Blender script (to be added under `tools/`, like `tools/f35i/`) that makes a
  lathe body (ogive nose, cylinder, boattail, seeker dome, lugs) plus fin sets (planform, count, roll angle,
  station) from a table of public dimensions with sources (as docs/real-weapons.md), and paints PBR bands (olive
  drab, yellow HE band, brown live motor band, white / grey missiles). Its output is committed with the rest; the
  script stays to rebuild or tune one.

2–5 k triangles per store; 20 stores × a few dozen jets is well inside the M4 Pro's budget, and the far LOD caps it.
Not in scope: plumes and motor glow (`mission/trails.gd`), moving fins in flight, aircraft (§3.7).

**Check** (a new Godot test, `test_detailed_models`): with the switch on, every mapped model loads; the store's
pilon helper and AABB the game code reads equal the original's, and the detailed mesh's lug sits on the helper; with
the switch off, `Gltf.object` returns exactly the original.

**Visual check** (the test proves fit, not looks). A comparison sheet per batch, the same shot twice (Models
Original / Detailed) from the pilot guides' shot runner (`tests/godot/_guide_shots.gd`: an airborne start with a
`loadout` on the pylons, the external view, `settings` per shot), in the game's own lighting, not a model viewer's:
each store close up on the pylon (front quarter, side, below), a launch / drop in flight, a chase at 50 m, and a pass
at 300–1500 m to catch the switch to the far LOD popping. Assembled into one HTML page (original | detailed side by
side, as `tools/flight_timeline.py --html`). I look at every picture first for defects a script cannot judge (wrong
colours, missing / stretched textures, black or inside-out faces, floating or sunk lugs, shading seams); you pass or
fail each store on the sheet, and a failed one is just left out of the mapping (it falls back to the original) until
fixed. Cheap numbers alongside: triangles, texture size, frame time on 231 (the busiest mission) Original vs Detailed.

**In motion** (flying, falling, hitting). Stills miss what goes wrong only while a weapon moves:
- **Frame strips and clips** from the same runner: every store launched / dropped onto a placed target
  (`place` + `on_impact`), followed by the F11 weapon view (docs/views.md §4.2: fly-by at 300–700 m) and a chase
  close behind, captured every few frames from release to impact and the explosion, Original | Detailed side by
  side on the sheet (a short video per store too). Bombs level and in a dive, missiles at a crossing and a head-on
  target, the guided ones (Maverick / GBU-15 / Popeye) through their turn.
- **Per-frame checks in the test** (scripted, no eyes needed): the mesh's nose stays on the velocity (≤ 2°, as
  `Basis.looking_at` sets it today); the motor trail starts at the detailed mesh's tail, not in front of or behind
  it (the trail head sits half the model's length back, `player_weapons.gd` — taken from the detailed mesh while it
  is shown, visual only); the mesh stays visible until the detonation frame and is gone on it; its lowest point never
  goes under the ground before the impact; the far LOD swap stays beyond the F11 view's 700 m while that view follows
  the weapon (else it swaps on screen).
- **Known risk to look for**: the weapon's roll is not tracked — `looking_at` uses up = Y, and RIGHT once the
  weapon points straight up or down, so a near-vertical bomb snaps 90° in roll. The 1998 blobs hide it; crisp fins
  will show it. If it shows, keep the roll continuous (visual only, same switch).

**Order.** (1) the switch, the hook, the load-time fit and the test; (2) the FlightGear stores (bombs, AIM-9 /
120 / 7, Maverick, HARM, tanks, pods), compared side by side in the Reference viewer; (3) the FGAddon check; (4) the
built ones for the rest.

## 4. Ranked shortlist

| # | Option | Payoff | Effort | GPU cost (M4 Pro) | Why here |
|---|---|---|---|---|---|
| 1 | Terrain heights in Rust for the sensors (CPU spike fix) — **done** | perf | M | 0 | AI combat worst 4.3 → 0.5 ms (221, live) |
| 2 | Water shader | 3 | M | ~0.2 ms | cheap, visible on every coastal mission |
| 3 | MetalFX upscaling row | perf | S | − (saves) | headroom for 4–8 |
| 4 | F-16D detailed model (FlightGear, GPLv2+) | 5 | L | small | the biggest visible jump; licence clean |
| 5 | F-16D 3D cockpit with live MFDs / Real HUD on the glass, then clickables | 5 | L → XL | small | the "DCS feel"; fixes the real HUD FOV |
| 6 | GPU particle effects + heat haze | 3 | M | ~0.5 ms | combat looks modern |
| 7 | Modern DEM (Copernicus 30 m) | 4 | L | small | real relief; mission impact → opt-in |
| 8 | Vegetation near the ground | 4 | L | 1–2 ms | low-level speed sense; after DEM |
| 9 | Night lighting | 3 | M | small | closes a status gap |
| 10 | F-15C model + cockpit (after its licence is cleared) | 5 | L | small | second jet |
| 11 | Detailed weapon / store models (FlightGear GPLv2+ + our own for the gaps; §3.13) | 3 | M | small | close views of every store |
| — | SSAO / SSIL / SDFGI | 1 now | S | +5 / +12 / +18 ms | nothing to shade over draped terrain; revisit with detailed models |
| — | Volumetric clouds | 4 | L | 3–6 ms | only with MetalFX |

Suggested order: 1 (perf) → 2 + 3 → 4 → 5 → 6 → 7 → 8; a short performance pass (the 2–3 ms streaming spikes, AI
scans on the WorkerThreadPool) before 7–8, which add geometry near the ground.

## Shots (local, `assets/converted/research/`)
`gfx_none.png`, `gfx_shadows_off.png`, `gfx_shadows_hq.png`, `gfx_ssao.png`, `gfx_ssil.png`, `gfx_glow.png`,
`gfx_vol_fog.png`, `gfx_sdfgi.png`, `gfx_fsr_0.67.png`: mission 311 over Ramat David at 60 m, 3840×2160, one feature each.

## References
- FlightGear F-16 (GPL-2.0-or-later, `copyright.txt`): https://github.com/NikolaiVChr/f16
- Zaretto F-15 / F-14 (no licence file): https://github.com/Zaretto/fg-aircraft
- F-4X (GPLv2+): https://github.com/Zaretto/F-4X
- FGAddon aircraft list: https://sourceforge.net/p/flightgear/fgaddon/HEAD/tree/trunk/Aircraft/
- FlightGear policy (FGAddon GPLv2+ since 2015): https://www.flightgear.org/about/policy , https://wiki.flightgear.org/FGAddon
- Kfir C.10 on Sketchfab (CC BY, game rip — not used): https://sketchfab.com/3d-models/kfir-c10-block-60-c6534a1cac1e4a13817ac6f8eb35fe96
- Godot 4.7 RC notes: https://gamedev.net/news/3813-release-candidate-godot-47-rc-1/
