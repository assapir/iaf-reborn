# Rendering options

This doc lists the rendering options of the flight scene, what each one sets, and what each one costs on the GPU
(graphics processor). Key facts:

- The game logic is the original's. The rendering may look better than the original's, but the original look is the
  default and every improvement is opt-in.
- Preferences → Graphics holds the original's own switches and our VSYNC (vertical sync) check. Its **MORE** button
  opens our graphics options (the rows below and the terrain imagery). Preferences → Extras holds the rest of ours.
- The time of day (§4) follows the original's rules: the sun, light and fog colours come from the mission start time.

Code: `game/terrain/render_options.gd` (applied by `terrain_view.gd apply_render_options()` at the start of a flight
and when the in-flight Preferences close), `terrain/terrain.gdshader`, `terrain/atmosphere.gdshader`,
`terrain/cloud_layer.gd`, `terrain/night_lights.gd`. Tests: `tests/godot/test_graphics_prefs.gd` (switches → render
settings, save / load), `test_ui_smoke.gd` (Graphics → MORE and Extras rows in EN / HE), `test_night_lights.gd` (§4 light points, §5), `test_water.gd` (§1.3).

## 1. Options

Preferences → Graphics → MORE has our rendering rows. MSAA = multisample anti-aliasing, FXAA = fast approximate anti-aliasing,
TAA = temporal anti-aliasing.

