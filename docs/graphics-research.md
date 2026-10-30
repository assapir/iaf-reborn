# Better graphics: research and options (2026-10-16)

This doc lists what could make the game look better, what each option costs on our machine (Apple M4 Pro, Godot
4.7.2 Forward+ on Metal 4.0), and a suggested order. Options marked **done** or **built** link to the doc that
describes them (mostly docs/rendering.md); the rest are proposals. Key facts:

- Every option is an **opt-in switch**: the graphics ones on Preferences → Graphics → MORE, the rest on Extras. The
  original look stays the default (docs/deviations.md).
- The game is **GPU-bound** where it drops below the display refresh; the CPU shows as short **spikes** (§1).
- The ranked shortlist and the suggested order are in §4.
- Screenshots referenced below are rendered locally into `assets/converted/research/`. They show the original art, so
  they are never committed.

Terms used in this doc:

| Term | Meaning |
|---|---|
| AGL | above ground level |
| AI | the computer-controlled aircraft and units |
| DEM | digital elevation model (a grid of terrain heights) |
| HUD | head-up display |
| MFD | multi-function display |
| RWR | radar warning receiver |
| FOV | field of view |
| LOD | level of detail (simpler versions of a model for distance) |
| PBR | physically based rendering (textures for colour, normal, roughness, metal, occlusion) |
| glTF / glb | the open 3D model format Godot loads (glb is the single-file form) |
| MSAA / FXAA | multisample / fast approximate anti-aliasing |
| SSAO / SSIL | screen-space ambient occlusion / screen-space indirect lighting |
| SDFGI | signed-distance-field global illumination (Godot's real-time bounce light) |
| FSR | AMD FidelityFX Super Resolution (an upscaler) |
| OSM | OpenStreetMap |
| CC0 / CC BY / NC / ND | Creative Commons: public domain / attribution / non-commercial / no derivatives |
| ODbL | Open Database License (OSM's licence) |
| DCS | DCS World, the current study-level flight simulator we use as the visual bar |

## 1. Baseline: where the frame goes

This section measures where a frame's time goes today. Result: the GPU sets the frame rate where it drops; the CPU
adds only spikes.

**Tools:**
- `tests/godot/_flight_bench.gd`: frame rate over the terrain, per leg.
- `tests/godot/_cpu_profile.gd` (ours): each system's `_process` timed on the main thread, and the render thread's
  CPU time.
- `tests/godot/_gfx_proto.gd` (ours): switches one rendering feature on, measures its frame time at 4K and takes a
  shot.

**Metal caveats (measured):**
- Metal presents at the display's refresh even with vsync off. A frame that fits never shows below the refresh
  time: 6.90 ms on the 144 Hz screen, 16.67 ms on the 60 Hz one.
- Godot reports **no GPU time on Metal** (`viewport_get_measured_render_time_gpu` = 0).
- To expose a GPU cost, `_gfx_proto.gd` renders 4K at a 1.6 render scale, so that the GPU sets the frame time
  rather than the display.
- Xcode's Metal System Trace would give exact GPU times (not done).

| Run (1920×1080) | 150 m AGL | 1500 m | 6000 m | Note |
|---|---|---|---|---|
| 311, default settings, frozen flight | 144.9 fps (6.90 ms) | 144.9 | 144.9 | capped at the 144 Hz refresh (steady state) |
| 311, BENCH_BEST (all sliders up, MSAA 4×+FXAA, closeup, atmospheric sky, modern imagery) | 144.9 | 144.9 | 144.9 | still capped |
| 221, live simulation (13 AI jets, SAMs) | 6.91 ms | | | capped |
| 231, live simulation (MiGs, ground units, low level) | **10.9 ms (92 fps)** | | | over the cap: GPU-bound (below) |

The numbers above are warm runs, each alone on the machine. The first runs after start-up are slower (60–82 fps:
shader compilation, disk cache). Runs in parallel with other Godot processes are noisy.

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

**Verdict:**
- On the M4 Pro the main thread uses ≈ 2–2.5 ms of a frame; the render thread ≈ 0.45 ms.
- The game is **GPU-bound** where it drops below the refresh: 231 at low level takes 10.9 ms, of which 2.5 ms is CPU.
- The CPU shows as **spikes**, with little steady load. The spikes come from:
  - AI combat's sensor scans (5–13 ms worst). The terrain line of sight samples the GDScript `mission_ground()`
    through a Callable once per sample (radar.rs `line_of_sight`).
  - terrain streaming's main-thread part (≈ 2–3 ms worst);
  - the mission runtime's first events (8 ms once).
- The "13–24 fps dips" once reported do not reproduce on this machine when warm (inferred: a heavier earlier build
  or cold caches).

## 2. Where the work runs (CPU → GPU, Rust or threads)

This section lists each measured hotspot and where its work should run: on the GPU, in Rust, or on worker threads.

| Hotspot (measured) | Today | Recommendation | Payoff | Effort |
|---|---|---|---|---|
| Terrain line of sight in sensor scans: 5–13 ms spikes (measured before the fix) | **done**: `IafHeights` (iaf_avionics::heights) holds the streamed full-detail nodes terrain.gd loads; `world::terrain` answers `mission_ground` from it, with no Callable per sample (same nodes and interpolation, ≤ 1 cm from the float32 GDScript path; line of sight identical on 400 pairs, test_heights.gd) | keep | 400 checks 93 → 2.4 ms; mission 221 live: AI combat worst 4.3 → 0.5 ms | M |
| Terrain mesh / heights | already on the GPU: heights sampled in the vertex shader; JPEG decode, mipmaps, BC1 on 6 worker threads | keep; batch the node swaps to cut the main-thread part (2–3 ms worst on splits) | small | S |
| Explosions, smoke, trails, decoys | Original: MultiMesh billboards (GPU-instanced), positions filled by GDScript each frame | **GPUParticles3D** — **done** (Particle effects = Detailed, §3.4) | the puffs per frame 0.67 → 0.08 ms CPU | M |
| HUD / MFD drawing (`_draw` every frame) | `_process` < 0.02 ms; the `_draw` canvas calls run on the main thread (small; not separately measured) | redraw only on change, or a SubViewport per MFD updated at the original's rate; low priority, since it is a minor cost today | low | S |
| Vegetation / clutter (new) | — | **MultiMesh**, placement from the WorldCover classes on worker threads or a compute shader | needed for §3.6 | — |
| Flight model, AI brains, mission runtime, weapons | Rust (FM = flight model, avionics) + GDScript (brains, runtime) | keep on the CPU: the code is branchy and serial, a poor fit for the GPU. Rust per our rule; brains / sensors on the WorkerThreadPool (the M4 Pro has 12+ cores) | keeps headroom as missions grow | M–L |

## 3. Options

Each option below gives its visual payoff, its effort and its cost on our machine.

- **Payoff:** 1–5 (visual).
- **Effort:** S (days), M (a week or two), L (weeks), XL (months).
- **Cost:** the measured GPU frame time where measured, else an estimate. Measured costs are lower bounds: the base
  4K×1.6 frame still fits a 60 Hz frame.

### 3.1 Sun shadows (already built: Graphics SHADOWS, docs/front-end.md §12)
Built: Godot directional shadows on aircraft, buildings and units, from 08:00 to 17:00, as the original's projected
shadows.
- **Measured:** shadows on vs off, and the 4-split 8192 atlas at high soft quality, all fit the frame at 4K×1.6 (no
  measurable cost).
- **Payoff:** already had. A "shadows: high" Extras row (4 splits, 8K atlas) would sharpen self-shadowing on aircraft,
  cheaply.
- **Metal:** shadow maps work well on tile GPUs.
- **Recommendation:** S, add the "high" row.

### 3.2 Screen-space lighting: SSAO / SSIL / SDFGI / glow
These effects add shading from nearby geometry. Over our terrain they show no visible change, at a high cost.
- **Measured** (4K×1.6, frame ms vs the 16.7 base): **SSAO ≥ +4.8**, **SSIL ≥ +12.1**, **SDFGI ≥ +18**, glow ≥ +1.2.
- **Look** (shots `gfx_none.png`, `gfx_ssao.png`, `gfx_sdfgi.png`): **no visible difference from the cockpit over the
  terrain**. The ground is a heightfield draped with photos, with nothing for ambient occlusion to darken, and the
  cockpit is 2D art. The effects would matter only on detailed 3D models (§3.7) and on buildings in external views.
- **Metal:** bandwidth-heavy (several full-screen passes at full resolution), the expensive kind on a tile GPU.
- **Recommendation:** **skip now**. Add SSAO only with detailed models, in external views only. Glow (bloom) for the
  sun and explosions: +1.2 ms, payoff 2, S.

### 3.3 Modern DEM (SRTM / Copernicus GLO-30) — payoff 4, effort L
A 30 m DEM gives real relief; the work is a converter plus keeping physics, AI and missions on the same surface.
Sources, licences and the two phases (normal map, then geometry): docs/imagery-research.md §3, §4.5.
- **Today:** the original's heights are coarse (level-6 grid), and the physics uses the same surface.
- **Copernicus GLO-30 attribution:** "© DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 provided
  under COPERNICUS by the European Union and ESA".
- **Gain:** real ridgelines, wadis and the Golan escarpment, and normals for lighting, so the relief shows in the
  light as well as in the outline.
- **Work:** a converter like `iaf-imagery` (GDAL is already a setup dependency) that warps the DEM into the game frame
  (docs/georef.md); finer height nodes; the physics and AI on the same surface. Airbases must stay flat (blend to the
  original around them), and mission objects placed on the original heights need re-seating.
- **GPU:** finer vertex grids near the camera, small on the M4 Pro.
- **Risk:** missions tuned to the original terrain (masking routes like 313) change, so it must stay an opt-in.
- **Recommendation:** worth it, after the cheaper items; pairs with the modern imagery already built.

### 3.4 Effects: GPU particles (explosions, smoke, contrails, heat haze) — payoff 3, effort M — **done** (docs/rendering.md §6)
- **Today:** soft procedural billboards in MultiMeshes (damage_effects.gd, trails.gd), with the original's sizes and
  timings.
- **Option:** GPUParticles3D with flipbook textures (our own or CC0, e.g. from Kenney / ambientCG), collision with the
  heightfield, a heat-haze distortion pass behind the engines (a Compositor effect or a refraction shader on the
  afterburner), and contrails above a height / temperature.
- **GPU:** modest (particles are cheap; the distortion is one extra pass). **Metal:** works well.
- **Built** (docs/rendering.md §6): three particle pools, a heat-haze cone behind each nozzle and contrails, with the
  original's spawns and timings; ≈ 0.3 ms at 1080p in a heavy burst. Not built: flipbook textures and heightfield
  collision.

### 3.5 Water shader — payoff 3, effort M — **done** (docs/rendering.md §1.3)
- **Built:** Graphics → MORE → Water: waves, glint and sky reflection; ≈ 0.23 ms at 1920 × 1080 with water over the
  whole view.
- **Shoreline foam:** left to the photo's own surf; a procedural foam on the 96 m mask would draw blocks.

### 3.6 Vegetation / ground clutter — payoff 4 (low level), effort L
- **Option:** trees, orchards and scrub as MultiMesh instances near the ground. Placement comes from the ESA
  WorldCover classes (CC BY 4.0, already used for imagery: tree cover, shrubland, cropland) and the imagery's own
  colour. They fade out by 1–2 km.
- **Gain:** the sense of speed at 50–100 ft.
- **GPU:** instancing is cheap on Metal. The cost is overdraw of alpha-tested leaves; use impostor cards (flat
  billboards) to limit it.
- **Assets:** CC0 tree models (Kenney, Quaternius) or our own.
- **Recommendation:** after the DEM and water.

### 3.7 Detailed aircraft models — payoff 5, effort L per jet (XL for all)
The 1998 models have ≈ 800–3000 triangles with 256-px textures (f16_h: 57 nodes). Open models exist for some jets;
the F-16D has the cleanest licence.

**Candidates (licence verified where stated):**

| Jet (variant needed) | Candidate | Licence (checked) | Notes |
|---|---|---|---|
| F-16D (two-seat) | FlightGear F-16 `github.com/NikolaiVChr/f16` | **GPL-2.0-or-later** (`copyright.txt`: "version 2 of the License, or (at your option) any later version", all files) — compatible | **Built** from `Models/f16.ac` (the textured single-seat F-16C with separate moving parts, 2048² UVs, three IAF desert liveries) made two-seat by `tools/f16d/rig.py` ([aircraft-models.md](aircraft-models.md)). `Models/F-16D.ac` is a shared untextured AI model: one mesh with its stores baked in |
| F-15C (single) | Zaretto F-15 `github.com/Zaretto/fg-aircraft` (`aircraft/F-15`, also FGAddon `F-15`) | **GPL-2.0-only** (author, issue #211): can't ship in our GPL-3.0-or-later repo; setup can download and convert it locally | external model by Enrique Laso; C and D variants; cockpit with photo textures |
| F-4E / Kurnass 2000 | FGAddon `McDonnell-F-4-Phantom`; `github.com/Zaretto/F-4X` (GPLv2+, early alpha, an F-4S) | GPLv2+ (F-4X README); FGAddon per file | F-4E differs (gun nose); Kurnass 2000 adds its own avionics bumps |
| Mirage IIICJ | FGAddon `MirageIII`, `MirageIIIE` | FGAddon policy (check files) | the IIICJ is close to the IIIC |
| Kfir C2/C7 | none open; Sketchfab "Kfir C.10 Block 60" (CC BY, but taken from War Thunder — **rights doubtful**, don't use) | — | would be our own build from the Mirage III / 5 base |
| Lavi | none | — | our own |
| F-35I (F-35A) | FGAddon `F-35B` (FGMEMBERS/F-35B 2726b3b); PaoloAmoroso/F-35A (80500454) | F-35B: GPL-3.0 (`License.txt`); F-35A: a GPL-2.0 text over an FGUK airframe (FGUK hangars are CC BY-NC-SA), so **provenance doubtful** | the F-35B is the STOVL variant (lift fan doors, swivel nozzle, no gun hump) with ≈ 16 k triangles, below our F-35I's 52.8 k (andertan, CC BY 4.0); the F-35A has ≈ 240 k. Checked 2026-10-30: **keep ours** |
| MiG-21bis (AI) | `github.com/l0k1/MiG-21bis` (9ca6f5b) | GPL-3.0 (`License.txt`) | ≈ 15 k triangles (`MiG-21bis.ac` 1.55 MB); its R-3S already a store |
| MiG-29 9-12 (AI) | `github.com/Mercenary-Mercury/MiG-29_9-12` (d4a299b) | GPL-3.0 (`LICENSE`) | ≈ 21 k triangles (`MiG-29.ac` 2.1 MB), external model by Enrique Laso Leon; two 1024-class textures and a RuAF livery; every surface animated in `MiG-29.xml` (gear and doors, flaps, LERX flaps, ailerons, rudders, stabilators, airbrakes, canopy, 52 nozzle petals each side). Open: not built yet |
| MiG-23MLD (AI) | `github.com/xcvb85/MiG-23MLD` (df6c532) | GPL-3.0 (`LICENSE`) | ≈ 16 k triangles (`model.ac` 1.6 MB), 3D by Tim Samedov. Open |
| Su-27SK | `github.com/yanes19/SU-27SK` | conflicting (GPL-2.0 files, README GPLv3+) over an FGUK airframe: don't use | ≈ 9 k triangles |
| Su-22 / Su-24 (AI) | none open in FlightGear (the su22-fg-dev Su-22M4 is unreleased, non-commercial); Sketchfab CC BY: Su17 by manilov.ap (26 k), Su-24 by Chenzoss (120 k) — provenance unchecked | — | keep the originals |

**Licence rules:** CC BY is usable with attribution; NC and ND are not usable. Our repo is GPL-3.0-or-later, so
GPL-2.0-only files cannot ship in it.

**F-15, checked 2026-10-26.** The Zaretto F-15C/D is still the only open candidate with every moving part split and
hinged (gear, doors, flaps, ailerons, stabilators, rudders, canopy, air brake, hook, nozzles) and a full cockpit:
3D model by Enrique Laso, rig by Richard Harrison, cockpit photo textures by GeneB. Its licence is not stated
anywhere: GitHub reports none, the repo has no COPYING and no file headers, zaretto.com says "All rights reserved",
and the FGAddon copy was first committed on 2015-07-04, before FGAddon recommended GPLv2+. Answered on 2026-10-27 by
Richard Harrison (Zaretto/fg-aircraft issue #211[^zaretto211]): the repository is **GPL-2.0-only**, and a change
would need every copyright holder in its AUTHORS file. GPL-2.0-only files can't ship in our GPL-3.0-or-later repo,
but anyone may use and modify them, so setup can download the model at a pinned commit and convert it on the
user's machine, like the game's own data (inferred). Rejected:
- the Sketchfab F-15Es by bohmerang (CC BY-NC-SA) and andertan (CC BY-ND), and ARAZ BASIC's "free rig", which is
  built on bohmerang's;
- low-poly CC BY F-15s (2.7–13.6k triangles), no better than the original;
- "[War Thunder]" F-15 uploads (game rips);
- CGTrader, TurboSquid and 3dcadbrowser models, which can't be redistributed.

The FGUK F-15E has no stated licence and is an alpha. NASA 3D Resources and Smithsonian 3D have no F-15. Fallback:
RaduCarstean's "F-15 Eagle No Textures" (Sketchfab, CC BY 4.0, 72k triangles), a bare mesh needing UVs, paint,
split surfaces and LODs. No open F-15I Ra'am exists (inferred: our own conversion of an F-15D; done 2026-10-30 from the same Zaretto files: aircraft-models.md §6.7). Done 2026-10-28: setup downloads the
Zaretto F-15C at a pinned commit and converts it in Rust (aircraft-models.md §6).

A second, wider search (2026-10-26) found nothing better. Checked:
- **The old FlightGear `f15c`** (Fabrice Kauffmann, FGMEMBERS/f15c): fgdata's GPL v2 text with no "or later", and
  only a little better than the original.
- **Two maybes on Sketchfab:**
  - mgg8's "F-15A Eagle — USAF 76-0020, Duxford" (CC0, 131k triangles, 17 textures, no split surfaces): an
    AI-assisted procedural model whose author says details are approximate; it needs checking against photos.
  - Spark_Customs' F-15E (CC BY, 205k triangles, no textures, origin unverified).
- **One maybe on OpenGameArt:** MNDV.ecb's "f 15" (OGA-BY 3.0, no real textures).
- **Too low-poly:** YSFlight's stock F-15 (BSD-3).
- **Rejected:**
  - non-commercial licences: YSFlight community F-15s (YS BY-NC-SA), BlendSwap 17592 (CC BY-NC), the skyfall
    repo's model (non-commercial assets);
  - restricted or paid: Free3D 1387 (editorial only), the itch.io F-15A (paid, no licence);
  - rips: 42manako's F-15I ("not my model"), Jeyhun1985's F-15I / E / C (same triangle counts as the War Thunder
    uploads), kositsuwan's and MattDoesBlender's F-15Es (origin unknown);
  - low-poly CC BY F-15s (14–45k triangles).
- **Nothing on** Poly Pizza, Wikimedia Commons, Printables, Cults or GitHub file search. The forks FGMEMBERS/F-15
  and Megaf/F-15 are Zaretto copies without a licence.
- **Not verified:** Thingiverse models (pages blocked).

**Fitting one** (a pipeline like `tools/f35i/`):
1. Convert AC3D → glTF (Blender) and scale to the original's dimensions.
2. Name the moving parts with our `<part>1/2` hinge helpers (gear legs, flaps, ailerons, elevons, canopy, air brake,
   nozzle, hook; docs/part-animation.md, docs/adding-a-plane.md).
3. Place the `Station*` helpers at the original's pylon positions (stores must hang where the original's do), the eye
   point, and the afterburner `EngineL/R` helpers.
4. Make LODs (full / 30 % / impostor) for AI use.
5. Make PBR textures (repaint in IAF camouflage: ours).

**Wheels:** the original's wheels never roll. Part ids 0x21–0x26 are hidden for aircraft (docs/part-animation.md),
and no aircraft model has Wheels frames. Built: Graphics → MORE → Rolling wheels turns a model's own wheel frames
(today the F-35I's; docs/part-animation.md §2.2).

**Switch:** Preferences → Graphics → MORE → Models: Original / Detailed.

**F-16D: stage 1 done** (2026-10-17, [aircraft-models.md](aircraft-models.md)): 51.4 k triangles, KTX2 textures in a
3.8 MB glb, runtime LODs; the IAF dorsal spine (the Brakeet's avionics hump, level under the canopy as on IAF photographs, 2026-10-29) and the
centreline pylon added. Next for DCS level: our own UV layout (the FlightGear UVs stretch the fuselage sides), a
hand-painted 4K livery with stencils, glass reflections, a detailed cockpit-view model.

**Own jet in the cockpit views: built** (2026-10-17, docs/views.md §4.3). Looking aside or back from the cockpit shows
the jet's wings, fuselage and canopy frame, as the original draws them: each jet's `<plane>_bc` model. The F-35I has its
own (`tools/f35i/bc.py`).

**Effort per jet:** L. The F-16D first (≈ 2–3 weeks), then the F-15C.

**GPU:** 26 k triangles × a few jets is nothing on the M4 Pro; textures 2–4K per jet.

### 3.8 Cockpit: better 2D, 3D, clickable — payoff 5, effort L → XL
Three steps, each building on the last. Recommended path: the F-16D 3D cockpit with live MFDs / HUD first, then its
clickables, then the F-15C.
- **(a) Better 2D** (S–M): today the 1998 panels are upscaled 4× (Lanczos, never AI). Higher resolution needs redrawn
  art (ours): a lot of work for the 2D look, and a low payoff compared with (b).

  **Tested and dropped (2026-10-26): upscaling the panels better.** The panels are 24-bit renders (1920 × 352–374,
  44k–85k colours), not palette art; the exe shows 640 px of them across the screen, so 1440p is 4× and 4K 6×.
  Methods tried at ×2 and ×4 on the F-16, F-15, MiG-29 and F-4E panels (a gauge, a labelled switch panel, an MFD
  bezel, worn metal), Iris Xe:

  | Method | Labels and digits | Lines | Finish and colour | Time, one panel ×4 |
  |---|---|---|---|---|
  | Lanczos3 (what setup does) | soft | soft | exact | ms |
  | Lanczos3 + unsharp | a little crisper | better | exact | ms |
  | Pixel-art scalers (scale2x / hq2x / xBR) | jaggy | jaggy | as nearest | ms |
  | Real-ESRGAN x4plus (AI) | wrong letters (MODE → "VODE", 8 → "S") | crisp | wear erased, reds shift orange | 31–38 s |
  | Real-ESRGAN x4plus-anime (AI) | garbled, posterised | cartoon outlines | flattened | 11–26 s |
  | Real-ESRGAN animevideov3 (AI) | kept; text under 5 px stays mush | crisp | mostly kept | 2–7 s |

  Pixel-art scalers need flat colours, so they fail on these renders. The AI models also lose the cyan colour key
  (exact-key pixels drop from 56 % to 0.05 %), so a mask would have to come from the source. Upscayl's popular
  models (UltraSharp, Remacri) are CC BY-NC-SA, unusable in this GPL project. The best result (animevideov3) was not
  worth a setup step and an outside binary; the user dropped the idea. Sharp text needs drawing by the game itself
  (as Better cockpit and the crisp MFD pages do), or a 3D cockpit (b).
- **(b) 3D virtual cockpit** (L for the F-16D): the FlightGear F-16 cockpit (GPL-2.0-or-later, above) is a complete
  modelled pit: MFDs, DED (data entry display), RWR, CDU (control display unit), ICP (integrated control panel) and
  gauges. It must be live:
  - our MFD and RWR drawers rendered into SubViewport textures on the 3D screens;
  - the Real HUD drawn on the combiner glass at its real field of view. The glass becomes the real one, so the
    HUD's field of view is the real one too;
  - the gauges' needles driven from our cockpit state, and the lamps.

  Head movement: free look already exists (views.gd); TrackIR-style 6-DoF (six degrees of freedom) later; VR
  possible with Godot's OpenXR (not on macOS). Switch: Extras "Cockpit: Original 2D / 3D". GPU: a few SubViewports at
  MFD resolution, cheap. F-15C: the Zaretto cockpit (licence to clear, above).
- **F-35I panel: built** (2026-10-17, docs/f35i.md §4.2–4.3): a modelled panel around the panoramic display
  (`tools/f35i/cockpit3d.py`), with the helmet display's NAV steerpoint cues.
- **(c) Clickable** (M after b): mouse-look and click, with a highlight. Switches map to our commands
  (docs/controls.md): master arm, gear, flaps, hook, chaff / flare, ECM (electronic countermeasures), MFD OSBs
  (option select buttons; already clickable in 2D: docs/mfd.md), radar mode, autopilot. The keyboard keeps working.

#### Sufa options (research 2026-10-30)
What a 3D cockpit for the F-16I Sufa can be built from. The real one (docs/f16i.md §4): an F-16D Block 52+ with
three colour displays in each cockpit (six 484 × 484 colour LCDs in all; the 4 × 4 in MFDs are Astronautics'), an
Elbit wide-angle HUD, the DASH IV helmet in both seats, and a rear seat for a weapons systems officer (WSO) that one
switch turns into an instructor's[^cp-du][^cp-at]. Today the Sufa shows the F-16's 1998 2D panel with our live colour
MFDs (docs/mfd.md §9) and the Real HUD on it.

**What the FlightGear F-16 holds** (`~/.cache/fg-f16`, pinned commit ef4f192, the source of the Detailed F-16D):
- **Licence:** `copyright.txt` puts every file in the package under GPL-2.0-or-later (© 2023 Erik Hofman, authors
  in `authors.txt`; cockpit textures and layout by Martin "Pegasus" Schmitt and Prohm "Rama" Snitwong, MFD / HUD /
  CDU / PFD work by Nikolai V. Chr.)[^cp-fg]. No file carries a different licence of its own.
- **One cockpit for every block:** `Models/Cockpit/Main/cockpit.xml` is the only interior; the `F-16C-40` /
  `F-16C-50` cockpits are commented out in `F-16.xml` and absent. The blocks differ by texture and by selected
  objects: a panel sheet per block in `Textures/Block-panels/` (blck10 … blck60, MLU), MLU and Block 50 console
  textures, a Block 10 stick, the US or the MLU RWR head (`US_threat_warning_prime` / `MLU_threat_warning_prime`).
- **Front seat, complete:** tub and glareshield, two MFDs (`Avionics/MFD`, bezel 0.141 m square, 20 OSBs each; the
  screens are FlightGear canvases), ICP (integrated control panel), DED (data entry display), CDU, a small PFD, EHSI,
  ADI, standby ADI, airspeed, altimeter, VSI, AoA, fuel flow and fuel quantity gauges, both side consoles and
  auxiliary consoles (MLU-labelled), throttle, stick, rudder pedals, the eyebrow lamp panels, the ACES II seat,
  kneeboards, the HUD (`hud.ac`, the dash-34 shape, 0.19 × 0.21 m; `f16_war_hud.ac`, the LANTIRN wide-angle HUD)
  and the JHMCS helmet (`hmcs.ac`).
- **No rear seat:** the package has no F-16D interior; `F-16D.ac` is a bare shell (two objects). Our
  `tools/f16d/rig.py` already makes the two-seater for the exterior: it stretches the canopy and places a second,
  decimated copy of the front tub, seat and pilot (`cockpit()`).
- **Canopy frame:** part of the exterior model (`f16.ac`), seen from inside; our rig rebuilds the two-seat centre bow.
- **Size** (counted from the `.ac` files, `refs − 2` triangles per surface): about 147 k triangles for the whole
  interior without the kneeboards and the pilot. The consoles are most of it: left console 36 k, left aux 30 k, right
  console 18 k, ICP 14 k, seat 13 k; the tub itself 6 k, each MFD 1.6 k. Textures: about 9 MB of PNGs, mostly 256²
  to 1024², with four 1024 × 2048 console sheets.

**Other open or CC models** (Sketchfab API, downloadable, checked 2026-10-30):

| model | licence | triangles | verdict |
|---|---|---|---|
| "F16C Block 50/52 + Cockpit", graphXDoses (2014, Blender)[^cp-gxd] | CC BY | 27 k (with the airframe) | own work; single seat, half-textured work in progress, below the FlightGear pit: a cross-check only |
| "F-16 Fighting Falcon, GameReady", rave.Ar4ik[^cp-rave] | CC BY | 115 k (with the airframe) | a baked cockpit texture set; provenance open; no gain over FlightGear's live parts |
| "General Dynamics F-16D Block 60", MirzaArrafiERV_45[^cp-b60] | CC BY | 62 k | the Block 60 panel (three large displays) is another layout; provenance open |
| "F-16C Cockpit Photogrammetry", VTX_car | CC BY-NC-SA, tagged DCS | 989 k | rejected: non-commercial, likely a sim capture |
| "F-16 Fighting Falcon - Free", bohmerang | CC BY-NC-SA | 30 k | rejected: non-commercial |
| "F-16I Sufa (War Thunder)", KojfDiscord (two) | labelled CC BY | 305 k | rejected: War Thunder rips (Gaijin's rights) |
| DCS F-16I mod (forum.dcs.world) | — | — | rejected: built on Eagle Dynamics' cockpit |

CC BY 4.0 work may be combined into our GPL-3.0 work[^cp-fsf]; each would need its credit (docs/credits.md, the
setup wizard's Attributions, the credits roll).

**Photos for the Sufa's own parts (Wikimedia Commons):** no straight-on photo of a Sufa's front or rear panel was
found (open; Commons' search was rate-limited partway). Usable: two crews in an F-16I with the canopy open, showing
the rear coaming and the canopy frame (IDF, CC BY 2.0)[^cp-ph-cos]; a pilot in a Sufa's front seat beside the canopy
rail (IDF Spokesperson's Unit, CC BY-SA 3.0)[^cp-ph-ad]. For the F-16 panel in general: an F-16C panel (PD)[^cp-ph-16c],
an F-16 trainer panel (PD)[^cp-ph-aa], an F-16AM MLU cockpit (CC BY-SA 2.0)[^cp-ph-efka]. Where the third display
sits in each Sufa cockpit: open.

**Options:**

| | option | licence | completeness | effort | Iris Xe cost |
|---|---|---|---|---|---|
| A | **Sufa 2D panel rendered from the FlightGear pit**: Cycles from the game's eye into the 1920 px panel strip, as `tools/f35i/cockpit3d.py`; the bezels where `[MFD]` puts our live MFDs, a third display through `MiddleActive` (docs/mfd.md §7) | GPL-2.0+ | front seat, HUD frame, consoles in the pan; no rear seat | S–M (≈ 1 week) | none: a 2D panel as today |
| B | **Real-time 3D front cockpit from FlightGear**: Blender → one glb with KTX2, as `tools/f16d/rig.py`; Block 50 textures | GPL-2.0+ | front seat complete; the canopy frame from our F-16D | L (2–3 weeks; (b) above) | ≈ 60–80 k triangles with the consoles decimated to 30–50 %, ≈ 20–30 MB of textures in VRAM (inferred, not measured) |
| C | **B + Sufa panels (hybrid)**: the third display, colour MFD glass, the Elbit HUD's frame, Sufa labels; our own parts in Blender | GPL-2.0+ and ours | the front seat Sufa-like where photos allow | M on top of B | as B |
| D | **Rear WSO cockpit**: B's tub copied aft (as `rig.py` does outside), no HUD, its displays, the WSO's controllers (open) | GPL-2.0+ and ours | rear seat | M after B | a second eye point; one cockpit drawn at a time |
| E | **Our own model from photos**, all Blender, as the F-35I | ours | what the photos show; the Sufa panel photos are missing | XL (6+ weeks) | as B |
| F | **A Sketchfab base** | CC BY | single seat, less detail than FlightGear | M, then C's work anyway | 27–115 k triangles |

**How B–D fit our architecture:**
- **Switch:** Extras "Cockpit: Original 2D / 3D"; the 2D panel stays the default (a docs/deviations.md entry when
  built).
- **MFDs:** `mfd.gd` / `f16_mfd.gd` draw into a SubViewport per display (484 × 484, the Sufa's resolution) whose
  texture is the bezel's emissive screen: three per cockpit ≈ 0.7 Mpx per frame. The EO camera already renders
  through a SubViewport (`cockpit.gd`). OSB clicks: a ray onto the bezel's button rectangles, as (c).
- **HUD:** the Real HUD is collimated: its symbols sit at infinity, so it is not a texture on the glass. It is drawn
  as today (screen space, at the real IFOV, docs/real-hud.md "Real view"), masked to the combiner's outline as seen
  from the current eye. The glass is then the real one and the symbols stay on the world as the head moves
  (inferred). The Sufa's Elbit HUD field: open (the F-16C/D's 20° × 13.5° until a source is found).
- **DASH:** a helmet display draws in screen space wherever the pilot looks (docs/real-hud.md "DASH helmet"); a 3D
  cockpit leaves it as it is.
- **Head:** free look (`views.gd`) turns a camera at the design eye; snap views as today. 6-DoF head tracking
  (TrackIR / opentrack) adds the head's position; opentrack's UDP output is one way in (open: not tried). Near plane
  0.1 m, as the F-35I (docs/f35i.md §4.4).
- **Gauges and lamps:** FlightGear's XML animations name each needle's object and axis; our cockpit state (the values
  `gauges.gd` / `instruments.gd` draw today) drives them.
- **Iris Xe:** the cockpit covers the lower screen, so less 3D world is drawn behind it. The sun's shadows over the
  panel are the main unknown (open: measure with `tests/godot/_flight_bench.gd` under the GPU bench lock). Budget it
  as the Detailed F-16D (51 k triangles, docs/aircraft-models.md).

**Open questions:** the Sufa's panel layout (the third display's place, the up-front controls, the rear seat's
controllers); the Elbit HUD's frame and field; the DASH IV's differences from the DASH III; whether FlightGear's MLU
console labels match a Block 52 (they are the closest set).

**Recommendation** (smallest useful first):
1. **A:** the Sufa's own 2D panel rendered from the FlightGear pit, with our live colour MFDs and a third display. No
   runtime cost; it reuses the 2D cockpit, the F-35I's render script and `[MFD]`.
2. **B:** the real-time 3D front cockpit behind the Extras switch: MFDs in SubViewports, the Real HUD masked to the
   combiner, the main needles live. Measure on the Iris Xe before going on.
3. **C:** the Sufa-specific parts, as photos are found.
4. **D:** the rear WSO seat as a second view.
5. **(c)** clickables, then 6-DoF head tracking.

E and F add nothing over FlightGear for the F-16: not recommended.

### 3.9 Atmosphere, clouds, fog — payoff 3, effort M
- **Built:** the atmospheric sky and the cloud layer (docs/rendering.md).
- **Volumetric fog:** measured free at our density, and it hides little at flight distances.
- **Built: volumetric clouds** (Graphics → MORE Clouds Volumetric, rendering.md §2.1: a compositor effect at half size; 8–18 ms on the Iris Xe at 1080p, §2.2). Researched before: payoff 4, but a
  cost of ≥ 3–6 ms at 1080p on tile GPUs (bandwidth), so only with upscaling (§3.10).

### 3.10 Upscaling for headroom: MetalFX — done
**Built:** Preferences → Graphics → MORE → Upscaling: Native / Quality / Balanced (docs/rendering.md §1). Quality renders the 3D
scene at 0.77 of the window, Balanced at 0.67. MetalFX spatial scales it up on Metal; FSR 1 does it on other drivers.
The Anti-aliasing row keeps working at the lower resolution. The 2D cockpit, HUD and MFDs stay at the window's
resolution.

**Measured** with `tests/godot/_upscale_probe.gd`: mission 231, M4 Pro, 3600×2160 window on the 120 Hz screen. One
process cycles every mode 12 times, so load from other processes hits every mode alike. Median frame time:

| Mode | Frozen | Frozen + SSAO + SSIL | Live simulation | Live + SSAO + SSIL |
|---|---|---|---|---|
| Native, MSAA 4× (default) | 6.42 ms | 15.61 ms | 6.38 ms | 12.91 ms |
| Native, AA off | 4.38 | 11.81 | | |
| Native, TAA | 8.30 | 16.04 | | |
| **Quality**: MetalFX spatial 0.77 + MSAA 4× | 5.79 | 10.97 | 6.09 | 9.05 |
| **Balanced**: MetalFX spatial 0.67 + MSAA 4× | 4.98 | 9.29 | 5.74 | 8.11 |
| FSR 1 0.77 + MSAA 4× | 5.87 | 11.25 | | |
| MetalFX temporal 0.77 / 0.67 / 0.5 | 9.43 / 7.95 / 6.77 | 15.68 / 13.62 / 9.97 | | |
| FSR 2 0.77 | 11.26 | 16.11 | | |

- **Spatial wins.** Quality saves 0.6 ms on today's scene and 4.6 ms with a heavy per-pixel load (SSAO + SSIL);
  Balanced saves 1.4 ms and 6.3 ms. The saving grows with the per-pixel cost, so it is headroom for §3.9 clouds and
  the detailed models.
- **Temporal costs more than it saves.** MetalFX temporal and FSR 2 need motion vectors, like TAA. That pass costs
  about 4 ms at 4K here (native TAA 8.30 ms against 4.38 ms with AA off).
  Built later as an opt-in Anti-aliasing choice (FSR 2; MetalFX on Metal), for players who use TAA anyway: it
  replaces TAA and runs at the Upscaling row's scale (docs/rendering.md §1.7).
- **At 1920×1080** every mode measures 3.3–3.9 ms frozen: the GPU has room to spare at that size. Separate live runs
  (one process each) vary by ±2 ms, more than the gaps between the modes.
- The 60 Hz main screen holds every frame at 16.67 ms; measure on the 120 Hz screen (`--screen 1`).

**Look** (`upscale_cockpit_*.png`, `upscale_external_*.png`, crops `crop_hud_*`, `crop_jet_*`, `crop_ext_*`):

- HUD symbols, the cockpit art and the MFDs look the same in all three crops: they are 2D canvas items.
- Aircraft textures and terrain keep their detail. MetalFX spatial sharpens edges a little.
- Balanced breaks a one-pixel 3D line (a seam on the fin) into dots, and fin edges step a little more. Quality
  keeps the line whole, so Quality is the choice for looks.

### 3.11 Night lighting — payoff 3, effort M — **done**
- **Built** (docs/rendering.md §4–§5): the original's `LT_` light points by default, and Night lights = Detailed
  (glows, base and jet lights, stars, moon); below the frame-time noise.
- Next: city lights from the imagery's built-up classes (WorldCover); the panel's floodlight in the 3D cockpit (#5).

### 3.12 Runway / airbase detail, buildings (OSM) — payoff 3, effort L
- **Runways (built, docs/rendering.md §7):** Graphics → MORE → Airbases = Detailed draws a procedural surface with ICAO
  markings in the terrain shader at all ten iaf.ibx bases, inside a paved mask (runways, taxiways, aprons) derived
  from the 1998 art, with a smooth edge. The original's light sets (`lt_*_h`) stand ≈ 2 m outside the derived runway
  edges. Next: runway-holding markings and taxiway edge lines, signs, approach lights; the real layouts stay out
  (docs/imagery.md §9).
- **OSM buildings:** the ODbL is share-alike on the *database*. The safe pattern is a derived 3D-building dataset
  generated at setup and kept local in `assets/`, like the imagery.
- The original's object placement must stay, because missions place targets.

### 3.13 Detailed weapon and store models — payoff 3, effort L
**Goal: DCS-level, as close as we can** (the user's bar). That bar sets the target per store, well above "better than
1998":
- **geometry**: missiles 8–20 k triangles, bombs / tanks 6–15 k; bevelled edges (soft, rounded corners), real
  details — lugs, fuze, arming wire, umbilical, seeker dome with its glass, fin hinges, nozzle;
- **materials**: a PBR set per store at 2048² (albedo, normal, occlusion / roughness / metallic), stencils and
  markings legible at 2 m, light weathering (grime, chipped edges, panel lines) over the painted body;
- **LODs**: full / ≈ 30 % / ≈ 10 %, then the original as the last;
- **rendering** (shared with §3.7): the sky's reflections on the bodies, sun shadows in the external views, SSAO
  where a store meets its pylon (§3.2: worth it once the models are detailed), specular anti-aliasing so thin fins
  stay stable without shimmer.

Honest limit: DCS-level stores on the 1998 jets will look pasted on. The full effect comes with the detailed jet
(§3.7), so the F-16D and its stores are best done together.

**Today:** the 1998 stores have 117–432 triangles on one shared 256-px atlas (`weapons.png`). They sit in 38 folders
under `objects/weapons/` (bombs, missiles, tanks, pods, the ZUNI box), plus the SAM / Scud rounds under
`groundforces/` (`sa2lcr` … `sa6lcr`, `scdlcr`) and the MiG-29 tank (`controllableplanes/mig29/mig29ftk_m`). Players
see them close in the external views, on the pylons and in flight.

**Phase 1 built** (2026-10-26, [aircraft-models.md](aircraft-models.md) §5): the FlightGear F-16's stores as they
are (no upgrade pass yet) in place of 16 originals: AIM-9 / 7 / 120, AGM-65 / 88, MK-82 / 83 / 84 and their laser
versions, CBU-87 / 97, the F-16's tanks, the ECM and FLIR pods; fitted at build time (`tools/stores/build.gd`), not at
load time; runtime LODs and the original as the far LOD; BC1 textures.

**Phase 2 built** (2026-10-29, aircraft-models.md §5): the Soviet stores the enemy jets carry, from two GPL-3.0
FlightGear aircraft, the same way: the AA-2 (the MiG-21bis's R-3S), the AA-8, AA-10, AA-11 (the MiG-29 9-12's R-60M,
R-27R, R-73) and the MiG-29's tank (its PTB-1500). The MiG-21bis's own R-60 (231 faces) and R-27R1 (one texture of
flat colours) were checked and are plainer than the MiG-29 9-12's. Left on the original: the AA-6, AS-14 and AS-16
(no open model, below) and the MiG-23's tank (it shares the F-4's tank model).

**Switch.** Preferences → Graphics → MORE → **Models: Original / Detailed** (built with the F-16D, §3.7; default
Original; visual only). The stores join this one switch, with no second toggle (the user's call).

**One hook: `Gltf.object(path)`** (`game/util/gltf.gd`, built). Every weapon model goes through it:
- the pylon stores and the launched / dropped weapons (`player_weapons.gd` `_instance`);
- the AI jets' stores and rounds (`combat.gd`);
- the Reference viewer (`model_view.gd`);
- the mission objects (`terrain_view.gd`).

With the switch on, the hook opens the detailed model mapped to that original path (`DETAILED`, today only
`f16_h.gltf`) when there is one, else the original. Each model falls back on its own, so the models ship a few at a
time; later, ground units and ships take the same path.
- **Cache:** the switch is read before the cache, and detailed models have their own cache, so toggling between
  flights takes effect.
- **Far LOD:** far away a detailed store is not worth its triangles, so the original model serves as its far LOD
  (`visibility_range`, as the mission objects' LODs in `terrain_view.gd`).

**Fit to the original, at load time, so only the look changes.** Game code reads geometry from these models:
- `stores.gd` takes the store's `pilon` / `Pilon` helper (both spellings occur) for `IafStores.slots` (rack spacing);
- `player_weapons.gd` takes the half length from the model's AABB (axis-aligned bounding box);
- every node gets the Present scale (2.0) on top.

The hook keeps those values from the original (its pilon helper and AABB are what the game code reads) and places
the detailed mesh on them: the mesh's own lug point onto the original's pilon helper, its axis onto the original's.
The originals are already close to real size in the same units (Mk-84 3.93 vs 3.84 m, AIM-9 2.85 vs 2.87 m, AIM-120
3.52 vs 3.65 m, F-16 jet 15.01 vs 15.03 m), so the detailed models stay at real size. A model more than 10 % off the
original's length is scaled to it (moving rack slots would be a behaviour change, a separate question).

**Sources: start from FlightGear's shapes, bring them up to the bar ourselves; committed.** The models are ours or
GPL-compatible, and contain no original game data, so they are tracked in the repo (`models/stores/`, with a
`SOURCES.md`). The fit happens at load time, so they are independent of the install and need no regeneration at
setup.
- **FlightGear F-16** (`github.com/NikolaiVChr/f16`, `Models/Armament/`; `copyright.txt`: "extends to all files in
  this Flightgear F-16 package", GPL-2.0-or-later — compatible with our GPL-3.0-or-later; authors in its
  `authors.txt` → docs/credits.md): MK-82, MK-83, MK-84, AIM-9L / M, AIM-120B, AIM-7F, AGM-65B / D, AGM-88,
  CBU-87, GBU-12 / GBU-24 (stand-ins for the game's laser Mk-82L / Mk-84L), the 300 / 370 / 600 gal tanks,
  ALQ-131 / ALQ-184 ECM pods, LANTIRN (FLIR pod), LAU-68 (a stand-in for the ZUNI box) — ≈ 18 of our 38 folders,
  the most-seen ones. **Measured**: good shapes (the MK-84 ≈ 4 400 faces), but one 512² colour texture with baked
  shading and small stencils, and no normal / roughness maps (AIM-120B, MK-84: 512²; AIM-9M: 512 × 256). That is
  mid-2000s sim level, below DCS, so they are the starting mesh, and the upgrade pass makes the result.
- **The upgrade pass** (Blender, a script under `tools/` like `tools/f35i/`, so it can be re-run):
  1. AC3D → Blender;
  2. fix and bevel the mesh, add the missing details;
  3. UV-unwrap at even texel density;
  4. bake normal / occlusion from a subdivided high-poly copy;
  5. paint the PBR set at 2048² (base colours by real paint schemes, roughness / metal per part, procedural grime and
     edge wear);
  6. redraw the stencils as vector text (the real public markings) so they stay sharp;
  7. export glTF with the LODs.

  The result stays GPL (derived from FlightGear's).
- **Checked, not usable**: hobby / print packs (CGTrader, Cults3D, 3dcadbrowser: personal use or paid);
  Sketchfab game rips (War Thunder / DCS: rights doubtful); no Smithsonian CC0 scan of these weapons found.
  Checked 2026-10-26 and rejected: the Zaretto F-15 / F-14 stores (180–750 triangles, no licence file); the
  `l0k1/oprf_assets` SAM missiles (no licence, low-poly); Sketchfab "(War Thunder)" uploads by KojfDiscord and
  "(WARNO)" uploads, and Jeyhun1985's Kfir scenes (labelled CC BY but likely rips: the Kfir's face count equals the War
  Thunder one); bohmerang's "Missile & Bomb Collection" (CC BY-NC-SA) and civorsky's AIM-9M (CC BY-NC): non-commercial
  licences can't go in a GPL project. Narni_Tchereskov's R-40 / R-3S / R-60 (CC BY, 28k–123k triangles) have
  unverified provenance. No open model exists for the Python 3 / 4 / 5, Shafrir 2, Popeye or Spice: only paid ones
  (CGTrader, RenderHub; the RenderHub Popeye is editorial-only); ours since 2026-10-30 for the Python 5, Popeye, GBU-39 and
  its BRU-61/A, SPICE 1000 / 2000 and Spike NLOS (aircraft-models.md §5.6). Checked 2026-10-30 and rejected: the
  FlightGear F-22A Raptor's GBU-39 (`racerretrocoder/Flightgear-F-22A-Raptor`, GPL-2.0-only with no "or later"
  notice, and its weapons folder says "By FGUK's Davinci F-35", a source not named further). Checked 2026-10-29 and rejected: the
  `xcvb85/Su-27` Kh-29T (an AS-14 stand-in; the repo is GPL-3.0, but the mesh is a 3DS import added in 2024 with a
  shared weapons texture atlas from an unnamed source, so its provenance is unverified); its R-73 is the MiG-29 9-12's.
  No open AA-6 (R-40) or AS-16 (Kh-15) was found in FlightGear's GitHub aircraft.
- **To check next**: FGAddon `MirageIII` stores (Shafrir, the Mirage tank) — FGAddon licence per file.
- **Built by us for the rest** (Python 3 / 4, Shafrir 2, Popeye, AGM-62 Walleye, GBU-15, M117, CBU-97, RBK-500,
  AS-14 / AS-16, AA-6, SA-2 / 3 / 5 / 6, Scud, the F-15 / F-4 / Kfir tanks): modelled in Blender from
  public drawings and photos to the same bar, through the same upgrade pass. A lathe-and-fins script makes only the
  blockout; the shipped model is always the full build.
- **Repo size**: 2048² PBR sets as PNG are ≈ 10–15 MB per store (≈ 0.5 GB for all) — too much for git history.
  **Decided (user, 2026-10-17):** textures GPU-compressed inside the glb (KTX2 / Basis, `KHR_texture_basisu`:
  ≈ 1–2 MB per store, ≈ 60–80 MB for all), if Godot's runtime glTF loader reads them; Git LFS only as the fallback.
  **Measured with the F-16D (2026-10-17):** Godot 4.7.2's runtime glTF loader reads `KHR_texture_basisu` (UASTC and
  ETC1S) and decodes it to RGBA8, with the mipmaps stored in the file (`basisu -mipmap`). So KTX2 keeps the repo
  small, and in video memory each 2048² map takes ≈ 22 MB (RGBA8 + mips), 4× the BC7 figure below. Fallback when
  memory matters: `Image.compress(COMPRESS_ASTC)` at load, ≈ 0.25 s per 2048² map on the M4 Pro (BC7 at runtime:
  ≈ 2 s per map). The tool: `tools/plane/glb_ktx2.py`.

**Cost:** 6–20 k triangles per store × 20 stores × a few dozen jets is a few million triangles at worst, inside the
M4 Pro's budget with the LODs (most stores are far). Textures: ≈ 40 × 3 × 2048² compressed (BC7) ≈ 0.5 GB of video
memory at worst (≈ 2 GB as the RGBA8 the runtime loader decodes KTX2 to, above), less in a mission (only its loads). To be measured on 231 before shipping.

**Scope:** stores and rounds only. Plumes and motor glow (`mission/trails.gd`), moving fins in flight, and aircraft
(§3.7) are out of scope.

**Check** (to add to `tests/godot/test_detailed_models.gd`, which checks the F-16D today):
- with the switch on, every mapped model loads;
- the store's pilon helper and AABB that the game code reads equal the original's, and the detailed mesh's lug sits
  on the helper;
- with the switch off, `Gltf.object` returns exactly the original.

**Visual check** (the test proves the fit; this check judges the looks). A comparison sheet per batch:
1. **Shots:** the same shot twice (Models Original / Detailed) from the pilot guides' shot runner
   (`tests/godot/_guide_shots.gd`: an airborne start with a `loadout` on the pylons, the external view, `settings`
   per shot), in the game's own lighting rather than a model viewer's. A third column holds a **real photo** at a
   similar angle (US DoD photos are public domain; DCS screenshots only as a private reference, never committed).
2. **Angles per store:** close up on the pylon (front quarter, side, below), a launch / drop in flight, a chase at
   50 m, and a pass at 300–1500 m to catch the switch to the far LOD popping.
3. **Sheet:** one HTML page, original | detailed side by side (as `tools/flight_timeline.py --html`).
4. **Review:** the agent looks at every picture first for defects a script cannot judge: wrong colours, missing /
   stretched textures, black or inside-out faces, floating or sunk lugs, shading seams. The user passes or fails each
   store on the sheet. A failed store stays out of the mapping (it falls back to the original) until fixed.
5. **Numbers alongside:** triangles, texture size, and frame time on 231 (the busiest mission), Original vs Detailed.

**In motion** (flying, falling, hitting). Some faults appear only while a weapon moves, so stills miss them:
- **Frame strips and clips** from the same runner: every store launched / dropped onto a placed target
  (`place` + `on_impact`), followed by the F11 weapon view (docs/views.md §4.2: fly-by at 300–700 m) and a chase
  close behind. Frames are captured every few frames from release to impact and the explosion, Original | Detailed
  side by side on the sheet, plus a short video per store. Bombs level and in a dive; missiles at a crossing and a
  head-on target; the guided ones (Maverick / GBU-15 / Popeye) through their turn.
- **Per-frame checks in the test** (scripted, no eyes needed):
  - the mesh's nose stays on the velocity (≤ 2°, as `Basis.looking_at` sets it today);
  - the motor trail starts exactly at the detailed mesh's tail. The trail head sits half the model's length back
    (`player_weapons.gd`); while the detailed mesh is shown, take that length from it (visual only);
  - the mesh stays visible until the detonation frame and is gone on it;
  - its lowest point stays above the ground until the impact;
  - the far LOD swap stays beyond the F11 view's 700 m while that view follows the weapon (else it swaps on screen).
- **Known risk to look for:** the weapon's roll is untracked. `looking_at` uses up = Y, and RIGHT once the weapon
  points straight up or down, so a near-vertical bomb snaps 90° in roll. The 1998 blobs hide it; crisp fins will
  show it. If it shows, keep the roll continuous (visual only, same switch).

**Order.**
1. the load-time fit and its test (the switch and the hook are built);
2. the FlightGear stores (bombs, AIM-9 / 120 / 7, Maverick, HARM, tanks, pods), compared side by side in the
   Reference viewer;
3. the FGAddon check;
4. the built ones for the rest.

## 4. Ranked shortlist

The options of §3, ranked by payoff for effort.

| # | Option | Payoff | Effort | GPU cost (M4 Pro) | Why here |
|---|---|---|---|---|---|
| 1 | Terrain heights in Rust for the sensors (CPU spike fix) — **done** | perf | M | 0 | AI combat worst 4.3 → 0.5 ms (221, live) |
| 2 | Water shader — **done** | 3 | M | 0.23 ms at 1080p (measured) | cheap, visible on every coastal mission |
| 3 | MetalFX upscaling row — **done** | perf | S | −0.6 / −4.6 ms (Quality, 4K, light / heavy) | headroom for 4–8 |
| 4 | F-16D detailed model (FlightGear, GPLv2+) — **done** (stage 1, [aircraft-models.md](aircraft-models.md)) | 5 | L | +32 k primitives in 231 | the biggest visible jump; licence clean |
| 5 | F-16D 3D cockpit with live MFDs / Real HUD on the glass, then clickables | 5 | L → XL | small | the "DCS feel"; fixes the real HUD FOV |
| 6 | GPU particle effects + heat haze — **done** | 3 | M | ≈ 0.3 ms at 1080p in a heavy burst (measured) | combat looks modern; Graphics → MORE Particle effects |
| 7 | Modern DEM (Copernicus 30 m) | 4 | L | small | real relief; mission impact → opt-in |
| 8 | Vegetation near the ground | 4 | L | 1–2 ms | low-level speed sense; after DEM |
| 9 | Night lighting — **done** | 3 | M | +3–6 draw calls (≈ 2 per jet) | original light points; Extras glows, base / jet lights, stars, moon |
| 10 | F-15C model + cockpit (after its licence is cleared) | 5 | L | small | second jet |
| 11 | DCS-level weapon / store models (FlightGear GPLv2+ shapes + our PBR pass; §3.13) | 3 | L | small–medium | best done with #4 |
| 12 | Detailed airbases with the paved mask — **done** (§3.12) | 3 | M | small | take-off and landing look |
| 13 | Own jet in the cockpit views — **done** (§3.7) | 3 | S | small | wings and canopy frame when looking aside |
| — | SSAO / SSIL / SDFGI | 1 now | S | +5 / +12 / +18 ms | nothing to shade over draped terrain; revisit with detailed models |
| — | Volumetric clouds — **done** (rendering.md §2.1) | 4 | L | 8–18 ms on the Iris Xe at 1080p (§2.2) | high tier only |

**Suggested order:** 1 (perf) → 2 + 3 → 4 → 5 → 6 → 7 → 8. Before 7–8, which add geometry near the ground, do a short
performance pass: the 2–3 ms streaming spikes, and the AI scans on the WorkerThreadPool.

## Shots (local, `assets/converted/research/`)
`gfx_none.png`, `gfx_shadows_off.png`, `gfx_shadows_hq.png`, `gfx_ssao.png`, `gfx_ssil.png`, `gfx_glow.png`,
`gfx_vol_fog.png`, `gfx_sdfgi.png`, `gfx_fsr_0.67.png`: mission 311 over Ramat David at 60 m, 3840×2160, one feature each.
`upscale_{cockpit,external}_{off,quality,balanced}.png`: mission 231 on the runway, 3600×2160, one per Upscaling choice
(§3.10), with native-pixel crops `crop_hud_*`, `crop_jet_*` and `crop_ext_*`.

## References
- FlightGear F-16 (GPL-2.0-or-later, `copyright.txt`): https://github.com/NikolaiVChr/f16
- Zaretto F-15 / F-14 (no licence file): https://github.com/Zaretto/fg-aircraft
- F-4X (GPLv2+): https://github.com/Zaretto/F-4X
- FGAddon aircraft list: https://sourceforge.net/p/flightgear/fgaddon/HEAD/tree/trunk/Aircraft/
- FlightGear policy (FGAddon strongly recommends GPLv2+ for original content; not a requirement, per the F-15 author in issue #211): https://www.flightgear.org/about/policy , https://wiki.flightgear.org/FGAddon
- Kfir C.10 on Sketchfab (CC BY, game rip — not used): https://sketchfab.com/3d-models/kfir-c10-block-60-c6534a1cac1e4a13817ac6f8eb35fe96
- Godot 4.7 RC notes: https://gamedev.net/news/3813-release-candidate-godot-47-rc-1/

[^zaretto211]: Richard Harrison, reply in "What is the license of the F-15 model (aircraft/F-15)?", Zaretto/fg-aircraft issue #211, 2026-10-27, https://github.com/Zaretto/fg-aircraft/issues/211
[^cp-du]: Defense Update, "Israel Air Force F-16I Soufa" (three displays per cockpit, six 484 × 484 colour LCDs, the
    rear seat's WSO / instructor switch; from its search-engine excerpt, docs/f16i.md §4): https://defense-update.com/?p=11422
[^cp-at]: Airforce Technology, "F-16I Soufa Multirole Fighter, Israel" (4 × 4 in colour MFDs by Astronautics, 120 ppi):
    https://www.airforce-technology.com/projects/f-16i-soufa/
[^cp-fg]: FlightGear F-16, `copyright.txt` and `authors.txt` at commit ef4f192: https://github.com/NikolaiVChr/f16
[^cp-gxd]: graphXDoses, "F16C Block 50/52 + Cockpit", Sketchfab, CC BY:
    https://sketchfab.com/3d-models/83fb3b74c97d46febda2813331de168d
[^cp-rave]: rave.Ar4ik, "F-16 Fighting Falcon | GameReady", Sketchfab, CC BY:
    https://sketchfab.com/3d-models/0793379abcf742aa881c319155c61220
[^cp-b60]: MirzaArrafiERV_45, "General Dynamics F-16D Block 60", Sketchfab, CC BY:
    https://sketchfab.com/3d-models/ea8edb08d79e4eafa9c794c581f88cf3
[^cp-fsf]: Free Software Foundation, "Various Licenses and Comments about Them", CC BY 4.0 ("compatible with all versions
    of the GNU GPL"): https://www.gnu.org/licenses/license-list.html#ccby
[^cp-ph-cos]: Israel Defense Forces, "Chief of Staff Visits Air Force, Jan 2011 (3)", CC BY 2.0:
    https://commons.wikimedia.org/wiki/File:Flickr_-_Israel_Defense_Forces_-_Chief_of_Staff_Visits_Air_Force,_Jan_2011_(3).jpg
[^cp-ph-ad]: IDF Spokesperson's Unit, "Aviad Dagan, May 2021. IX", CC BY-SA 3.0:
    https://commons.wikimedia.org/wiki/File:Aviad_Dagan,_May_2021._IX.jpg
[^cp-ph-16c]: US Air Force, "F-16C cockpit m02006112700032", public domain (360 × 342 px):
    https://commons.wikimedia.org/wiki/File:F-16C_cockpit_m02006112700032.jpg
[^cp-ph-aa]: Nathaniel, "F16 Cockpit, Asian Aerospace 2006" (a trainer), public domain:
    https://commons.wikimedia.org/wiki/File:F16_Cockpit,_Asian_Aerospace_2006.JPG
[^cp-ph-efka]: Edvard Majakari, "F-16D cockpit at EFKA" (an F-16AM), CC BY-SA 2.0:
    https://commons.wikimedia.org/wiki/File:F-16D_cockpit_at_EFKA.jpg
