# Rendering options

The game logic is the original's; the rendering may be better, but the original look is the default and every
improvement is opt-in (Preferences → Graphics for the original's own switches and our VSYNC check, Preferences → Extras for the rest of
ours).
Code: `game/terrain/render_options.gd` (applied by `terrain_view.gd apply_render_options()` at the start of a flight
and when the in-flight Preferences close), `terrain/terrain.gdshader`, `terrain/atmosphere.gdshader`,
`terrain/cloud_layer.gd`. Tests: `tests/godot/test_graphics_prefs.gd` (switches → render settings, save / load),
`test_ui_smoke.gd` (Extras rows in EN / HE).

## 1. Options

| Extras row | choices (first = default) | what it sets |
|---|---|---|
| Anti-aliasing | MSAA 4x / + FXAA / TAA | viewport `msaa_3d` 4× (the project's setting since the start); + FXAA: also `screen_space_aa` FXAA (softens shader / texture edges MSAA misses); TAA: `use_taa` **instead of** MSAA (resolves sub-pixel shimmer over time — thin runway lines, distant wires; a little softer, may ghost in fast rolls) |
| Terrain close up | Original / Detailed | 16× anisotropic filtering (default 4×) for the grazing view of the ground, and in `terrain.gdshader` detail that follows the imagery, k fading from 1 at 300 m to 0 at 1.5 km (§1.1) |
| Sky | Original / Atmospheric | Original: our gradient sky (ProceduralSkyMaterial) with the fixed fog colour. Atmospheric: `atmosphere.gdshader`, a clear-day sky from the sun's direction and the camera's altitude; the fog takes its colour from the sky (`fog_aerial_perspective` 1, `fog_sun_scatter` 0.1); the fog density (the original's fog distances) is unchanged; the cloud layer's clouds separated (§1.2). No glow / bloom (it cost 3 ms) |

### 1.1 Terrain close up

The 1998 imagery is a few metres per texel, so below ≈ 500 m AGL the ground near the jet is a blur. The detail is
built from the photo's own colour, per pixel (≈ 5 texture samples):

- **Coloured ground** (chroma ≥ 0.05: fields, scrub, soil): patches (noise tile 420 m, ≈ 40 m features, plus the
  9 m clumps) move the colour toward a deeper, more saturated version of itself (c²/luminance: growth, wet soil) or
  a paler, drier one (half-desaturated × 1.3); then a grain (16 m tile, ≈ 1.6 m features, ± ≈ 15 %) and normal
  detail from the noise's normal map at the grain's scale.
- **Grey ground** (asphalt, concrete, rock): a faint grain only (± ≈ 4 %), a fifth of the normal detail: runways
  get no grass noise. Inside an airbase (terraintype.dat 0x10) the chroma limit is higher, as the aprons are
  tinted blue / purple in the imagery.
- **Water**: none: the generated open sea (as before) and the inland water of terraintype.dat (0x6, not island
  leaves): `render_options.gd` rasterises the BSP around the camera into a 32 × 32 texture of 96 m texels (global
  `terrain_surface`, R = water, G = airbase), rebuilt 4 rows per frame when the camera is 600 m from its centre.
- The noise textures are centred (mean 0.5) and every term is 0 at their mean, so distant mipmaps and the fade-out
  leave the imagery's colours unchanged from afar. The terrain grid has no tangents: the detail normal is built in
  the fragment shader from the world X / Z axes (no `NORMAL_MAP`, which made Godot warn on every node).
- Before: one brightness noise (±7 %) at 2.4 m / 0.5 m features, sub-pixel beyond ≈ 50 m, so it was barely visible.

### 1.2 Atmospheric sky

`L = E · sun · [P_R(μ)·(1 − e^(−τ_R·m)) + P_M(μ)·(1 − e^(−τ_M·m))]`: m the air mass along the view (Kasten-Young,
capped at 6), P_R the Rayleigh phase, P_M Henyey-Greenstein (g 0.75), τ_R / τ_M the air's (per channel) and the
haze's optical depths thinning with altitude (scale heights 8 km / 1.5 km; the altitude is passed in 250 m steps so
the sky's radiance is not re-filtered every frame), the sunlight slightly reddened by its air mass. The τ_R
(0.045, 0.13, 0.6) are tuned, not the λ⁻⁴ values: plain single scattering (the first version) gives a pale cyan
zenith and a white horizon 7× brighter, which the AgX tonemapper turns grey; these give a deep blue zenith (≈ the
gradient sky's top), a pale horizon 2–3× brighter, a darker zenith at 9000 m. Below the horizon the colour is the
horizon's: the fog over the ground takes it (before: a dark "ground" colour, a brown-grey haze). The sun's disc
(0.53°) has a crisp edge (its angle from the chord: `cos` near 1 lost the disc in float precision before) and a
narrow glare (e-folding 1.5°). The cloud layer (Graphics TEXTURED SKY, the original's) maps its texture's alpha
0.3–0.9 to 0–1 with this sky: separate clouds with clear sky between them rather than a grey veil over the
whole sky; with the nearly opaque Cloud256_5 (one mission in six) it stays overcast. No time of day yet: the sun is
our fixed light (30° up), the sky follows `LIGHT0_DIRECTION`.

Not AI upscaling anywhere; the art pipeline stays 4× Lanczos. The canopy frame and the HUD are the 2D cockpit
art, so the 3D anti-aliasing does not touch them.

## 2. Cloud layer (Graphics TEXTURED SKY, docs/front-end.md §12.4)

- **Cut.** The original cuts the dome at the terrain's far horizon (`407c70` → `41dc30` → +0x1098) and fills the gap
  at the dome's depth, so the dome never covers drawn terrain. Our port drew the lower rings (down to height 0 at
  21.9 km) over the terrain we draw out to 200 km: a white band across the whole horizon, at 2000 m most of the
  view above the hills. Now the dome is drawn at the far plane (reverse-Z depth 0, `at_far`), behind every terrain
  point; the flat layer seen from above stays at its depth.
- **Whiteout** checked in the disassembly (v1.0 41da5e–41da9f): only while |altitude − 7000| < 1000 (`5fb53c`),
  alpha = clamp(j + 255 − ftol(0.255·|Δ|), 0, 255) (`5fb540` = 0.255). Nothing at 6000 m or below; the white
  "haze" in the 2000 m explosion shot was the dome band (above) and the explosion's own smoke column 40 m away.
  The full-screen whiteout rect is hidden while its alpha is 0.
- **Cost.** Not the 36 vs 68 fps reported (that run averaged its first frames after load); measured 0.15–0.5 ms GPU
  below the layer, 1.4 ms above it (the flat layer over half the screen) — table below.

## 3. Measurements

`tests/godot/_visual_bench.gd` (one real-render window, all poses × options, screenshots), Intel Iris Xe (TigerLake
GT2), 1920×1080, mission 311 at Ramat David, GPU time per frame (`viewport_get_measured_render_time_gpu`, the frame
rate is capped at 60 by the Wayland compositor):

| pose | base (MSAA 4×, clouds) | no cloud layer | + FXAA | TAA | close up | atmospheric | TAA + close up + atmospheric |
|---|---|---|---|---|---|---|---|
| runway (cockpit) | 13.8 ms | 13.3 | 15.0 | 16.6 | 15.4 | 14.7 | 17.8 |
| runway (external, jet) | 14.4–15.2 | 15.0 | 15.3 | 17.7 | 16.2 | 15.0 | 19.0 |
| 150 m AGL | 18.2–18.4 | 17.9 | 19.0 | 18.8 | 19.6 | 18.3 | 20.4 |
| 2000 m cruise | 22.0 | 21.7 | 22.6 | 20.6 | 22.7 | 22.3 | 21.0 |
| 2000 m towards the sun | 17.3 | 16.7 | 17.7 | — | 17.6 | 17.5 | — |
| 6900 m (whiteout) | 22.5 | 22.0 | 22.9 | — | 22.8 | 22.6 | — |
| 9000 m (flat layer) | 25.5 | 24.1 | 25.8 | 23.2 | 26.0 | 25.7 | 23.5 |

Costs: + FXAA ≈ +0.5–1.2 ms; TAA ≈ +0.4–2.7 ms near the ground, 1.5–2.4 ms cheaper than MSAA 4× at altitude
(MSAA 4× itself is ≈ 6 ms here). MSAA 8× (+5 ms) and MSAA + TAA (+7 ms) were measured and left out. The close up and
atmospheric columns above are the first versions (§1.1 / §1.2 "before").

The tuned close up and atmospheric sky, three bench runs (the machine shared with builds: single values vary by
±1–2 ms, so the costs are the differences within a run, each pair rendered back to back):

| pose | close up − base | atmospheric − no cloud layer (sky alone) |
|---|---|---|
| runway (cockpit) | +0.7 / +1.0 / +1.3 ms | −0.0 ms |
| runway (external, jet) | +1.1 / +1.4 / +1.5 | +0.1 / +0.2 |
| 150 m AGL | +0.5 / +1.4 / +1.6 | −0.4 / +0.1 |
| 2000 m cruise | +0.2 / +0.2 / +0.5 | +0.4 / +1.5 (under load) |
| 2000 m towards the sun | +0.0 / +0.2 / +0.4 | +0.2 / +0.3 |
| 9000 m (above the layer) | +0.6 / +0.6 | +0.3 / +0.4 |

Terrain close up ≈ +0.5–1.5 ms near the ground (16× anisotropic filtering included; one sample over 1.5 ms),
≤ 0.6 ms at altitude; atmospheric sky ≈ +0.1–0.4 ms (the sky shader runs per background pixel; its radiance is re-filtered
only when the altitude step changes). Screenshots of each pose are written by the bench
(`BENCH_SEED=3` for the broken-cloud texture Cloud256_0 instead of the overcast Cloud256_5).