| Graphics → MORE row | choices (first = default) | what it sets |
|---|---|---|
| Anti-aliasing | MSAA 4x / + FXAA / TAA | MSAA 4x: viewport `msaa_3d` 4× (the project's setting since the start). + FXAA: also `screen_space_aa` FXAA, which softens the shader / texture edges that MSAA misses. TAA: `use_taa` in place of MSAA; it resolves sub-pixel shimmer over time (thin runway lines, distant wires), is a little softer and may ghost in fast rolls |
| Terrain close up | Original / Detailed | 16× anisotropic filtering (default 4×) for the grazing view of the ground, and in `terrain.gdshader` detail that follows the imagery, with a weight k fading from 1 at 300 m to 0 at 1.5 km (§1.1) |
| Sky | Original / Atmospheric | Original: our gradient sky (ProceduralSkyMaterial) with the fixed fog colour. Atmospheric: `atmosphere.gdshader`, a clear-day sky computed from the sun's direction and the camera's altitude. The fog takes its colour from the sky (`fog_aerial_perspective` 1, `fog_sun_scatter` 0.1) and keeps its density (the original's fog distances). The cloud layer shows separate clouds (§1.2). Glow / bloom is off (it cost 3 ms) |
| Upscaling | Native / Quality / Balanced | the 3D scene's render scale: Native 1.0; Quality 0.77; Balanced 0.67 of the window. A spatial upscaler scales it up: MetalFX spatial on Metal, FSR 1 on other drivers (`render_options.gd upscale_mode()`). The Anti-aliasing row still applies. The 2D cockpit, HUD and MFDs are canvas items, drawn after the upscale at the window's resolution. Godot lowers the texture mip bias by log2(scale). Saves 0.6 ms (Quality) / 1.4 ms (Balanced) at 4K today, 4.6 / 6.3 ms with SSAO + SSIL; Balanced breaks one-pixel 3D lines into dots (docs/graphics-research.md §3.10) |
| Night lights | Original / Detailed | Original: the original's light points (§4). Detailed: glowing lights, the home airbases lit at night, the jets' navigation lights and strobe, stars, a moon and moonlight (§5) |
| Water | Original / Detailed | in `terrain.gdshader`: waves, sun glint and the sky's reflection on the sea and on lakes (§1.3) |
| Models | Original / Detailed | Detailed: our detailed aircraft models where one exists (today the F-16D), parsed once and shared, with runtime LODs ([aircraft-models.md](aircraft-models.md)) |

### 1.1 Terrain close up

The 1998 imagery has a few metres per texel, so below ≈ 500 m AGL (above ground level) the ground near the jet is a
blur. The Detailed option adds detail built from the photo's own colour, per pixel (≈ 5 texture samples). The shader
treats three kinds of ground:

- **Coloured ground** (chroma ≥ 0.05: fields, scrub, soil):
  - Patches (noise tile 420 m, ≈ 40 m features, plus the 9 m clumps) move the colour toward a deeper, more saturated
    version of itself (c²/luminance: growth, wet soil) or toward a paler, drier one (half-desaturated × 1.3).
  - A grain follows (16 m tile, ≈ 1.6 m features, ± ≈ 15 %), with normal detail from the noise's normal map at the
    grain's scale.
- **Grey ground** (asphalt, concrete, rock): a faint grain only (± ≈ 4 %) and a fifth of the normal detail, so runways
  stay free of grass noise. Inside an airbase (terraintype.dat 0x10) the chroma limit is higher, because the imagery
  tints the aprons blue / purple.
- **Water** keeps the plain imagery. Water means the generated open sea (as before) and the inland water of
  terraintype.dat (0x6, island leaves excluded). To find it, `render_options.gd` asks Rust (`IafSurface`,
  `iaf_formats::terrain_types`) for terraintype.dat around the camera as a 256 × 256 texture of 96 m texels, 24.6 km
  across (global `terrain_surface`, R = water, G = airbase). It rebuilds the texture in one call when the camera is
  4 km from its centre. The Water option (§1.3) uses the same texture.

Design points:

- The noise textures are centred (mean 0.5) and every term is 0 at their mean. Distant mipmaps and the fade-out
  therefore leave the imagery's colours unchanged from afar.
- The terrain grid has no tangents. The fragment shader builds the detail normal from the world X / Z axes and leaves
  `NORMAL_MAP` unset (setting it made Godot warn on every node).
- Before: one brightness noise (±7 %) at 2.4 m / 0.5 m features. It was sub-pixel beyond ≈ 50 m, so it was barely
  visible.

### 1.2 Atmospheric sky

The Atmospheric sky computes the radiance L of each view direction with single scattering:

`L = E · sun · [P_R(μ)·(1 − e^(−τ_R·m)) + P_M(μ)·(1 − e^(−τ_M·m))]`

- m is the air mass along the view (Kasten-Young, capped at 6).
- P_R is the Rayleigh phase function; P_M is Henyey-Greenstein (g 0.75).
- τ_R / τ_M are the optical depths of the air (per channel) and of the haze. They thin with altitude (scale heights
  8 km / 1.5 km). The shader receives the altitude in 250 m steps, so Godot re-filters the sky's radiance only when the
  step changes, not every frame.
- The sunlight is slightly reddened by its air mass.

Tuning:

- The τ_R values (0.045, 0.13, 0.6) are tuned, not the physical λ⁻⁴ values. Plain single scattering (the first
  version) gave a pale cyan zenith and a white horizon 7× brighter, which the AgX tonemapper turns grey.
- The tuned values give a deep blue zenith (≈ the gradient sky's top), a pale horizon 2–3× brighter, and a darker
  zenith at 9000 m.
- Below the horizon the colour is the horizon's, and the fog over the ground takes it. Before, it was a dark "ground"
  colour, which made a brown-grey haze.
- The sun's disc (0.53°) has a crisp edge: the shader takes its angle from the chord, because `cos` near 1 lost the
  disc in float precision before. Around it is a narrow glare (e-folding 1.5°).

The cloud layer (Graphics TEXTURED SKY, the original's) maps its texture's alpha 0.3–0.9 to 0–1 with this sky. The
result is separate clouds with clear sky between them, in place of a grey veil over the whole sky. With the nearly
opaque Cloud256_5 (one mission in six) the sky stays overcast. The sun is the original's by the time of day (§4); the
sky follows `LIGHT0_DIRECTION`.

The art pipeline stays 4× Lanczos everywhere; nothing uses AI upscaling. The canopy frame and the HUD (head-up
display) are the 2D cockpit art, so the 3D anti-aliasing does not touch them.

### 1.3 Water

The Water option shades the water in `terrain.gdshader` (global `terrain_water` = 1). Godot's lighting does the
rest: the sun's GGX highlight becomes the glint, and the sky's radiance gives the reflection with Fresnel.

**Which pixels are water:**

1. The generated open sea: the photo's colour within 0.04–0.08 of `sea_colour`, compared in sRGB.
2. The photo's water inside terraintype.dat's water (the surface raster, §1.1): blue-green pixels (green or blue at
   least 0.02–0.07 above red, sRGB luminance below 0.55–0.7). This covers lakes and the coastal shallows; beaches are
   red-dominant, so they stay land. The raster fades out over its outer 10 % (2.4 km).

**The surface (per water pixel):**

| Part | Values |
|---|---|
| Waves | 6 cosine waves: swells of 97, 53, 31 m and wind waves of 17, 11.3, 6.1 m, steepness (amplitude · k) 0.03–0.04, within ± 0.9 rad of the wind (toward the east-north-east), deep-water speed √(g / k) |
| Crest warp | the wave positions shifted by up to ± 9 m (noise tiles of 260 m and 330 m), so the crests bend |
| Ripples | 2 scrolling layers of the detail normal map, tiles of 41.3 m and 8.9 m, slope × 0.18 |
| Wind patches | noise of 1.7 km tiles scales all slopes by 0.25–1.8 (calm and rough areas) |
| Anti-aliasing | each wave fades out between 16 and 5 pixels per wavelength; the slope variance it loses goes into the roughness (GGX α = √(0.0016 + 2 · lost variance)), so far away the glint spreads into a glitter path |
| Material | specular 0.28 (F0 ≈ 0.0125; Godot also scales the grazing reflection by 50 · F0, so the sea stays blue until near the horizon), albedo 0.75 × the photo's colour |

Every derivative is taken at the top of `fragment()`, outside the per-pixel water branch. The noise samples use
`textureGrad` with those derivatives and a trilinear sampler (global `terrain_water_noise`, the detail normal map).

**Cost** (`tests/godot/_water_shot.gd SHOT_BENCH=1`, M4 Pro, 3840 × 2160 at render scale 1.6 = 21 Mpx, mission 311's
sun, `terrain_water` switched 0 / 1 every 120 frames in one window, median of 12 pairs):

| Pose | on − off |
|---|---|
| 150 m over the sea, water over most of the view (frame 16.1 → 18.4 ms) | +2.27 ms (quartiles +2.17 / +2.37) |
| the same while other Godot processes shared the GPU (frame 28.4 → 32.5 ms) | +4.18 ms (the same +14 % of the frame) |
| 1500 m over the Tel Aviv coast, sea over half the view (shared GPU) | +2.35 ms |

That is ≈ 0.11 ms per million water pixels: ≈ 0.23 ms at 1920 × 1080 and ≈ 0.9 ms at 3840 × 2160 with water over
the whole view. The surface raster costs 0.7 ms of CPU (Rust, 65 536 lookups) once every 4 km of flight.

**Shots** (local, `assets/converted/research/water/`, Original then Detailed): `ta150_*` and `ta1500_*` (the Tel Aviv
coast at 150 m and 1500 m), `glint150_*` and `glint1500_*` (towards the sun over the sea), `kin150_*` (the Kinneret at
150 m), `cmp_*.png` (the pairs stacked).

## 2. Cloud layer (Graphics TEXTURED SKY, docs/front-end.md §12.4)

The cloud layer is a dome of cloud texture plus a flat layer, and a whiteout near its altitude. Three findings:

- **Cut.** The original cuts the dome at the terrain's far horizon (`407c70` → `41dc30` → +0x1098) and fills the gap
  at the dome's depth, so the dome never covers drawn terrain. Our port drew the lower rings (down to height 0 at
  21.9 km) over the terrain we draw out to 200 km. That made a white band across the whole horizon; at 2000 m it
  covered most of the view above the hills. Now the dome is drawn at the far plane (reverse-Z depth 0, `at_far`),
  behind every terrain point. The flat layer seen from above stays at its depth.
- **Whiteout**, checked in the disassembly (v1.0 41da5e–41da9f):
  - It shows only while |altitude − 7000| < 1000 (`5fb53c`).
  - alpha = clamp(j + 255 − ftol(0.255·|Δ|), 0, 255) (`5fb540` = 0.255).
  - At 6000 m or below there is none. The white "haze" in the 2000 m explosion shot was the dome band (above) and the
    explosion's own smoke column 40 m away.
  - The full-screen whiteout rect is hidden while its alpha is 0.
- **Cost.** The reported 36 vs 68 fps was wrong: that run averaged its first frames after load. Measured: 0.15–0.5 ms
  GPU below the layer, 1.4 ms above it (the flat layer covers half the screen). See the table below.

## 3. Measurements

The bench `tests/godot/_visual_bench.gd` renders all poses × options in one real-render window and saves
screenshots. Setup:

- GPU: Intel Iris Xe (TigerLake GT2), 1920×1080.
- Scene: mission 311 at Ramat David.
- Value: GPU time per frame (`viewport_get_measured_render_time_gpu`), because the Wayland compositor caps the frame
  rate at 60.

| pose | base (MSAA 4×, clouds) | no cloud layer | + FXAA | TAA | close up | atmospheric | TAA + close up + atmospheric |
|---|---|---|---|---|---|---|---|
| runway (cockpit) | 13.8 ms | 13.3 | 15.0 | 16.6 | 15.4 | 14.7 | 17.8 |
| runway (external, jet) | 14.4–15.2 | 15.0 | 15.3 | 17.7 | 16.2 | 15.0 | 19.0 |
| 150 m AGL | 18.2–18.4 | 17.9 | 19.0 | 18.8 | 19.6 | 18.3 | 20.4 |
| 2000 m cruise | 22.0 | 21.7 | 22.6 | 20.6 | 22.7 | 22.3 | 21.0 |
| 2000 m towards the sun | 17.3 | 16.7 | 17.7 | — | 17.6 | 17.5 | — |
| 6900 m (whiteout) | 22.5 | 22.0 | 22.9 | — | 22.8 | 22.6 | — |
| 9000 m (flat layer) | 25.5 | 24.1 | 25.8 | 23.2 | 26.0 | 25.7 | 23.5 |

Costs:

- + FXAA ≈ +0.5–1.2 ms.
- TAA ≈ +0.4–2.7 ms near the ground, and 1.5–2.4 ms cheaper than MSAA 4× at altitude (MSAA 4× itself is ≈ 6 ms here).
- MSAA 8× (+5 ms) and MSAA + TAA (+7 ms) were measured and left out.
- The close up and atmospheric columns above are the first versions (§1.1 / §1.2 "before").

The next table measures the tuned close up and atmospheric sky over three bench runs. The machine was shared with
builds, so single values vary by ±1–2 ms. The costs are therefore the differences within a run, each pair rendered
back to back:

| pose | close up − base | atmospheric − no cloud layer (sky alone) |
|---|---|---|
| runway (cockpit) | +0.7 / +1.0 / +1.3 ms | −0.0 ms |
| runway (external, jet) | +1.1 / +1.4 / +1.5 | +0.1 / +0.2 |
| 150 m AGL | +0.5 / +1.4 / +1.6 | −0.4 / +0.1 |
| 2000 m cruise | +0.2 / +0.2 / +0.5 | +0.4 / +1.5 (under load) |
| 2000 m towards the sun | +0.0 / +0.2 / +0.4 | +0.2 / +0.3 |
| 9000 m (above the layer) | +0.6 / +0.6 | +0.3 / +0.4 |

- Terrain close up ≈ +0.5–1.5 ms near the ground (16× anisotropic filtering included; one sample over 1.5 ms), and
  ≤ 0.6 ms at altitude.
- Atmospheric sky ≈ +0.1–0.4 ms. The sky shader runs per background pixel, and Godot re-filters its radiance only
  when the altitude step changes.
- The bench writes screenshots of each pose. `BENCH_SEED=3` selects the broken-cloud texture Cloud256_0 in place of
  the overcast Cloud256_5.

### 3.1 Flying, best settings (`tests/godot/_flight_bench.gd BENCH_BEST=1`)

This bench flies with every Graphics option up, MSAA 4× + FXAA, close up, atmospheric sky and the mapi2015 /
sentinel2 imagery, at 1920×1080:

- **M4 Pro (Metal):** CPU-bound. The cockpit HUD's sprite font cost ≈ 6 ms and ≈ 880 draw calls (one draw call per
  segment / pixel). One `draw_multiline` per sprite took the bench from 106 to 260–300 fps.
- **Iris Xe:** GPU-bound, 35–50 fps (GPU 19–27 ms; with the terrain hidden, 8 ms; half resolution about halves it).
  Costs on static legs:
  - shadows ≈ 4 ms; the 8192 atlas was ≈ 1.8 ms of it, so the atlas is 4096 now;
  - MSAA 4× ≈ 4 ms over TAA;
  - close up / FXAA / cloud layer ≈ 0.3–0.5 ms each;
  - the 2 m imagery: nothing measurable;
  - the original sky cost 1–4 ms more than the atmospheric one, because it rewrote its horizon colours every frame
    (each write re-renders the sky radiance). It now writes them only on change, and the sky radiance is
    incremental.

  These last two changes were not yet re-measured in a clean A/B on the Iris.

## 4. Time of day (built: game/terrain/time_of_day.gd)

This section describes the original's day / night rendering and our port of it. By these rules only mission 214
starts at night; missions 112, 237 and 515 start at 05:xx, which is dawn.

**Port.** The time of day = the mission start 0x460 + the mission clock (11:00 without a mission).

- Once a sim second the port sets:
  - the sun node's direction and colour;
  - the ambient factor (Godot ambient energy = factor / 0.6);
  - the gradient sky's top colour;
  - SHADOWS, only 08:00–17:00;
  - the cloud layer's tint: (20, 20, 60) at night, white by day (its day value is not traced);
  - no sun disc at night; at night the atmospheric sky (Graphics → MORE) falls back to the gradient one.
- Every frame it sets the fog / horizon colour by the view's heading (B → C → D).
- The sun node lights the terrain; the original pre-lights it with the light colour (UNCERTAIN match).
- The cockpit darkening is game/cockpit/cockpit.gd `night` (docs/cockpit.md).

**Original.**

- **Clock.** `FUN_004dbe00` runs every frame: the clock (`FUN_004cf8c0`, s) × 1000 = ms since midnight → renderer
  vtable +0x64 `FUN_00405020` → `FUN_00407c70` (TerrainType=Stream, the shipped tgen.ini) or `FUN_00407ba0`. The
  briefing preview uses a fixed 11:00 (`FUN_00405070`).
- **Colour table** `defcolorset.tcs` (install root, `FUN_00422f30`):
  - Rows are `HH MM sky light horizB horizC horizD k` (RGB each). `FUN_00422b90` interpolates linearly by minute and
    clamps.
  - 05:00 and 20:00 are the same night row (sky 0,15,38; light 43,43,43; B 0,12,30; C 0,0,0; D 0,6,17; k 40). The
    other rows are at 05:42, 06:00, 06:20, 07:01, 12:00, 16:00, 19:30.
  - `FUN_004229c0(minute, heading)` returns the sky colour, light and k, and the fog colour blended B (toward the
    sun) → C → D (away) by 2·|view azimuth (180 − heading) − sun azimuth|/180.
- **Sun** (`FUN_00407920`): f = (t − 05:00) / 15 h.
  - **Night when f < 0 or f > 1**: night flag (0x775a34) set, shadows off, light straight down, light colour
    (20, 20, 60)/255, ambient 0.2, the cloud layer 0xFF14143C, no sun disc / flare.
  - Day: a = 180·f + 90°, direction (−sin a, −cos a, cos a) (the sun peaks at 45° at noon), light = tcs·(1 − k/255) +
    k, ambient factor 0.2 + 0.4·(−cos a) (0.6 at noon), shadows only for 0.2 ≤ f ≤ 0.8 (08:00–17:00,
    docs/deviations.md).
  - The result is a D3D (Direct3D) directional light with that colour, ambient = factor × light (`FUN_00403ca0` →
    `FUN_0040b500`).
- **Fog** colour is set per frame (render state FOGCOLOR, `FUN_0040bd90`). Its density (6.0) stays the same at night.
- **Terrain** is pre-lit with the light colour (at night × (20, 20, 60)). The **sky** is a gradient quad: zenith the
  tcs sky colour, horizon the fog colour (`FUN_00419a20` / `FUN_004195f0`). Medium certainty.
- **Objects**: the model loader `FUN_0041ee60` flags a model by the first three letters of its file name: `UL_`
  sets object flag 0x1, `LT_` sets 0x4. The draw call `FUN_0041ac40` sets the render states per model:
  - `UL_` models (flat decals: the runway underlays `ul_rw*`, `ul_dipuns`, `ul_cloud3d`, `ul_crater`) draw as
    pre-lit vertices with depth write off. `FUN_0041d0c0` ("updateUnlitedObjectsColors") sets their vertex colour
    (flag mask 0x11) to 0xFF1E1E41 at night and 0xFFDCDCDC by day. The port hides these flat models
    (docs/deviations.md §1); the colour applies only to them.
  - Every other model is lit by the light and the ambient.
- **Light points** (`LT_` models, flag 0x4): `FUN_0041ac40` draws them as a point list (D3D FILLMODE POINT,
  DrawPrimitive POINTLIST of pre-lit vertices). Each vertex is one pixel in its material's colour, with depth test
  on, depth write off and fog. They draw at every hour. The sets:

  | model | what | placed by |
  |---|---|---|
  | `lt_dvd_h`, `lt_rmn_h`, `lt_tnf_h` | runway, taxiway and threshold lights of Ramat David, Ramon, Tel Nof (on their `ul_rw*` spot) | `lt_dvd_h` in 214 (base mission `bmisrdvdn`) |
  | `lt_dsk_h`, `lt_dsk01`–`04` | Damascus's streets and districts | 214 |
  | `lt_chmny` | the power plant's two chimneys | 214 |
  | `lt_ossa` | a missile boat's navigation lights | 125 |

  In 214 ("Damascus Blackout") each Damascus set and chimney has a script Wait, then Vanish (Visible off): the city
  goes dark. These lights are the original's only night lights; its night sky is the gradient.
  Port: `terrain_view.gd _spawn_mission_objects` turns every `LT_` model into points (`night_lights.gd to_points`):
  one point per vertex in its surface's colour, unshaded, depth write off, fogged, `round(rows / 480)` pixels wide
  (one pixel of the 640 × 480 screen). The TSD target window (`model_view.gd setup_target`, docs/front-end.md §10) draws them the same way.
- **Update rate**: on the Stream path the light, night flag and sky change only when the time moved > 60 s.
- **Gameplay**: none (no sensor reads the night flag). The tower greets by hour (`FUN_00551c20`: < 12 morning, 12–16
  afternoon, 17–21 evening, ≥ 22 morning, a quirk). The time option labels Noon / Dawn / Sunset / Night = 12:00 /
  06:00 / 19:00 / 22:00.

## 5. Night lights, Detailed (built: game/terrain/night_lights.gd)

Preferences → Graphics → MORE → **Night lights = Detailed** (ours, docs/deviations.md §2). It aims at a modern night look at
a small cost. The parts:

1. **Glowing light points.** The `LT_` sets draw with a glow shader: a bright core and a soft halo. The glow is 4 m
   wide in the world, kept between 2.5 and 28 pixels at 1080 rows. It fades with the fog, and it stands 1.5 m above
   its spot, so the ground between the spots leaves it whole. By day the glow is at 35 %.
2. **Home airbases lit at night.** At a night start, a runway model on its home spot (`ul_rwramon`, `ul_rwtelnof`,
   `ul_rwdavid`, `night_lights.gd BASE_LIGHTS`) gets its base's light set (`lt_rmn_h`, `lt_tnf_h`, `lt_dvd_h`). The
   set takes the runway model's spot, heading and scale, as in base mission `bmisrdvdn`. The sets are the
   original's art and match the runway edges in the imagery.
3. **Navigation lights and strobe on every jet** (`aircraft_model.gd`): red on the left wingtip, green on the right,
   white at the tail, and a white strobe on top of the fin. It flashes for 0.08 s every 1.2 s, each jet at its own
   phase. The spots are the model's EndWing helpers and its outermost vertices (cached per model).
4. **Night sky.** 2600 stars (a fixed random sky, brighter ones rarer) and a moon disc drawn at the far plane. The
   cloud layer draws over them.
5. **Moonlight.** At night the sun light comes from the moon (azimuth 140°, elevation 38°), colour (0.20, 0.23,
   0.33), ambient factor 0.3. The original's night light is (20, 20, 60) / 255 straight down, ambient 0.2.

Cost: +3 to +6 draw calls, about 2 per jet in view plus the sky, and ≈ 5 000 points (`tests/godot/_flight_bench.gd`
with `BENCH_SET=night_lights=detailed`: mission 311 at 22:00 +3, mission 214 +6). The frame time change is below the
run-to-run noise on the M4 Pro. Screenshots: `tests/godot/_night_shot.gd` (cockpit and
external, Original and Detailed, with the frame rate).

Metal notes (Godot 4.7.2): in a spatial shader's `vertex()`, `VIEWPORT_SIZE` reads 0 and the projection is
Y-flipped. The shaders get the viewport rows as a uniform and take the focal length as
`abs(PROJECTION_MATRIX[1][1])`. `POINT_SIZE` and `POINT_COORD` work.

