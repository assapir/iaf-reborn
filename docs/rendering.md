# Rendering options

This doc lists the rendering options of the flight scene, what each one sets, and what each one costs on the GPU
(graphics processor). Key facts:

- The game logic is the original's. The rendering may look better than the original's, but the original look is the
  default and every improvement is opt-in.
- Preferences → Graphics holds the original's own switches and our VSYNC (vertical sync) check. Its **MORE** button
  opens our graphics options: the Window row (framed / full screen), the rows below and the terrain imagery
  (docs/imagery.md §5). Preferences → Extras holds the rest of ours.
- The time of day (§4) follows the original's rules: the sun, light and fog colours come from the mission start time.

Code: `game/terrain/render_options.gd` (applied by `terrain_view.gd apply_render_options()` at the start of a flight
and when the in-flight Preferences close), `terrain/terrain.gdshader`, `terrain/atmosphere.gdshader`,
`terrain/cloud_layer.gd`, `terrain/night_lights.gd`, `terrain/night_vision.gdshader`, `terrain/airbases.gd`, `terrain/ground_textures.gd`, `util/model_detail.gd`, `terrain/weather.gd`. Tests: `tests/godot/test_graphics_prefs.gd` (switches → render
settings, save / load), `test_ui_smoke.gd` (Graphics → MORE and Extras rows in EN / HE), `test_night_lights.gd` (§4 light points, §5, §8 the goggles key), `test_water.gd` (§1.3), `test_ground_textures.gd` (§1.4), `test_particle_effects.gd` (§6), `test_airbases.gd` (§7), `test_model_detail.gd` (§9), `test_rain.gd` (§10: the levels, and the switch × mission weather rules).

## 1. Options

Preferences → Graphics → MORE has our rendering rows. MSAA = multisample anti-aliasing, FXAA = fast approximate anti-aliasing,
TAA = temporal anti-aliasing, FSR = AMD FidelityFX Super Resolution.

| Graphics → MORE row | choices (first = default) | what it sets |
|---|---|---|
| Anti-aliasing | MSAA 4x / + FXAA / TAA / FSR 2 | MSAA 4x: viewport `msaa_3d` 4× (the project's setting since the start). + FXAA: also `screen_space_aa` FXAA, which softens the shader / texture edges that MSAA misses. TAA: `use_taa` in place of MSAA; it resolves sub-pixel shimmer over time (thin runway lines, distant wires), is a little softer and may ghost in fast rolls. FSR 2 (MetalFX on Metal): the temporal upscaler anti-aliases the 3D scene, in place of MSAA and TAA, at the Upscaling row's scale (§1.7) |
| Upscaling | Native / Quality / Balanced | the 3D scene's render scale: Native 1.0; Quality 0.77; Balanced 0.67 of the window. With Anti-aliasing MSAA 4x / + FXAA / TAA a spatial upscaler scales it up: MetalFX spatial on Metal, FSR 1 on other drivers (`render_options.gd upscale_mode()`), and the Anti-aliasing row still applies. With Anti-aliasing FSR 2 the temporal upscaler does it (FSR 2.2, MetalFX temporal on Metal), at Native as anti-aliasing only (§1.7). The 2D cockpit, HUD and MFDs are canvas items, drawn after the upscale at the window's resolution. Godot lowers the texture mip bias by log2(scale). Spatial saves 0.6 ms (Quality) / 1.4 ms (Balanced) at 4K today, 4.6 / 6.3 ms with SSAO + SSIL; Balanced breaks one-pixel 3D lines into dots (docs/graphics-research.md §3.10) |
| Terrain close up | Original / Detailed | 16× anisotropic filtering (default 4×) for the grazing view of the ground, and in `terrain.gdshader` detail that follows the imagery, with a weight k fading from 1 at 300 m to 0 at 1.5 km (§1.1) |
| Sky | Original / Atmospheric | Original: our gradient sky (ProceduralSkyMaterial) with the fixed fog colour. Atmospheric (by day; at night the Original sky): `atmosphere.gdshader`, a clear-day sky computed from the sun's direction and the camera's altitude. The fog takes its colour from the sky (`fog_aerial_perspective` 1, `fog_sun_scatter` 0.1) and keeps its density (the original's fog distances). The ambient light is that sky's, and a bounded auto-exposure adapts the 3D view by at most 1.25× either way (§1.2). The cloud layer shows separate clouds (§1.2). Glow / bloom is off (it cost 3 ms) |
| Night lights | Original / Detailed | Original: the original's light points (§4). Detailed: glowing lights, the home airbases lit at night, the jets' navigation lights and strobe, stars, a moon and moonlight (§5) |
| Night vision (Shift+N) | Off / Goggles | Goggles: Shift+N in flight puts the night-vision goggles on and off: the 3D view turns into a green image-intensified picture, the cockpit stays as it is (§8) |
| Water | Original / Detailed | in `terrain.gdshader`: waves, sun glint and the sky's reflection on the sea and on lakes (§1.3) |
| Models | Original / Detailed | Detailed: our detailed aircraft models where one exists (today the F-16D), parsed once and shared, with runtime LODs ([aircraft-models.md](aircraft-models.md)) |
| Model detail | Original / ambientCG | ambientCG: fine CC0 surface detail (normal, roughness and brightness: paint chips, scratches, grime, rubber grain) on the original models up close, over their own textures (§9). Greyed out ("Not downloaded") until setup has downloaded the materials. Takes effect when a model loads (the next flight) |
| Particle effects | Original / Detailed | Detailed: explosions, smoke and missile trails as GPU particles, contrails above 9000 m and a heat haze behind each engine (§6). Takes effect at the next flight |
| Rain | Off / Light / Heavy | Light / Heavy: rain as the weather: falling rain around the camera, drops on the canopy in the cockpit views, wet ground, a shorter visibility under an overcast, a dimmer sun (§10). The original has no weather |
| Rolling wheels | Original / Rolling | the wheels of a model with wheel frames turn as the jet rolls (today the F-35I; docs/part-animation.md §2.2) |
| Airbases | Original / Detailed | in `terrain.gdshader`: near the ground, a procedural runway, taxiway and apron surface with ICAO markings over the nearest base's paved surface (§7); always on in World scale Real |
| Ground textures | Original / ambientCG | in `terrain.gdshader`: near the camera, where they resolve, CC0 photo textures of asphalt, concrete, sand, gravel, grass, soil and rock, chosen per pixel from the imagery's colour (§1.4). Greyed out and not clickable ("Not downloaded") until setup has downloaded them; a saved ambientCG without them loads as Original |
| Scenery | Off / On | On: buildings and trees over the Survey of Israel 2 m photo, streamed with the ground (`terrain/scenery.gd`, `scenery.gdshader`; [scenery.md](scenery.md) §3). The row sits under Imagery Israel. "On" is greyed out with "Not downloaded" until setup has made the scenery, and with "Needs Survey 2 m" while the Israel imagery picked on the page is not a Survey 2 m layer; picking another Israel imagery turns it off. A saved On without either loads as Off. Takes effect at the next flight |

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
- **Water** keeps the plain imagery. Water means the generated open sea and the inland water of
  terraintype.dat (0x6, island leaves excluded). To find it, `render_options.gd` asks Rust (`IafSurface`,
  `iaf_formats::terrain_types`) for terraintype.dat around the camera as a 256 × 256 texture of 96 m texels, 24.6 km
  across (global `terrain_surface`, R = water, G = airbase). It rebuilds the texture in one call when the camera is
  4 km from its centre. The Water option (§1.3) uses the same texture.

Design points:

- The noise textures are centred (mean 0.5) and every term is 0 at their mean. Distant mipmaps and the fade-out
  therefore leave the imagery's colours unchanged from afar.
- The terrain grid has no tangents. The fragment shader builds the detail normal from the world X / Z axes and leaves
  `NORMAL_MAP` unset (setting it makes Godot warn on every node).
- The scales are coarse on purpose: finer noise (the first version: ±7 % brightness at 2.4 m / 0.5 m features) is
  sub-pixel beyond ≈ 50 m.

### 1.2 Atmospheric sky

The Atmospheric sky computes the radiance L of each view direction with single scattering, plus a multiple-scattering
term (below):

`L = E · sun · [P_R(μ)·(1 − e^(−τ_R·m)) + P_M(μ)·(1 − e^(−τ_M·m))]`

- m is the air mass along the view (Kasten-Young, capped at 6).
- P_R is the Rayleigh phase function; P_M is Henyey-Greenstein (g 0.75).
- τ_R / τ_M are the optical depths of the air (per channel) and of the haze. They thin with altitude (scale heights
  8 km / 1.5 km). The shader receives the altitude in 250 m steps, so Godot re-filters the sky's radiance only when the
  step changes, not every frame.
- Multiple scattering adds an isotropic term (after Hillaire 2020's[^hillaire] isotropic multiple scattering,
  fitted, no look-up table): `E · sun · (1 − e^(−(τ_R+τ_M)·2)) · (1 − e^(−τ_R·m)) · clamp(0.25 + sin h, 0, 1)`,
  h the sun's elevation. It fills the band 90° from the sun that the Rayleigh phase leaves dark, and with a low
  sun it takes the reddened sun's colour.
- The sunlight is reddened by its air mass beyond the zenith's, with its own optical depths (0.08, 0.22, 0.4),
  closer to λ⁻⁴ than τ_R: through τ_R's strong blue a low sun turned the sky olive. Light scattered high up
  (looking up) crossed less air: the path is scaled by 1 − 0.6·√(view elevation's sine), and by
  0.2 + 0.4·(1 + μ), so the sky away from a low sun stays blue-grey (fitted for ozone's absorption of the orange
  light), capped at 6 air masses (beyond, the haze toward the sun turned a flat salmon). The sky keeps the
  reddening's hue but only part of its dimming (the red channel's transmittance to the power 0.3), so the horizon
  toward a low sun stays bright: white at noon, golden to peach at 19:30 toward the sun, blue-grey away from it.

The sky also lights the scene:

- **Ambient light**: the environment's ambient comes from the sky alone (`ambient_light_sky_contribution` 1,
  energy `SKY_AMBIENT` 0.6 in `render_options.gd`) in place of the time of day's ambient factor (§4). Models and
  terrain take the sky's colour: a blue fill by day, warm with a low sun. The noon value equals the Original
  sky's (factor 0.6 × sky). At night the Original sky and its rules come back (§4, §5), so night is as before.
- **Auto-exposure**: Godot's auto-exposure on the WorldEnvironment's CameraAttributesPractical. Godot measures the
  3D scene's mean luminance (the mean of each pixel's brightest channel, ≈ 1 by day, the sky's blue) and scales
  the exposure by `EXPOSURE_REF / luminance` (1.0), the luminance clamped so the factor stays within 1/1.25 …
  1.25 (min / max sensitivity 640 / 1000 ISO). It adapts at Godot's default speed (≈ 2 s), so a glance from the
  sky to the ground or a dark panel eases in. A low sun's dimmer scene gets +25 % at most: dusk stays dusk. It is
  off with the Original sky and at night. The 2D cockpit art, the HUD and the MFDs are canvas items drawn after the
  3D view's tonemapping: their brightness never changes. Night vision (§8) has its own gain on the tonemapped
  picture.

**Shots**: `tests/godot/_sky_shot.gd` (usage in its header) captures the same views at chosen hours and altitudes,
from the cockpit and outside, with a fixed cloud texture, to compare the sky before and after a change.

Tuning:

- The τ_R values (0.045, 0.13, 0.6) are tuned, not the physical λ⁻⁴ values. Plain single scattering gives a pale
  cyan zenith and a white horizon 7× brighter, which the AgX tonemapper turns grey.
- The tuned values give a deep blue zenith (≈ the gradient sky's top), a pale horizon 2–3× brighter, and a darker
  zenith at 9000 m.
- Below the horizon the shader keeps the horizon's air path in the same azimuth, and the fog over the ground takes
  that colour. Three things change there:
  - the scattering angle is the true view's, so the haze glows warm only toward the sun (the phase functions'
    forward lobe) and stays blue-grey elsewhere;
  - the optical depths fade to sea level's by 6° down: looking down from altitude, the view goes into the lower
    air and its haze (else the haze vanishes at 5000 m, whose own horizon has little of it);
  - the colour darkens to 0.55 by 30° down (the ground's shade, not lit air), except in the forward glow. This is
    the light from below for the ambient, and the fog of near ground, which Godot takes from a blurred radiance
    level. A uniform horizon colour there gave a brown filter over the whole view at sunset.
- The sun's disc (0.53°) has a crisp edge: the shader takes its angle from the chord, because `cos` near 1 loses the
  disc in float precision. Around it is a narrow glare (e-folding 1.5°).

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

With either Water choice, the vertex shader (`is_open_sea`) gives the generated open sea a flat normal, so the sea-bed
relief under the data surface does not shade the water. It takes the colour from mip level 3 and compares it in sRGB
within 0.08 of `sea_colour`, the outer edge of the fragment test above. (Compared in linear colour, no vertex
matches, and the sea bed leaves faint streaks of up to 5 / 255 on the water off Haifa and Nahariya.)

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

### 1.4 Ground textures

The ambientCG choice puts real ground textures under the jet. They are CC0 (public domain) photo-scanned materials from
ambientCG[^ambientcg]. The repo holds none of them: setup's optional `textures` step downloads them (docs/setup.md).
Without them the row's ambientCG choice is greyed out, cannot be picked and reads "Not downloaded" (run `./setup`
again online); a saved ambientCG then loads as Original, so the switch is never half on.

| layer | material | real size of one repeat | used for |
|---|---|---|---|
| 0 | Asphalt027C | 2.5 m (inferred: ambientCG gives none; the sibling Asphalt033 is 2.5 m) | grey ground in an airbase: runways and taxiways |
| 1 | Concrete040 | 1.4 m | the blue / purple tinted aprons in an airbase; the Detailed airbases' apron slabs |
| 2 | Ground054 | 3.5 m | pale ground: sand |
| 3 | Ground062L | 3.0 m | grey-brown ground: gravel desert, and grey ground outside airbases (towns, roads) at 60 % strength |
| 4 | Ground037 | 2.1 m | green ground: grass and fields |
| 5 | Ground109 | 2.8 m | saturated brown ground: dry soil and scrub |
| 6 | Rock045 | 2.4 m | slopes steeper than ≈ 30° |

How the shader uses them:

- **Where**: where a texture resolves; none on water. The shader takes the pixel's ground footprint gm (the geometric
  mean of its two axes, as the anisotropic filter sees it): full strength up to 0.05 m, none past 0.12 m (a repeat of
  2–3 m under ≈ 20 pixels). At 2560 × 1440 that is ≈ 100–250 m looking down, less at a grazing angle. Farther and
  grazing pixels skip the samples. The first fade (0.1–0.25 m) showed the grass layer's tiling as a lattice of
  diagonal stripes at 100 m above fields.
- **Colour**: the texture's colour divided by its own mean colour multiplies the imagery's colour. Setup stores that
  ratio, halved, in the colour map. The photo keeps its own hue and brightness; the texture adds cracks, stones and
  grass blades.
- **No grid of repeats**: the strength varies over ≈ 9 m clumps (pavement: ≈ 4 m) with the close up's noise.
- **Normal and roughness**: the material's normal map tilts the surface normal, and its roughness map sets the
  roughness (0.8–1.0 on natural ground, 0.75–1.0 on pavement).
- **Choice per pixel**: the imagery's colour picks the layer weights, compared in ≈ sRGB. In an airbase
  (terraintype.dat 0x10) grey is asphalt and the blue / purple tint is concrete. Elsewhere green is grass, bright
  (≥ 0.55) is sand, saturated brown is soil, and the rest is gravel. The slope of the terrain grid picks rock. The
  strongest layer is sampled, and the second one too where it weighs a fifth or more: two or four texture samples
  per pixel (colour, roughness + normal).
- **With Terrain close up**: the textures take the place of the close up's fine grain (the 16 m noise and its normal
  detail) up to a 0.03 m footprint, and share it up to 0.1 m. Past that a texture of a few metres no longer reads,
  and the grain reads better. The close up's patches stay at every distance.
- **With Detailed airbases** (§7): the procedural pavement takes asphalt in place of its 2.3 m aggregate grain and
  its micro relief, and its apron slabs take concrete. The markings, tyre rubber, seams and repairs are drawn as
  before, over the texture. The close up's own airbase layers are skipped there, so a pixel never samples both.
- **Scale**: the textures repeat at their real size in world metres. The imagery's colour changes every few metres
  and breaks up the repeat.

Files and loading:

- Setup (`iaf_tools::thirdparty`, `iaf-textures`) downloads `<id>_2K-JPG.zip` for each material, checks it against a
  pinned SHA-256, and keeps the colour, normal (OpenGL) and roughness maps in `assets/thirdparty/ambientcg/<id>/`.
  It packs them at 1024² with every mip level, compressed as the GPU reads them (texpresso, cluster fit): `albedo.bc1`
  (BC1 / DXT1, RGB: the linear colour over its mean, halved) and `nr.bc3` (BC3 / DXT5: R roughness, G normal Y, B the brightness detail Model detail reads (§9),
  A normal X). `ground.json` lists the layers in order with their sizes. The step takes ≈ 1 minute after the
  download.
- 1024² is ≈ 2.4 mm per texel on a 2.5 m repeat, finer than a pixel of the ground at 2560 × 1440 from the cockpit.
- The game (`terrain/ground_textures.gd`) reads the packed maps (≈ 15 MB, ≈ 5 ms) on a worker thread while the
  mission screens are open (`terrain_preload.gd`); the flight's start uploads them as two texture arrays. Nothing is
  decoded or compressed in the game. The switch itself is a shader uniform (`ground_tex`), so the terrain shader is
  the same with it on or off: no new shader compiles in flight.
- Video memory: 7 layers × (0.7 MB + 1.4 MB) ≈ 15 MB.

Cost on an Intel Iris Xe (TigerLake GT2) laptop at 2560 × 1440, 2026-10-22, X11 window, vsync off. The GPU column
is the median of 12 pairs switching `ground_tex` 0 / 1 in place (`tests/godot/_airbase_shot.gd`, `SHOT_BENCH=ground_tex`):

| pose | other options | frame, switch off | GPU cost of the switch |
|---|---|---|---|
| lineup on Ramat David's runway 27, cockpit | defaults | 13.5 ms (74 fps) | +1.05 ms (−7 % fps) |
| the same | Terrain close up + Detailed airbases | 20.0 ms (50 fps) | +0.92 ms (−4.5 %) |
| 300 m above the Halutza sands, looking 35° down | defaults | 17.8 ms (56 fps) | +1.61 ms (−9 %) |
| the same | Terrain close up + Detailed airbases | 20.1 ms (50 fps) | +1.18 ms (−6 %) |

Hitches (`tests/godot/_ground_tex_bench.gd`, mission 311, three runs each, the switch off / on):

- Upload at the flight's start, after the mission screens' preload: 0 / 5.5–6.4 ms.
- Mission start (scene change to the first flying frame, without the terrain preload): 37–46 s / 44–48 s before the
  loading screen's frame cap; 2.6–2.8 s now (§1.5).
- Worst frame in the first 30 s on the ground: 61–86 / 62–65 ms; average 52–59 / 55 fps.
- Worst frame in a low pass over the base (60 m, 150 m/s): 29–31 / 30–31 ms; average 55 / 53–54 fps.
- Video memory: +15.9 MB (Godot's texture memory monitor).

### 1.5 Loading the flight

Between Fly and the first flying frame the flight scene loads, builds itself and waits for its ground behind the
loading screen (`terrain_view.gd` `waiting_for_ground`). The flight starts once every terrain node in view is at full
detail and the mission's models are parsed. What runs where:

| step | where | cost on the Iris Xe laptop (mission 311, 2560 × 1440) |
|---|---|---|
| the flight scene's scripts and resources | a loader thread, while the mission screens are open (`terrain_preload.gd` `preload_scene`) | ≈ 0.85 s |
| the first frame's art: the loading screen's menu art, the cockpit art (the scene's default F-16 cockpit and the player's jet's; a file both load, as the F-35I's borrowed MFD and RWR art, serves both), the player's jet model, its cockpit-view model, the models it borrows parts from (the F-35I's F-16 pilot) and its stores' models; the effects' art (the cloud layer, the trails, the flares and chaff, the afterburner flame) | worker threads, once the scene has loaded (`prefetch_flight`: `Img.prefetch`, `Gltf.parse_file_ahead`) | ≈ 0.17 + 0.23 + 0.15 s |
| the scene's build (`_ready`) | the main thread, over six frames behind the loading screen; between them only the terrain and the loading screen run | ≤ 0.2 s a frame |
| the terrain's nodes: about 300 colour nodes (setup's BC1 `.dds`, else JPEG, mipmaps, BC1) and 50 height nodes | 4 worker threads (`terrain.gd` `max_jobs`); the texture uploads on the main thread, ≤ 4 ms a frame (`UPLOAD_MS`) | ≈ 1–3 s |
| the mission's models (every placed unit's model and its LOD copies, the AI's jets; with Models Detailed the detailed F-16D and stores) | worker threads parse the files, make their mipmapped textures, set their materials and, for a detailed model, its LODs and meshes, from the mission screens on (`TerrainPreload.mission_models`, `Gltf.parse_ahead`); the main thread takes them for ≤ 12 ms a frame (no GPU readback) | ≈ 1.5 s of worker time (the F-16D ≈ 0.4 s), done before Fly after a few seconds on the TSD |
| the spawn of the mission's units and the AI's jets | the main thread, the first flying frame (one parse per jet type, `Gltf.model`) | ≈ 0.25 s (mission 224) |

Three things made the start slow, measured 2026-10-22:

- **The GPU encoder and the loading screen's frame rate.** In a window `Image.compress` (BC1) ran on the GPU (Godot's
  Betsy encoder, ≈ 6 ms an image on an idle GPU), one image at a time. Setup's pre-compressed tiles and the CPU
  encoder (below) have since removed it. Behind the loading screen the 3D view still
  renders every frame. Uncapped (the bench turns vsync off; the X11 window presents at once) the frames took the GPU
  and each image waited ≈ 250 ms: the ground took 35–45 s. While the loading screen is up the frame rate is capped at
  30 fps (`LOADING_FPS`; a lower Max FPS stays): the images take ≈ 20 ms and the ground ≈ 2–3 s. Ground textures on
  made each of those frames ≈ 1 ms dearer, which slowed the encoder by ≈ 3 s in the uncapped bench; capped it is
  within the spread. Headless runs have no GPU encoder: the CPU encoder takes ≈ 5 ms an image.
- **Two decode threads.** The terrain's decode tasks were low-priority pool tasks, which Godot runs on 30 % of its
  threads[^wtp]: 2 of 8 here. They are high-priority now, 4 at once; 6 slowed the main and render threads, and the
  first frame of the built scene took ≈ 0.5 s instead of ≈ 0.1 s.
- **Work in one frame.** The scene load (0.85 s), its build (0.85 s: the loading screen's 2560-pixel menu art
  0.17 s, the cockpit art 0.26 s, the jet model 0.15 s, the first draw 0.1 s) and the mission's units after the ground
  (0.5 s, mostly the PNG textures of the runway model) each froze one frame.

Measured with `tests/godot/_ground_tex_bench.gd` (`GT_PRELOAD=1` does the mission screens' preload; three runs each,
the switch off / on, X11 window, vsync off):

| | before | after |
|---|---|---|
| mission start (scene change to the first flying frame) | 37–45 s / 45–47 s | 2.6–2.7 s / 2.6–2.8 s |
| stalls over 250 ms from Fly on | three each: the scene load 0.87–0.91 s, its build 0.87–0.91 s, the units' spawn 0.58–1.10 s | none |
| worst frame in the first 30 s on the ground | 52–62 / 62–64 ms | 28–61 / 49–73 ms |
| video memory at the end | 972 / 988 MB | 972 / 988 MB |

The bench's own stalls before the scene change (one of ≈ 1000 ms every ≈ 1.35 s while it waits, the scene shown as
`?`) come from the test harness under X11 (XWayland): a script with no scene, in an empty project, shows them too; the
main thread waits in the Intel Vulkan driver's present. Headless or in a Wayland window they do not occur.

#### Pre-compressed tiles and the mission screens

The terrain compresses nothing at run time when setup's `bc1` step has run (docs/setup.md): beside each colour tile
`c_<x>_<y>.jpg` lies `c_<x>_<y>.dds`, BC1 with every mip down to 1 × 1. A decode worker reads the file and hands it
to `Image.load_dds_from_buffer` (≈ 0.3 ms a node, no decode, no compression). Without the file (a setup without the
step, or `Terrain.precompressed` off) the worker decodes the JPEG, makes the mipmaps and compresses them as before.
That fallback runs on the CPU encoder: `rendering/textures/vram_compression/compress_with_gpu` is off in
`project.godot` (Godot reads it at each `Image.compress`; the project imports no VRAM-compressed textures), so the
workers no longer wait for the GPU (Betsy here, Metal's on a Mac) behind the frames. Keep it off: with it on, the
flight's start could hang for good (seen 2026-10-22 under CPU load, 2 starts in ≈ 11). Godot 4.7's Betsy encoder runs
as a worker-pool task that, while idle, yields its thread to other pool tasks (`WorkerThreadPool::yield`). The pool
gave that thread a terrain decode task, which called `Image.compress` and waited for Betsy, the loop beneath it on
the same thread's stack. The other decode tasks waited for Betsy too, and the ground never finished (a gdb backtrace
with Godot's debug symbols: `BetsyCompressor::_thread_loop` → `yield` → `_wait_collaboratively` → the decode →
`_betsy_compress_s3tc` → `push_and_ret`). The few nodes that World scale
Real patches or overlays (`_bake`, `_inset_image`) still take the JPEG path.

The `.dds` is the same picture within BC1's error: over four `mapi2015_modern` tiles the mean absolute difference to
the JPEG is 3.8–3.9 (of 255) for the `.dds` and 4.8–5.0 for Godot's CPU encoder; between the two 4.7–4.8. The test
(`test_terrain.gd`) compares a node's 64-pixel mip both ways (3.6).

What froze the mission screens: the TSD preloads the start's ground (`terrain_preload.gd`) and, since the scene
preload, the flight scene and its first frame's art. Three main-thread steps took a frame each, measured on the TSD
with the imagery layers on:

- the texture uploads: every decoded node of the frame at once, up to 233 in one frame (116 ms) once the `.dds`
  made the workers fast. Now ≤ 4 ms a frame, the rest the next frames (`_finish_jobs`; the flight's `adopt` still
  takes them all);
- the preload terrain's set-up (`_ready`: the layers' manifests, the node lists, the meshes, `terraintype.dat`;
  ≈ 80 ms). Its pure part (`prepare()`) now runs on a worker thread before the node enters the tree;
- the choice of nodes (`_reselect`, ≈ 12 ms with the imagery layers) after every frame that brought data: now at
  most every 100 ms (`LOADED_RESELECT_MS`).

Left on the main thread: the flight's first-frame prefetch (`prefetch_flight`, ≈ 30 ms once: the mission's files
and the jet's descriptor) and the node choice (≈ 12 ms every 100 ms while data arrives).

Measured 2026-10-23 on the Iris Xe laptop (2560 × 1440, X11 window, vsync off; other agents' headless jobs ran on the
CPU meanwhile). Imagery: Israel `mapi2015_modern`, outside `sentinel2_modern` (the latter has no `.dds` yet on this
machine, so outside Israel takes the fallback), TAA, atmospheric sky, detailed models and airbases.

TSD, 20 s from the screen's opening with a flight change every 2 s (`tests/godot/_tsd_bench.gd`); no stall over
250 ms in any run:

| | before | after, `.dds` | after, fallback |
|---|---|---|---|
| worst frame, imagery on | 179 / 81 / 234 ms | 46 / 46 / 37 ms | 81 / 55 ms |
| the start's ground loaded, imagery on | 3.9–8.1 s | 0.6–0.8 s | 2.8–3.3 s |
| worst frame, original imagery | 49 / 53 / 55 ms | 48 / 39 ms (89 ms in a run under heavy CPU load) | |
| the start's ground loaded, original imagery | 2.9–3.2 s | 0.7 s | |

Flight start and a low fast pass (600 kt at 300 m for 60 s, heading west, frozen flight model;
`tests/godot/_stream_bench.gd`), two runs each:

| | before | after, `.dds` | after, fallback |
|---|---|---|---|
| one colour node on a worker thread | 88–99 ms | 0.3 ms | 40–60 ms |
| mission start 311 / 115 | 4.1–5.8 s / 4.0–6.3 s | 4.0–5.0 s / 3.3–3.8 s | 5.5–6.5 s / 4.2–4.3 s |
| pass: node-seconds waiting (the sum over frames of the nodes queued or decoding × the frame's time) | 21–26 | 3–4 | 9–15 |
| pass: worst frame | 59–124 ms | 41–92 ms | 74–90 ms |

The mission start with these settings still shows one or two stalls of 0.5–2.8 s in the flight scene's first frames,
before and after alike (not the terrain: its nodes were loaded by then). §1.6 found them: the detailed F-16D's parse
(≈ 1.1 s; now on the mission screens, below) and the first frame's pipelines with TAA (0.6–0.75 s), and 5–11 s more on a cold shader cache. The pass's worst frames are the 3D view's
own (≈ 45 fps average); the waiting nodes drop by a factor of 6.

#### The mission's models on the mission screens

The TSD's preload also parses the models the flight's spawn will draw, once the flight scene has loaded
(`terrain_preload.gd` `prefetch_flight`): the player's jet and cockpit-view model first, then every placed unit's
model with its LOD copies and the AI's jets (`mission_models`, the same list the flight's loading screen waits for).
They parse on low-priority pool tasks, which leave the decode tasks and the menu's threads free.

- **Textures off the main thread.** A parse decodes each model's base colour image (the file beside the `.gltf`)
  and makes its mipmaps on the worker (`Gltf._own_textures`). Finishing a model on the main thread used to read its
  texture back from the GPU to add the mipmaps: ≈ 30 ms a model, one model a frame behind the loading screen (80
  models in mission 224: ≈ 3 s). Now mission 224's 80 models finish inside its 0.8 s start. A model with an embedded image is parsed as Godot's import does.
- **Detailed models.** With Models Detailed the list holds the detailed model in place of the original it stands
  in for: the player's jet, the AI's jets and the parked ones (`Gltf.object`). Its parse makes the LODs and the meshes
  on the worker too, and reads its embedded KTX2 base colour images itself (`Gltf._image`), so no texture is read
  back from the GPU. The prefetch sets the flight's OBJECT DETAIL level first (`Gltf.object_level`), so the materials
  are set for it on the worker; at another level `open()` sets them again on the main thread. The F-35I (an extra
  plane, no detailed stand-in) parses ahead as before, and now its cockpit-view model too (`f35i_bc.gltf` in
  `extra/planes`, which the prefetch looked for among the install's models).
- **One parse per jet type.** The AI's jets parsed their model once per jet in the first flying frame (1.3–3.3 s in
  mission 224); `Gltf.model` keeps one per file and OBJECT DETAIL level, shared like the units' models.
- **One set held.** The parses are keyed by the mission, the flight and the jet. Another flight or jet drops the
  parses the new choice does not use (`Gltf.drop_ahead`); leaving the mission screens drops them all; the flight
  drops what it did not take after its spawn. A parse not finished when the flight needs it is parsed there, not
  waited for behind the queue. At exit the game waits for the parses still running (`Gltf.finish_ahead`): with
  them never waited for, Godot's exit hung in `WorkerThreadPool::exit_languages_threads`.
- **The menus.** The preload's terrain runs 2 decode tasks (the flight's 4). A Fly while the flight scene or its
  first frame's art is still loading waits over menu frames (`ready_to_fly`), not in one frame.

Measured 2026-10-23 on the Iris Xe laptop (2560 × 1440, X11 window, vsync off, `.dds` tiles, default settings;
`tests/godot/_preload_bench.gd`: the TSD opened, `PB_WAIT` seconds there, then Fly). Three runs each, before / after:

| | before | after |
|---|---|---|
| mission 311, Fly after 6 s on the TSD | 0.95–1.04 s | 0.52–0.68 s |
| mission 224 (F-4, 7 AI jets, 80 unit models), after 6 s | 1.87–2.26 s | 0.74–0.82 s |
| mission 311, Fly in the TSD's first frame | 2.12–2.58 s | 2.04–2.60 s |
| mission 224, Fly in the TSD's first frame | 3.31–4.09 s | 2.93–3.57 s |
| mission 311, Fly after 0.5 s (one run) | 1.58 s | 1.15 s |
| stalls over 250 ms after Fly, 6 s on the TSD | 311: none; 224: the spawn 0.49–0.67 s | 311: none; 224: 0.26 s in one run of three |
| stalls over 250 ms after Fly at once | the flight's first frame 0.5–0.86 s; 224: the spawn 0.51–0.64 s | the flight's first frame 0.5–0.78 s |
| stalls after Fly at 0.5 s | 0.29 s and 0.49 s | none |
| TSD worst frame while the preload runs, 311 | 32–37 ms | 32–36 ms |
| TSD worst frame, 224 | 37–44 ms | 34–49 ms |

A Fly in the TSD's first frame is the bench's limit: the TSD's own set-up frame (0.35–0.55 s, before and after
alike, `stall … in FrontEnd / tsd`) shows as a stall `in ?`, and the flight builds everything itself. The TSD of
missions 224 and 115 runs at ≈ 30 fps with the preload off too (its map); the preload's share is a few frames over
16.7 ms.

### 1.6 Shader compiling

Godot turns each shader into GPU code in two steps: the shader source to SPIR-V (per variant group), then a pipeline
(the shader with its draw state) by the driver. Both are cached in the game's user folder, and the driver keeps its own
cache too:

| cache | where (Linux) | holds |
|---|---|---|
| Godot's shader cache | `~/.local/share/godot/app_userdata/iaf-reborn/shader_cache` (`user://`; tests with `IAF_DEFAULT_SETTINGS` use the same folder) | the SPIR-V of every shader, one file per source + defines hash and variant group |
| Godot's pipeline cache | `…/iaf-reborn/vulkan/pipelines.forward_plus.<GPU>.cache` | Vulkan's pipeline cache, saved at exit and every few MB |
| Mesa's cache | `~/.cache/mesa_shader_cache_db` | the Intel driver's compiled shaders |

Both of Godot's caches are kept between runs: a second run has no shader cache miss (`--verbose` prints each miss).
On the Mac, Godot keeps the same `shader_cache` folder (in `~/Library/Application Support/Godot/app_userdata/`), and
macOS keeps the compiled Metal pipelines in its own per-app cache (inferred; not measured on the Mac).

Our shaders hit the cache every run. The code the game builds at run time is fixed text: the night lights' glow
(`night_lights.gd`), model detail's three cull modes (`model_detail.gd`), the particles (`gpu_fx.gd`), the cloud
layer and the debris (`damage_effects.gd`). The options that switch shader paths are global uniforms
(`terrain_detail`, `terrain_water`, `ground_tex`, `terrain_airbases`), so switching them compiles nothing.

What compiles when, measured 2026-10-23 on the Iris Xe laptop (2560 × 1440, X11 window, vsync off; mission 311, Fly
in the TSD's first frame; `tests/godot/_preload_bench.gd`, which also counts Godot's pipeline compiles per frame).
Cold: Godot's two caches deleted and Mesa's off (`MESA_SHADER_CACHE_DISABLE=true`), as on a first run or after a
Godot or driver update. Warm: the next run. "Yours": the Mac list (TAA, upscaling Quality, Atmospheric sky, Detailed
night lights / water / particles / airbases / models, Terrain close up, Better cockpit, Real HUD, both ambientCG
options, Night vision).

| | defaults, cold | defaults, warm | yours, cold | yours, warm |
|---|---|---|---|---|
| launch to the main menu | 2.8 s | 1.4 s | 2.7–2.8 s | 1.4–1.5 s |
| Fly to the first flying frame | 5.4 s | 2.0–2.1 s | 14.5–15.0 s | 3.9–4.3 s |
| longest frames behind the loading screen | 2.9–3.3 s | 0.96 s | 6.4 s, 4.6–5.0 s | 1.2 s |
| pipelines compiled while drawing (these stall) | 0 | 0 | 9 | 9 |

- **At launch** Godot's Forward+ renderer compiles every built-in effect, used or not: SDFGI, VoxelGI, screen-space
  reflections, SSAO, SSIL, volumetric fog, depth of field, subsurface scattering, SMAA, besides the ones we use. Cold
  this is ≈ 1.4 s of the launch; warm they load from the cache. Godot 4.7 has no project setting that skips them, and
  none of them is switched on in our environments, so `project.godot` has nothing to turn off.
- **At the flight's start** each material's shader compiles (16 with the defaults; with TAA each also in a second group
  for the motion vectors: 124 misses in all). With the defaults Godot compiles every pipeline when the mesh enters the
  scene, in the background. With TAA it compiles 9 of them while drawing the first frames: 6.4 s and 4.6 s frames
  cold, ≈ 0.4 s warm (inferred from the same frame without TAA: 0.19 s against 0.6–0.75 s).
- **In flight**, things drawn for the first time compiled there. Two are now drawn behind the loading screen:
  - the external view: a cockpit start draws one frame from the chase camera, then returns (`terrain_view.gd`
    `_warm_views`), so the jet's exterior and the chase view's pipelines compile there;
  - the debris: both debris materials drawn once, too small to see, in front of the camera (`damage_effects.gd`
    `warm_up`, as model detail's).

The first time each shows in flight, yours (worst frame within 2 s; `PB_EVENTS=1`):

| | cold, before | cold, after | warm, before | warm, after |
|---|---|---|---|---|
| the first external view (F2) | 4.9 s | 8 ms | 18–25 ms | 8 ms |
| the first debris | 1.27 s (defaults 0.88 s) | 70 ms (defaults 26 ms) | 79 ms (with the fireball) | 69 ms |
| the first fireball and flash | 108–117 ms | 108 ms | 11 ms | 11 ms |
| the goggles on | 26 ms | 27 ms | 12–25 ms | 12 ms |

The cold start with your settings takes the moved compiles behind the loading screen: 22.9 s (one run) against
14.5–15.0 s; the warm start stays at 4.2 s, and the defaults' at 5.4 s cold and 2.1 s warm.

Left warm with your settings, Fly after 6 s on the TSD, measured 2026-10-26 (`_preload_bench.gd`, the settings above
without Night vision; other agents' Godot runs on the machine for the F-35I's second run and the spread):

| | before | after |
|---|---|---|
| F-16D, Fly to the first flying frame | 2.30–2.40 s | 1.87–1.93 s |
| F-16D, stalls over 250 ms after Fly | 0.64–0.68 s (TAA pipelines), 1.07–1.13 s (the F-16D's parse 0.37 s, its meshes 0.41 s, its shaders) | 0.97–1.02 s (TAA pipelines and the motion-vector shaders, the F-16D's among them), 0.26–0.30 s (the F-16D's pipelines) |
| F-35I (`f35i_slot=0,jet_id=0`), Fly to the first flying frame | 2.70–2.81 s | 2.29 s (one idle run) |
| F-35I, stalls over 250 ms | 0.27 s, 0.66–0.69 s, 1.26–1.28 s | 0.27 s, 1.07 s, 0.49 s |

The main thread's share of the detailed model is now its scene (≈ 1 ms). The long frames after Fly are all behind
the loading screen (the bench marks each frame "loading" or "first flying"); what was found there, measured
2026-10-26 (same settings, 3 runs each, idle GPU but for other agents' screenshots in the F-35I's "before"):

- **Pipelines for the wrong sample count.** Godot compiles a mesh's pipelines in the background when it enters the
  scene, for the sample count of the project setting `rendering/anti_aliasing/quality/msaa_3d` (4×), not the
  viewport's. With TAA or the temporal upscaler the 3D view has no MSAA, so none fitted and each pipeline compiled
  while drawing (`draw` in the counters). The setting now follows the anti-aliasing choice at run time
  (`RenderOptions.sync_pipeline_samples`, from the mission screens' prefetch and `apply`; Godot reads it every frame).
- **The motion-vector shaders.** The first frame drawn with TAA (the build's fourth, once `apply_render_options` sets
  it) switches on Godot's motion-vector shader group, and `ShaderRD::enable_group` then loads that group for every
  scene shader on the calling thread, from the shader cache (≈ 1.2 s warm). It stays behind the loading screen. Drawn
  earlier (an 8-pixel TAA viewport on the mission screens) it moved there as two ≈ 150–200 ms TSD frames: each new
  scene shader then loads both groups when it is made. Not kept.
- **The jet's pipelines** compile in the external-view frame of `_warm_views` (≈ 0.2 s), behind the loading screen.
- **PNG decodes on the main thread** (gdb on `png_to_image`, main thread only): the F-35I's start read the F-16's MFD
  and RWR art (the default cockpit had taken the prefetched copy), parsed the F-16 model for the borrowed pilot (its
  file has the F-16D as detailed stand-in, so the list skipped it) and its two store models, and every start read the
  cloud, trail, flare, chaff and afterburner art (the afterburner once per flame and AI jet). All now decode on worker
  threads on the mission screens (§1.5 table); the afterburner art is read once. Left: the airbase mask (Airbases
  Detailed, the nearest base, also chosen in flight) and two small menu images.

| | F-16D before | F-16D after | F-35I before | F-35I after |
|---|---|---|---|---|
| Fly to the first flying frame | 2.21–2.39 s | 1.96–2.12 s | 2.38–3.55 s | 2.12–2.21 s |
| pipelines compiled while drawing | 28 | 2 | 23 | 2 |
| the TAA frame (loading) | 1.30–1.46 s | 1.23–1.33 s | 1.25–1.83 s | 1.18–1.26 s |
| the jet's build frame (loading) | 0.27–0.32 s | 0.22–0.24 s | 0.48–0.65 s | 0.37–0.38 s |
| the first flying frame | 75–109 ms | 66–87 ms | 66–119 ms | 58–61 ms |
| worst flying frame, 5 s | 19–51 ms | 14–27 ms | 24–46 ms | 15–17 ms |
| TSD worst frame | 31–57 ms | 33–65 ms | 39–66 ms | 46–68 ms |

### 1.7 Temporal upscaler (Anti-aliasing FSR 2)

Anti-aliasing FSR 2 sets the viewport's `scaling_3d_mode` to `SCALING_3D_MODE_FSR2` (AMD FSR 2.2), or to
`SCALING_3D_MODE_METALFX_TEMPORAL` on Metal (cheaper there, docs/graphics-research.md §3.10; the row then reads
MetalFX). MSAA and TAA are off: the upscaler accumulates jittered frames with the motion vectors and anti-aliases
itself. The Upscaling row sets its input scale; Native (1.0) uses it as anti-aliasing only.

The look, from `tests/godot/_temporal_shot.gd` (mission 231, Iris Xe, 1920×994 window, the jet moved at a fixed step per
frame), against the default MSAA 4x, TAA and Quality spatial:

- **Distant jets.** A jet crossing at 250 m/s, 5 km away, is a dark shape of a few pixels with MSAA 4x. TAA and
  Native FSR 2 keep a faint dot; Quality FSR 2 loses it almost fully; Quality spatial keeps a soft blob. At 10 km the
  jet is under a pixel: one faint pixel with MSAA 4x, nothing with the others. The temporal methods average a
  sub-pixel object that moves across the jitter pattern away.
- **Ghosting.** No trails seen behind the jet rolling 90°/s at 60 m and 300 m/s, nor around a fireball. Quality FSR 2
  draws the ground in motion a little softer than native.
- **The cockpit, HUD, MFDs and the F-35I's panoramic display** (`cockpit/pcd.gd`, a Control) are canvas items drawn
  after the upscale: the same in every mode.

Cost (inferred, not measured on the Iris Xe): the motion-vector pass is what TAA pays already. FSR 2's own passes
cost more than TAA's resolve: on the M4 Pro at 4K, Quality FSR 2 took 11.3 ms against 8.3 ms for native TAA and
9.4 ms for Quality MetalFX temporal (§3.10 there). On the Iris Xe, expect Quality FSR 2 near native TAA (the 3D
scene at 0.59 of the pixels pays for the passes) and Native FSR 2 above it. To measure, run
`BENCH_SET=antialiasing=temporal,upscaling=quality IAF_DEFAULT_SETTINGS=1 godot --path game --resolution 2560x1440
-s ../tests/godot/_flight_bench.gd` against `BENCH_SET=antialiasing=taa` and the default (§3.1), on an idle machine;
or `tests/godot/_upscale_probe.gd`, which cycles the modes in one process.

Making FSR 2 the only anti-aliasing and upscaling choice was considered and rejected (2026-10-26): it fades the
distant jets above, which matter most in a flight sim. MSAA 4x stays the default.

## 2. Cloud layer (Graphics TEXTURED SKY, docs/front-end.md §12.4)

The cloud layer is a dome of cloud texture plus a flat layer, and a whiteout near its altitude. Three findings:

- **Cut.** The original cuts the dome at the terrain's far horizon (`407c70` → `41dc30` → +0x1098) and fills the gap
  at the dome's depth, so the dome never covers drawn terrain. We draw terrain out to 200 km, beyond the dome's lower
  rings (down to height 0 at 21.9 km), so the port draws the dome at the far plane (reverse-Z depth 0, `at_far`),
  behind every terrain point; drawn at its depth it makes a white band across the horizon. The flat layer seen from
  above stays at its depth.
- **Whiteout**, checked in the disassembly (v1.0 41da5e–41da9f):
  - It shows only while |altitude − 7000| < 1000 (`5fb53c`).
  - alpha = clamp(j + 255 − ftol(0.255·|Δ|), 0, 255) (`5fb540` = 0.255).
  - At 6000 m or below there is none. The white "haze" in the 2000 m explosion shot was the dome band (above) and the
    explosion's own smoke column 40 m away.
  - The full-screen whiteout rect is hidden while its alpha is 0.
- **Cost.** 0.15–0.5 ms GPU below the layer, 1.4 ms above it (the flat layer covers half the screen); §3 (a bench
  must skip its first frames after load).

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
- The close up and atmospheric columns above are the first versions (the fine brightness noise of §1.1, plain
  single scattering in §1.2).

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
  when the altitude step changes. These numbers predate multiple scattering, the sky's ambient and the
  auto-exposure (2026-10-26, not yet benched): the multiple-scattering term is a few ALU per sky pixel and per
  radiance texel (≈ 0); the ambient from the sky reads the same radiance as before (0); the auto-exposure adds
  Godot's luminance reduction, a few compute passes over the 3D buffer each frame (expected ≈ 0.1–0.3 ms at
  2560 × 1440 on the Iris Xe). Bench it with `_flight_bench.gd BENCH_BEST=1` against a run with Sky = Original
  (its luminance pass off).
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

  The last two changes are not yet re-measured in a clean A/B on the Iris.

## 4. Time of day (built: game/terrain/time_of_day.gd)

This section describes the original's day / night rendering and our port of it. By these rules only mission 214
starts at night; missions 112, 237 and 515 start at 05:xx, which is dawn.

**Port.** The time of day = the mission start 0x460 + the mission clock (11:00 without a mission).

- Once a sim second the port sets:
  - the sun node's direction and colour;
  - the ambient factor (Godot ambient energy = factor / 0.6; with the Atmospheric sky the sky's own light, §1.2);
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
   wide in the world, kept between 2.5 and 28 pixels at 1080 rows. The rows are the 3D render's (window rows ×
   the Upscaling scale), so Quality and Balanced draw the glows at the same size on screen. It fades with the fog, and it stands 1.5 m above
   its spot, so the ground between the spots leaves it whole. By day the glow is at 35 %.
2. **Home airbases lit at night.** At a night start, a runway model on its home spot (`ul_rwramon`, `ul_rwtelnof`,
   `ul_rwdavid`, `night_lights.gd BASE_LIGHTS`) gets its base's light set (`lt_rmn_h`, `lt_tnf_h`, `lt_dvd_h`). The
   set takes the runway model's spot, heading and scale, as in base mission `bmisrdvdn`. The sets are the
   original's art and match the runway edges in the imagery.
3. **Navigation lights and strobe on every jet** (`aircraft_model.gd`): red on the left wingtip, green on the right,
   white at the tail, and a white strobe on top of the fin. It flashes for 0.08 s every 1.2 s, each jet at its own
   phase. The spots are the model's outermost vertices, or its EndWing helpers when they sit at the wingtips (the
   F-16's sit a third of the way out); cached per model. The cockpit-view model (`<plane>_bc`) carries its own set
   at its own wingtips, tail and fin top, so you see your wingtip lights when you look aside from the cockpit. The
   lights go out when the jet is hit, falls or is destroyed (damage state 3 and above), and when the player crashes.
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

## 6. Effects, Detailed (built: game/mission/gpu_fx.gd)

Preferences → Graphics → MORE → **Particle effects = Detailed** (ours, docs/deviations.md §2) draws the original's effects
with GPU particles. It takes effect at the next flight. What spawns, when, where, how fast, how wide and for how long stays the original's
(docs/damage.md §6): `damage_effects.gd` and `trails.gd` make every decision as in Original and hand each spawn to
`gpu_fx.gd`, which only draws it.

**How it works.** Three particle pools (`GPUParticles3D`, fed one particle at a time with `emit_particle`):

| Pool | Size | Look |
|---|---|---|
| Smoke | 16 384 | alpha-blended, sorted by depth; the shape and edges come from two noise octaves; lit by the sun with a sphere-like normal (bright sunlit side, darker core); soft where it meets the ground (depth fade) |
| Fire | 4 096 | additive; a temperature ramp (white-yellow core, orange, dark red) that cools with age and with the noise; drawn after the smoke, so it glows through it |
| Sparks | 4 096 | additive streaks stretched along their velocity (0.08 s of travel), falling, white-hot to orange |

Each particle carries its spawn data (position, velocity, life, width at birth and death, grey, delay, drag). The
pools only free a particle at the end of its life; the draw shader computes the position, width and fade straight from
the age with a formula (a closed form: no step-by-step simulation), on a clock that advances with the frame time (so it stops in the pause and follows time
compression). The noise texture is generated at run time with FastNoiseLite.

**Per effect:**

| Original effect (docs/damage.md §6) | Detailed |
|---|---|
| Smoke puff (0x100, damage smoke, columns, streamers, smoking pieces, the flare's smoke) | one smoke particle with the puff's position, velocity, life, widths, grey and delay |
| Fireball (0x10, 1.2 s, 256 m sprite) and small fire (0x10000000, burning pieces, cluster bomblets) | a burst inside the same spot and life, every particle ending by the fire's end: 22 rolling fire balls that expand fast and slow down (drag), 28 sparks, 10 dark smoke balls that rise from 0.4 of the fire's life. Small fires get half the particles. The lingering smoke comes from the original's own puffs and columns |
| Missile / rocket trail (trails.gd, 3.5 s) and its motor glow (missFLR) | a continuous smoke trail and a motor flame while the motor burns (below, `missile_fx.gd`); the trail bookkeeping (owners, 99 trails, 256 points) stays the original's |
| Wingtip vortices | the condensation streamers below, instead of the original ribbons |
| Afterburner flame | the original cones, plus the heat haze below |
| Debris, shatter pieces, the flash light, chaff | the original's |

**Missile smoke and flame** (`missile_fx.gd`, fed by `trails.gd` with the head of each missile or rocket trail):

- **Smoke**: one ribbon per trail through the head's positions, a point every 1/30 s (the newest follows the head).
  The vertex shader turns it to face the camera around its length and moves each point by its age: 0.6 m wide at the
  nozzle, ≈ 10 m after 2 s, ≈ 14 m after 5 s, ≈ 18 m at 10 s and ≈ 23 m at 20 s (as wide as the original ribbon,
  for spotting; a first, thinner trail at a real missile's early-seconds width was tried on 2026-10-26 and dropped: at
  range it thinned to a hairline and at dusk it nearly vanished, so launches were harder to spot than with Original),
  swelling and narrowing every ≈ 60 m;
  it meanders slowly, rises a little and drifts with the wind. The fragment shader shades it as a tube: white smoke
  scatters light many times, so its shadow side keeps at least 55 % of the sunlit side's light, plus the gradient
  sky's colours (set by the time of day, §4); the sun's colour warms the sun side, its rim, and the smoke seen
  toward the sun. While the sun is up its colour lights the smoke at full strength (its brightest channel at least
  0.9): the time of day dims the light colour toward dusk for the ground, but sunlit smoke still glows. Its
  brightness never drops below 0.95 (the hue kept), as bright as the original's flat white trail, so a launch is as
  easy to spot at dusk. The scene's
  fog covers it by distance. Two noise octaves, in metres, eat its edges and vary its density, more as it ages; the
  core stays dense. It fades out from 10 s to 20 s and stays after its missile hits or is gone. It is at least 3 px
  wide on screen (thinner smoke gets a lower alpha instead), so a far trail stays a clear band, and a trail only a
  few pixels wide keeps a plain soft profile. Seen along its length it is a plain soft cone (no swelling or noise,
  which would stack into rings), and its first 10 m fade in.
- **Flame**: at the nozzle (MissileFlareDistance, 1 m, ahead of the trail head) a 3.2 m plume along the flight path,
  white-hot (HDR, so AgX turns it white) to orange at the tip, flickering; a round glow at least 12 px wide, strongest
  seen from behind; and an orange light (25 m, no shadows) on the first 4 flames. The flame replaces the missFLR
  sprite.
- **Burnout**: the smoke and flame stop when the motor burns out and the weapon coasts on clean; its flight is the
  original's either way. The burn is the real motor's, by weapon (`missile_fx.gd MOTOR_BURN`, table below); a
  weapon without a sourced figure uses its motion's burn (`time_left`, docs/weapons.md §5.3). Rockets (560) burn
  1.07 s, the Hydra 70's Mk 66 motor of the LAU-61 pod[^hydra].
- **Caps**: 24 ribbons (the oldest goes first), 640 points each (≈ 30 000 vertices in all), 8 flames.
- **No stutter**: both materials are drawn once behind the loading screen (`damage_effects.gd warm_up`), so the first
  missile compiles nothing.

Motor burn by weapon (boost + sustain). Where two figures or a range are given, the value used is their sum or middle
(inferred).

| Weapon (bdb name) | Burn used | Source |
|---|---|---|
| R-60 (AA-8) | 4 s | "3–5 s" of motor time[^r60] |
| S-75 (SA2) | 26.5 s | booster about 4–5 s, main engine about 22 s[^s75fx] |
| S-125 (SA3) | 23 s | booster 2–4 s, sustainer up to 20 s[^s125] |
| 9K33 Osa (SA8) | 17 s | booster 2 s, sustainer 15 s[^osa] |
| Hydra 70 rockets (560) | 1.07 s | Mk 66 motor[^hydra] |

Open: no citable burn time was found for the AIM-9D / L / M, Python 3 / 4, Shafrir 2, AA-2, AA-6, AA-11, AIM-7B / F / M,
AMRAAM, HARM, Shrike and Maverick (only game wikis, forums or simulators give figures). These burn their motion's
burn, which is longer than the real motor's (AIM-9L 16 s, docs/weapons.md §1.2; AMRAAM 35 s, §11.2).

**Contrails** (new content): an aircraft above 9000 m (the Schmidt–Appleman limit of an atmosphere 10 °C warmer than
the standard one) leaves white condensation from each engine nozzle: a particle every 3 m, 1.2 m growing to 9 m,
lasting 6 s (`gpu_fx.gd contrail`, called for the player in `terrain_view.gd` and for AI jets in `ai_flights.gd`).

**Heat haze**: each afterburner nozzle gets a refracting cone (`afterburner.gd haze`): radius r at the nozzle growing to
2.2 r, 8 r long behind it, in the model's own frame, so it starts at the nozzle and moves with the jet. The shader
shifts the screen copy by scrolling noise, strongest across the middle of the cone and fading along it. Strength:
the engine level / 100, × 1.6 in afterburner; hidden below level 31. It draws before the flame, so the flame glows on
top. The screen copy holds the opaque scene, so the haze blends in only as far as the shimmer needs.

**Condensation** (new content, `vapour_fx.gd`, fed by `gpu_fx.gd contrail` with each jet's flight state): water vapour
condenses where the air around a jet cools below its dew point[^wtv][^vcone]. Three effects, on every jet within 3 km
of the camera (the player's and AI jets). With Detailed they replace the original wingtip ribbons (`terrain_view.gd`,
`ai_flights.gd`); Original keeps the ribbons and has none of these.

- **Wingtip streamers**: vortex cores condense most at high angle of attack, as in a fighter's high-G
  turn[^wtv]. Each tip leaves a thin camera-facing ribbon of points in the air behind the jet. A point lives 0.55 s
  (≈ 110 m at 200 m/s), widens from 0.22 m to 1.1 m and fades as (1 − age)^1.6. The ribbon is solid for its first ≈ 0.1 s
  and then breaks up into noise. It fades in over the first 0.5 m behind the tip (per pixel: one frame's segment is
  several metres long), so it has no cut end. Each point
  drifts at 2.5 m/s in a spiral around the trail (the two tips turning opposite ways) and sinks at 0.6 m/s with the
  downwash, so the wisp twists and wavers (inferred). The tips are the model's outermost vertices (the night lights'
  wingtip spots, `night_lights.gd`): on the F-16 the aft fin of the wingtip missile, the tip's trailing edge.
  Strength follows the physics under one fixed humidity. The lift per span is ρ·V·Γ[^kj], so the tip vortex's
  circulation Γ grows with the lift; the core's pressure (and so temperature) drop grows with Γ², which for a given wing
  is ∝ n·CL·(W/S) (inferred). CL = n·(W/S) / q from the load factor n and the dynamic pressure q (ISA density at the
  jet's altitude), capped at 1.8, with one wing loading W/S = 3 500 Pa for every jet (the F-16's: 9 207 kg on
  27.87 m²[^f16] is 3 240 Pa, more with stores). The streamers start at n·CL = 2 and are full at 5 (inferred): from
  ≈ 2.2 G (full 3.5 G) at 120 m/s, from ≈ 3.7 G (full 5.8 G) at 200 m/s, hardly at all at 250 m/s below 5 G. So a hard
  pull at low speed (where the original draws its wingtip ribbons, 75–150 m/s) condenses as much as a harder one fast.
  They fade out within ≈ 0.12 s once the pull ends.
- **LEX plume** (F-16, F-35I, MiG-29): the leading-edge extension vortices[^wtv] as a translucent plume hugging the
  upper surface. It is two flattened half tubes from the LEX (a per-plane spot, inferred from drawings) back over the
  wing roots to 0.95 of the length, spreading out to 0.55 of the half span. They widen from 3 % to 18 % of their run (most of it behind the wing root, where
  the vortex bursts) and carry noise that flows aft and breaks into wisps over the wing. Seen along the tubes (from
  the cockpit looking back) they keep their full strength: the eye looks down the length of the cloud, and its noise is stretched along the flow (streaks rather than puffs).
  Strength: from 10° AoA (full at 20°).
- **Vapour bell**: a flickering shell around the fuselage from the canopy (0.28 of the length) to the wings' trailing
  edge (0.7), flaring out to 0.9 of the half span. Its front is soft and its aft edge ragged and soft: the cloud ends
  at the shock, where pressure and temperature rise again[^vcone]. Seen along the jet's axis (from behind or ahead)
  it fades out, so it never shows as a ring or disc. Near Mach 1 low down (from Mach 0.86, full 0.95–1.03, gone by
  1.2; below 300 m full, gone by 2500 m) it is the vapour cone: it forms in transonic flight, not exactly at
  Mach 1[^vcone]. Under high G at speed (5 G, full at 8 G; from Mach 0.55, full at 0.8) it flattens onto the wings'
  upper side (wing vapour).

All three need humid air: they fade out between 1500 and 6000 m (inferred: the air near the ground carries the most
water). Each strength eases in over ≈ 0.15 s. They draw unshaded white: the sun's colour × its energy (to 1.5) plus
0.25 sky light, up to 1.6, so the tone mapping keeps sunlit vapour white (dim at dusk and night). They fade out
within 0.5–4 m of the eye: no hard edge at the near plane.

**From the cockpit**: the cockpit views draw the cockpit model (`*_bc`, terrain_view.gd `own_bc`), not the jet
model; it is larger than the jet model (the F-16's wingtips 10 m from the axis against 7 m) and placed by the eye.
So the player's condensation in the cockpit views leaves the cockpit model's own wingtips and LEX
(`terrain_view.gd vapour_state` hands vapour_fx.gd that frame). The cockpit model is cut at the eye: its nose and
length come from where the eye sits along the jet model (descriptor `eye`). The eye is inside the vapour bell there,
so the bell shows all round, with no axis fade; its silhouette fades over a wider angle and its noise is coarser and
denser, so the close fog has no hard glassy arc and no dark speckles. Looking straight back in a hard level turn (banked acos(1/n), the
horizon tilted), both streamers run from the wingtip missiles' aft fins up towards the inside of the turn, where the
jet's flight path lies behind it, and the LEX vapour pours back beside the spine behind the seat; the Mach 0.95 pass wraps the canopy in mist from the canopy back. The original's snap views cannot look down
(pitch ≥ 0.1 · (|yaw| − 90°)), so looking left or right (90°) the wing and its streamer are below the view; back-left
and back-right (135°) look along the wing to its tip. On the F-35I the cockpit model's wide aft fuselage (ours,
`tools/f35i/bc.py`) is higher than the eye's line to the trails: it hides the LEX plume and all but the streamers' far ends in
every snap view.

Tried and dropped from the cockpit (2026-10-26):
- Wings-level pull-ups as the cockpit test flight: the horizon stayed level, and the trails lay below the wings, out
  of the back view. The shots fly the banked level turn instead.
- A fade-in along the streamer's first 0.8 m carried per vertex: at 30 fps a frame's segment is ≈ 7 m long at
  200 m/s, so the streamer started a wing's width behind the tip. The fade is per pixel now.
- The streamer solid for 40 % of its life with a flatter edge profile: from the cockpit it read as a white rod laid
  over the ground.
- The LEX plume's noise 5× finer across and 3× coarser along from inside: a regular feather fan. The plain noise
  read as a cauliflower puff; 1.5× across and 0.6× along is between.
- The left / right snap views (90°): they cannot look down, so in the banked turn they show only sky or ground.

Cost (not measured yet):
- CPU: one `ImmediateMesh` rebuilt in GDScript each frame, ≈ 130 triangles per jet in a hard turn at 60 fps
  (2 tips × 33 points × 2).
- GPU: per jet a bell (363 vertices) and a plume (198 vertices), alpha-blended. The overdraw of a bell filling the
  screen in a close chase view is the main cost.
- Shader compiling: all three materials are in the scene from its start (a degenerate triangle, an invisible bell and
  plume), so their pipelines compile behind the loading screen.
- To bench: `tests/godot/_fx_bench.gd`'s on / off switching, with the jet held in a 7 G turn or a Mach 0.95 pass and
  the camera close behind it.

Shots: `tests/godot/_vapour_shot.gd` (F-16 Original and Detailed, F-35I: the turn from behind and from above, the low
pass from behind and from the side, wing vapour; from the cockpit straight back and back-left / -right in a level
turn banked acos(1/n) at 7 G and 200 m/s and at 4.5 G and 120 m/s (the original's ribbon regime, so the pairs show
both rules), and in the Mach 0.95 pass; `VAPOUR_FLIGHTS` / `VAPOUR_LOOKS` pick some of them; `VAPOUR_BEFORE=1` takes the same shots
with Original).

**Cost** (M4 Pro). Mpx = million pixels; overdraw = the same pixel shaded again by each overlapping particle.

| Measure | Original | Detailed |
|---|---|---|
| CPU, the puffs per frame (`test_particle_effects.gd`, every explosion kind at once, ≈ 1 900 live puffs) | 0.67 ms | 0.08 ms |
| GPU, mission 231: the effects' drawing on − off (`tests/godot/_fx_bench.gd`: every 2 s a vehicle and an aircraft explode and a missile hits, two missile trails, three smoking units; switched every 120 frames in one window, median of 9 pairs; 3840 × 2160 at render scale 1.6 = 22 Mpx) | +0.30 ms | +3.38 ms (quartiles +3.07 / +3.65) |
| The same in mission 221 | −0.04 ms | +2.84 ms (quartiles +2.42 / +3.12) |

That is ≈ 0.13–0.15 ms per Mpx under this heavy burst: ≈ 0.3 ms at 1920 × 1080 and ≈ 1.2 ms at 3840 × 2160. The
smoke's overdraw sets the cost; the trail spacing (1.5 m) and widths are the knobs. These measurements predate the
missile smoke ribbons (not measured yet).

The missile smoke's cost (inferred, not measured): CPU, one `ArrayMesh` rebuild per burning missile per frame (up to
640 points); GPU, the ribbons' alpha-blended overdraw, which is far smaller than the old puffs' (one layer, a few
metres wide), and up to 4 small omni lights. To measure it: `tests/godot/_fx_bench.gd` (its two missile trails) on
the Iris Xe at 2560 × 1440, Particle effects Original against Detailed.

**Shots** (local, `assets/converted/research/fx/`, `tests/godot/_fx_shot.gd`, Original then Detailed side by side in
`cmp_*.png`): `bomb_*` (a bomb's hit), `vehicle_*` (a ground vehicle destroyed), `hit_*` (a missile's hit), `air_*`
(an aircraft destroyed in the air), `trail_2.5` (a missile trail), `haze` (the engines in afterburner, close up, seen
from behind through the haze). The missile smoke and flame: `tests/godot/_missile_fx_shot.gd` (a launch from
beside, from behind, mid-flight, and the trail 4 s after the hit; any time of day; before / after).

## 7. Airbases, Detailed (built: game/terrain/airbases.gd, terrain.gdshader)

Preferences → Graphics → MORE → **Airbases = Detailed** (ours, docs/deviations.md §2) draws the nearest base's runways,
taxiways and aprons as a procedural surface with ICAO markings when the camera is near the ground. Original shows the
1998 imagery's painted runways. Rendering only: the flight model's runway surface stays terraintype.dat's.

**World scale Real**: the surface is always on, each base drawn at its real site from the moved runways and the
turned mask ([world-scale.md](world-scale.md) §4.2, §4.3).

**The data** (`iaf-terrain airbases <install> <theatre> <out>`, run by `tools/setup-cli.sh`; `crates/iaf-tools/src/airbases.rs`).
For each of iaf.ibx's ten bases, from the 1998 art at level 1 (2.5 m per pixel) around the base's terraintype.dat
runway cells:

1. **The runway through the lineup point.** iaf.ibx's lineup point and RunwayNumber give a line. The runway's colour
   is sampled along it (150–1200 m), and the asphalt pixels are the grey ones and those of that colour.
2. **The other runways.** The search drops asphalt strips narrower than ≈ 28 m (taxiways), then takes the longest
   straight run of asphalt per heading (0.5° steps; gaps up to 140 m bridged, so a crossing runway does not cut it).
   It repeats until no run reaches 1800 m.
3. **Measuring a runway.** The centreline runs through the middles between the edges at 20 % and 80 % of the run
   (twice). The edges lie where the art gets more than 25 levels brighter than the runway's middle (the shoulders and
   infield) or stops being asphalt. The ends lie where asphalt stops along the centreline, plus at most 120 m of grey
   concrete (the ends where the art paints the numbers). A runway is 35–120 m wide and at least 1800 m long.
4. **Thresholds.** The lineup point is its runway's threshold. Other ends: the art's threshold stripes (a third to
   nine tenths of the points across the runway bright, over ≥ 12 m) within 900 m of the end, else the end itself.
5. **Designation numbers**: the runway's own heading over ten, 01–36 (docs/deviations.md: the art's template numbers
   are covered).
6. **The paved surface** (a mask, 2.5 m pixels). A pixel counts as paved when its colour is one of these:
   - pavement grey (little colour, not brown, not dark), anywhere;
   - the aprons' blue / purple tint, anywhere;
   - the runway's own colour, within 100 m of the runway leaves;
   - a taxiway's own colour. Taxiways are often lighter or warmer than the runway, and differ from each other and from
     the aprons, so each segment of iaf.ibx's taxi paths samples its own colour (the median of its grey samples off
     the runways). That colour counts within 30 m of the segment, and within 600 m of the runway leaves for pixels that
     are not dark: taxiways no taxi path follows, such as Ramon's parallel taxiways, have the same paving.

   Roads (narrower than 12 m) are dropped, and only pixels reached from the runways within 1.5 km stay. The edge is
   then closed over 5 m (gaps and notches filled). Within 40 m of the runways' sides it is also opened over 7.5 m: the
   shoulders' worn grey made a wavy fringe there, and the opening drops it but keeps the wider taxiway junctions.
   The art's colours make the edge wobble by 5–10 m, so the outline is then straightened: traced along the pixels,
   each point averaged with its neighbours within 12.5 m along the outline, simplified to straight edges
   (Douglas-Peucker, 5 m), and drawn back with anti-aliased edges. Outline parts under 100 m² (specks, small holes)
   are dropped. The file stores the paved coverage, so the edge lies where the value is 0.5.

   Concrete (the aprons' tint) is a second channel, set per apron instead of per pixel: the surface off the runways is
   eroded over 12.5 m (the taxiways drop out), and each remaining part is concrete when most of its pixels show the
   aprons' tint. The concrete parts then grow back over the surface off the runways. The file stores concrete as
   coverage blurred over ≈ 5 m (edge at 0.5).
7. **Taxi lines**: iaf.ibx's taxi paths (runway → hangars, hangars → runway, each hangar's turn point → hangar), the
   paths the AI taxis, as a distance field in the mask's third channel (0–10 m, 4 cm steps).
8. **No runway in the art** (bases only in the coarse imagery): the AI's runway, 3000 × 45 m from 150 m behind the
   lineup point.

Result (`assets/converted/terrain/airbases.json` and `airbases/<base>.png`):

| base | runways (heading, length × width) | threshold from the ends |
|---|---|---|
| Ramon | 229.7° 3516 × 78 m, 050.0° 3374 × 78 m | 124 / 0, 0 / 0 m |
| Tel Nof | 090.2° 4446 × 92 m, 150.0° 3918 × 92 m | 370 / 98, 86 / 66 m |
| Ramat David | 270.4° 4264 × 97 m, 150.0° 4122 × 97 m, 029.9° 3264 × 96 m | 672 / 0, 150 / 284, 394 / 396 m |
| Refidim | 270.0° 3950 × 77 m | 772 / 0 m |
| Damascus | 059.7° 3946 × 75 m | 0 / 125 m |
| Kuzeir | 279.8° 3702 × 84 m, 100.0° 3538 × 75 m | 154 / 10, 0 / 0 m |
| Bley | 234.8° 4058 × 95 m, 055.0° 3860 × 96 m | 370 / 0, 352 / 356 m |
| Inshas, Ryak, Aman | the AI's runway (no runway found in the coarse art) | 150 m |

At Ramat David and Ramon the headings match the original's painted runway digits within 0.5°, and each runway reaches
past its digits (test `runways_of_the_real_bases`). At Ramat David the original light set `lt_dvd_h` (§5) stands at the
runway edges: the edge lights lie a median 2.3 m outside the derived edges (quartiles +0.2 / +6.3 m;
`test_airbases.gd`).

**The drawing** (`terrain.gdshader`, the globals `terrain_airbases`, `airbase_mask`, `airbase_mask_rect`, `airbase_data`,
`airbase_info`). `airbases.gd` picks the base whose runways' middle is nearest the camera (within 15 km) and hands the
shader its mask and a small float texture: per runway its centre, direction, half length and width, numbers and
thresholds. In the terrain's fragment, inside the mask's rectangle and within 6 km
(faded from 2.5 km):

- **Edge**: the mask is read with bilinear filtering, and the pavement starts where the paved coverage crosses 0.5,
  over one screen pixel (from `fwidth`). So the edge is smooth instead of following the mask's 2.5 m pixels; far
  away the mipmaps soften it.
- **Surface**: the imagery blurred to ≈ 16 m gives the tone (so it fades into the imagery far away), pulled 60 %
  toward real asphalt's brightness (albedo 0.1) so the paint stands out on light and dark art alike. Variation:
  patches (≈ 40 m), grain (≈ 2 m), 7.5 m paving lanes with dark seams, repaired patches (1 in 8 of 40 × 7.5 m cells).
  Aprons: 5 m concrete slabs along the base's first runway, each its own shade, dark joints. Roughness 0.88 (paint
  0.7), a faint aggregate relief within 300 m. The terrain close up's relief is the ground's, so the pavement drops it.
- **Markings** (ICAO Annex 14 sizes for a 60 m runway, scaled by the width, at most × 1.6): threshold stripes (8 each
  side, 1.8 m, 30 m long, 6 m past the threshold), the designation (two digits 9 m tall, 12 m past the stripes),
  centreline (30 m dashes, 20 m gaps), touchdown zone marks every 150 m (3, 3, 2, 2, 1, 1 bars), the aiming point
  (45 × 8 m at 400 m, on runways over 2400 m), edge lines. Before a threshold: yellow chevrons 30 m apart. Taxi lines:
  yellow, 0.3 m, within 2 km. World scale Real adds the runway letters, wider taxi lines and the real runway width
  (world-scale.md §4.3).
- **Tyre rubber**: dark streaks in the main gears' tracks (1–6 m off the centreline) from ≈ 150 to 1100 m past each
  threshold.
- Every mark is box-filtered over the pixel's footprint along and across the runway, so it fades to its average far
  away instead of shimmering.

**Cost** (M4 Pro, `tests/godot/_airbase_shot.gd` with SHOT_BENCH: `terrain_airbases` switched every 120 frames in one
window, median of 12 pairs; 1920 × 1080 at render scale 2.0 = 8.3 Mpx, Terrain close up on):

| View at Ramat David | on − off |
|---|---|
| Cockpit on the runway, take-off | +0.38 ms |
| External low pass at 40 m | +1.49 ms |
| 30 m over the threshold, looking down the runway (the most marking on screen) | +1.87 ms |

That is at most ≈ 0.22 ms per Mpx: ≈ 0.45 ms at 1920 × 1080. From 1500 m and above the base the cost is below the
noise (the surface fades out by 6 km and only the mask's rectangle runs the code).

**Shots** (local, `assets/converted/research/airbases/b_detailed/`, Original | Detailed side by side in `cmp_*.png`):
Ramat David, Tel Nof, Ramon and Damascus; take-off, roll (800 m), 300 m on final, 1500 m overhead, an external low pass;
noon and 22:00 (with Night lights = Detailed: the base's light set lines up with the runway edges).

## 8. Night vision (built: game/terrain/night_vision.gdshader)

Preferences → Graphics → MORE → **Night vision = Goggles** (ours, docs/deviations.md §2). In flight, **Shift+N** puts
the goggles on and takes them off (`terrain_view.gd _toggle_goggles`). The original has no night vision.

The goggles are a full-screen shader on canvas layer −1: over the 3D view and the cloud layer, under the cockpit,
HUD and MFDs. The pilot sees the outside through the goggles and the panel below them, so the panel keeps its own
night lighting. The tube depends on the mission's year (§8.1). The shader:

1. **Spectrum.** The image is one brightness, weighted by the tube's photocathode. A Gen III tube sees 500–900 nm,
   from blue-green into the near infrared[^nvd]: (0.6, 0.4, 0) for R, G, B, no blue. A Gen II tube sees more of the
   visible light: (0.45, 0.4, 0.15). The weights are inferred. Without blue the navy night sky stays a mid tone and
   the ground shows.
2. **Automatic gain control.** The shader works on the square root of the brightness, so the moonlit ground keeps
   its detail beside the brighter sky (inferred). The gain is set so the screen's mean (the screen texture's last
   mip) reaches 0.55, from ×1 up to the tube's top gain. A real tube raises its gain as the light falls[^rash].
   By day the gain stays at ×1, and the bright-source protection darkens the picture (§8.3).
3. **Sharpness.** The image is read from a blurred screen mip: none for the late Gen III, 0.7 for the early Gen III,
   1.2 for the Gen II. These follow the tubes' resolution against the late Gen III's 64 lp/mm: 36–51 lp/mm
   (×1.6 blur) and 28 lp/mm (×2.3)[^omni][^gen2].
4. **Halos.** Where a light is much brighter than the scene, mips 2–5 brighter than 0.9 after the gain add a disc
   around it, scaled by the tube's halo strength. Gen III tubes, with their ion-barrier film, show larger halos than
   Gen II ones[^nvd], and the halo shrank over the 1990s contracts (1.47 mm → 0.70 mm on the tube)[^omni].
5. **Grain.** Noise per pixel, new every frame, grows with the square root of the gain: the darker the scene, the
   more sparkle[^rash]. Its strength follows the tube's signal-to-noise ratio (§8.1): about 4:1 for a Gen II, 16 to
   21 for a Gen III[^gen2][^omni].
6. **Phosphor.** The brightness saturates softly (1 − e^(−1.6 l)), tinted P43 green (0.42, 1.0, 0.36). Night-vision
   images are green because green is easiest to watch in the dark for long[^nvd]; the US military made P43 its
   standard[^phosphor]. The edge of the view darkens (by up to 70 %), as the goggles' 40° round view[^rash].
7. **The HUD.** The HUD's light is far stronger than the night outside, so with the goggles on the HUD draws in the
   brightest of the H key's greens (index 7, 0x00fc00); the player's level comes back when the goggles come off
   (inferred).

The goggles show in every view, also the external ones. No sensor or AI reads them (gameplay unchanged).

### 8.1 The tube by year and jet

The year is the mission's (`Settings.mission_year()`): an edited mission's own (mission-editor.md §12), else the
original's by its id (`mission_year.rs default_year`: 111–117 1967, 121–127 1973, 131–137 1982, the rest 1998).

| Year / jet | Tube | Grain | Blur (mip) | Halo | Top gain |
|---|---|---|---|---|---|
| before 1972 | none: Shift+N shows "no night-vision goggles in <year>" | — | — | — | — |
| 1972–1981, and the MiG-23 / MiG-29 from 1972 | Gen II (AN/PVS-5, US Army from 1972[^pvs5]) | 0.29 | 1.2 | 0.25 | ×5 |
| 1982–1995 | early Gen III (ANVIS-6, Omnibus I–III, 1982–1990[^omni]) | 0.07 | 0.7 | 0.6 | ×8 |
| 1996 on, and the F-35I in any year | late Gen III (ANVIS-9, Omnibus IV, 1996[^omni]) | 0.047 | 0 | 0.4 | ×8 |

- Grain: the noise's strength at ×2 gain, from the tube's signal-to-noise ratio (inferred: σ ≈ 1 / SNR, scaled so the
  early Gen III's 16 gives 0.07). Top gain: the Gen II's lower, as its system gain was about 800 against about 2,000
  for ANVIS[^gain] (×8 × √(800 / 2000) ≈ ×5, inferred).
- The table gives the best tube that existed in the year. When IAF fighter pilots began to fly with goggles is open
  (§8.2), so the year picks the tube, not whether the squadron had one.
- The MiGs: the Soviet standard aviation goggle was the ONV-1[^onv1]; a forum post calls it a Gen II, with trials on
  the MiG-29 in the late 1980s and operational use only in the 1990s[^dcs]. No source shows MiG-23 goggles. Here the
  MiGs get a Gen II at most (inferred).
- The F-35I: the F-35 has no goggles. Its helmet shows a night camera's picture (ISIE-10, then ISIE-11, whose
  acuity comes close to the 20/20 of goggles), and the alternative goggle helmet was dropped in 2013[^f35][^f35alt].
  Here it is drawn as the late Gen III (inferred); its camera's own look (latency, colour) is open.
- Not modelled: the P20 phosphor's long afterglow (55 ms) on the Gen II and early Gen III tubes[^phosphor], and the
  autogating of late-1990s tubes[^autogate].

### 8.2 Goggles in the IAF (research, open)

- **Helicopters first.** The IAF's goggle, the "Zhurnal", sits in front of the helmet's visor with its battery on the
  helmet's back; it has served in the helicopter squadrons since the early 1980s[^zhurnal]. Its model and maker are
  open.
- **Fighters.** No source dates the first IAF fighter flights with goggles or names their goggle. The first IAF jet
  with a sourced goggle-compatible cockpit is the F-15I (delivered from 1998)[^f15i]. For comparison, the USAF began
  making its Block 40 F-16s goggle-compatible in 1996[^f16nvg]. Open: the Netz / Barak, Kurnass 2000 and Kfir.
- **Night attack in 1982** used laser-guided bombs; no source mentions goggles[^bekaa].

### 8.3 Cockpit glare and bright light

- **Cockpit lighting.** One cockpit light that does not suit goggles is enough to degrade the picture[^dtic]. Where
  the jet's lighting does not suit them (`terrain_view.gd goggles_lit`), the shader's `glare` (0.15) adds to the
  mean, which lowers the gain, and veils the picture toward the panel below (from 30 % of the height down). Suited:
  the F-15 and F-16 from 1996 (inferred from the USAF's F-16 retrofit[^f16nvg] and the F-15I[^f15i]) and the F-35I
  (its helmet camera). Every other jet and year glares. The original itself lights the F-4E's night cockpit red, the
  colour a Gen III tube sees best.
- **Bright-source protection.** When the view's mean (linear, through the tube's weights) passes 0.35, the picture
  darkens, down to 10 % at 0.6: a close blast filling the view, or daylight. The picture comes back as soon as the
  light goes (no hold time). Gray Zone Warfare shuts its goggles down the same way[^gzw]; the limits are inferred.

**Shots**: `tests/godot/_night_shot.gd` with `NIGHT_VISION=1`; the pilot guides' `night` / `night_nvg` pictures
(their "Night vision" section). In mission 214 (01:00, Detailed night lights) the goggles show the hills, the
ground's texture and the AI jet ahead, which are black without them. Cost: 68.5 against 71.4 fps at 1920×1080 on this
Iris Xe laptop, measured while another render ran (to measure again on an idle machine).

## 9. Model detail (built: game/util/model_detail.gd, model_detail.gdshaderinc)

Preferences → Graphics → MORE → **Model detail = ambientCG** (ours, docs/deviations.md §2) gives the original models
a fine surface up close: the stores read as painted metal, the jets as worn paint, the vehicles as weathered steel,
the buildings as cast concrete and the tyres as rubber. Each model keeps its own texture, colours and markings; the
detail only adds a normal map, a roughness map and a brightness variation (chips, scratches, stains) on top. Original draws the models as
the 1998 textures alone.

**The materials** are four CC0 PBR materials from ambientCG[^ambientcg], pinned with their zips' SHA-256 in
`crates/iaf-tools/src/thirdparty.rs` (`MODEL_DETAIL`, the list `model`):

| class | ambientCG material | used for |
|---|---|---|
| painted | PaintedMetal002[^acg-pm002] | stores, jets |
| worn | Metal016[^acg-m016] | ground vehicles, ships, the hangar shell, metal structures |
| concrete | Concrete029[^acg-c029] | shelters, bunkers, buildings |
| rubber | Rubber004[^acg-r004] | tyres |

**Setup**: the same optional `textures` step as Ground textures (§1.4, docs/setup.md; CLI `iaf-textures`) fetches
them. Each material's `nr.bc3` (1024², DXT5 with every mip level) carries what Model detail reads: R roughness, G
normal Y, B the colour map's brightness about its mean (0.5 = the mean, ±2 σ spans 0..1), A normal X (OpenGL
normals). `model.json` lists them in the classes' order (`model_detail.gd MATERIALS`). Offline, the step is skipped,
the row stays greyed out ("Not downloaded", not clickable), a saved ambientCG loads as Original and the switch has no
effect. The uninstall keeps the downloads unless asked (docs/setup.md).

**Loading, without hitches**:

- The packs load off the main thread: the front end starts reading them while the mission's screens (TSD, briefing,
  Arming) are open, the flight scene again at its start for a flight started otherwise (`preload_packs`). Setup
  stored them compressed with their mips, so the game only reads and uploads them: 1.3 MiB per pack, 5.3 MiB of video
  memory for all four. The mean roughness comes from the 1×1 mip.
- One shader with uniforms (a variant per cull mode: two in all, as only a few original materials are two-sided). The
  tyres are a uniform, not a variant.
- Behind the loading screen, the flight scene draws every class once, too small to see, in front of each camera
  (`warm_up`), so the GPU pipelines are built before the first model shows.
- One material per original material and class, shared by every parse of the file (`Gltf.open` tags each material with
  its file and index), so ten jets of a type, and a store released from a pylon, use the materials already made.
  Placing a model creates no texture and, after the first of its type, no material.

**Which surfaces take which class** (from the original data; `model_class` and `detail_material`):

| original data | class |
|---|---|
| a model under `converted/objects/weapons` (bombs, missiles, drop tanks, pods) | painted, 0.8 m per repeat |
| `converted/planes`, `objects/controllableplanes`, `objects/noncontrollableplanes` (every original jet, helicopter, transport) | painted, 1.2 m per repeat |
| a jet's gear legs (meshes under the LdgL / LdgR / LdgF / LdGr frames; docs/part-animation.md) | painted, and rubber where the texel is dark (brightness below 0.16): the tyres |
| `objects/groundforces`, `objects/seaforces` | worn, 1.5 m per repeat |
| `objects/stationary` | concrete, 3 m per repeat |
| stationary `hgrsk1` (hangar shell), `cntnr` (containers), `antenas`, `ftank`, `hvtgpl`, `wtrtwr`, `radum` | worn. A corrugated-sheet material was tried on the hangar shell: mapped triplanar it crossed the corrugation its own texture paints and ribbed its brick wall |
| stationary `tent10`, `crater`; any `*_ul*` model (the airbases' flat surface pieces, the ground's) | none |
| a blended material (glass: canopies, cockpit windows, building windows; rotor and propeller discs; clouds) | none |
| the pilots (meshes under the pilot / pilotB frames) | none |
| an unshaded or glowing material, or any model at OBJECT DETAIL 1 (point-sampled textures) | none |
| our own models (the detailed F-16D and stores, the F-35I) | none: they carry their own maps |

**The shader** maps the pack triplanar in the model's frame, scaled to world metres by the model's own scale, so the
detail sticks to the model as it moves and keeps its real size at either World scale. The detail normal is blended
onto the model's normal (UDN blend); the roughness is the class's mean plus part of the pack's variation; the
brightness is multiplied by 1 ± the class's strength at ±2 σ of the material's own brightness, so the hue stays and the
mean brightness is unchanged.

| class | metres per repeat | normal strength | brightness | roughness mean |
|---|---|---|---|---|
| store | 0.8 | 1.6 | ±45 % | 0.42 |
| aircraft | 1.2 | 1.3 | ±35 % | 0.48 |
| vehicle | 1.5 | 1.6 | ±45 % | 0.62 |
| concrete | 3.0 | 1.5 | ±40 % | 0.9 |
| rubber (tyres) | 0.25 | 1.5 | ±60 % | 0.92 |

The first strengths (normal 0.55–1.0, brightness ±10–20 %, jets at 2 m per repeat) showed no difference at the
pylons or on the ramp; with these the chips and scratches of PaintedMetal002 read on the stores and the jets' skin from
a few metres, and the grime on the vehicles. The detail fades out between 40 and 120 m from the camera and is not sampled
beyond, so far models draw exactly as before and nothing shimmers. Code that reads a model's texture (the shatter
pieces, the re-lettered taxi signs) asks `ModelDetail.base_material` for the original material.

**Cost, with Ground textures** (Iris Xe, TigerLake GT2, 2560 × 1440, Linux, X11 with immediate present, vsync off, an
idle GPU; `tests/godot/_ground_tex_bench.gd` with `GT_PRELOAD=1`, mission 311 in the F-16, 2026-10-22; average fps,
two or three runs each, the first cold run left out):

| measurement | both Original | Model detail | Ground textures | both ambientCG |
|---|---|---|---|---|
| lineup on Ramat David's runway 27, cockpit, first 30 s | 59.3 fps | 59.3–60.0 fps | 54.7–55.0 fps | 54.9–55.7 fps (−7 %) |
| the same, external view of the jet and its stores, 15 s | 53.0–53.1 fps | 53.1 fps | 48.9–49.1 fps | 48.8–49.6 fps (−7 %) |
| 300 m above the Halutza sands, 35° down (`--at 307000 446000 520 0 -35 --freeze`) | 53.5–53.9 fps | 53.4–53.5 fps | 51.9–53.3 fps | 51.8–53.3 fps (−1 to −3 %) |
| worst frame, first 30 s on the runway | 61.8 ms | 60.8–61.3 ms | 61.2–62.8 ms | 60.8–61.8 ms |
| mission start (scene change to the first flying frame) | 43.7–45.3 s | 44.1–45.4 s | 47.5–48.8 s | 47.2–49.4 s |
| upload at the flight's start, after the preload | 0 | 0 | 5.7–6.7 ms | 4.4–6.5 ms |

Model detail costs nothing measurable in these views; its own busy view (four more jets, a tank column, a shelter, a
hangar; `_model_detail_shot.gd SHOT_BENCH=1`, measured before the strength change, which adds no samples) cost 1.6 %
(GPU +0.47 ms). The worst frame of the first 30 s is the same with either switch. The start takes ≈ 3 s longer with
Ground textures; where that time goes is open (the textures' upload is 6 ms).

Video memory added: 5.3 MiB (the packs). Far models cost nothing: past 120 m the shader samples no detail.

**Shots**: `_model_detail_shot.gd` saves each view twice, Original and ambientCG, from the same camera: the Kfir and
an F-4 on the ramp, the Kfir's pylons (Mk-82s, a drop tank), its wheels, a tank and truck column, a hardened shelter, a
hangar. On Linux, run it on X11 with `MESA_VK_WSI_PRESENT_MODE=immediate` (`DISPLAY=:0 … --display-driver x11`): a
Wayland window covered by other windows is drawn once a second.


## 10. Rain (built: game/terrain/weather.gd)

Preferences → Graphics → MORE → **Rain = Off / Light / Heavy** (ours, docs/deviations.md §2). The original has no
weather, so the default is Off, which makes no node and changes nothing. The choice is saved (`Settings.rain`,
settings.cfg); it takes effect at once, also from the in-flight Preferences.

A mission can carry a weather of its own: **Clear / Light rain / Heavy rain / Random**, set in the mission editor's
Mission tab (mission-editor.md §3) or in Mission Creator Better (front-end.md §19.4), stored as misc `weather`
(formats/mis.md). The level drawn (`Weather.level()`):

| Rain switch | mission without weather (every original) | mission with Clear | Light rain | Heavy rain |
|---|---|---|---|---|
| Off | dry | dry | dry | dry |
| Light | light | dry | light | heavy |
| Heavy | heavy | dry | light | heavy |

- **Off** never rains, whatever the mission says: it is the performance escape.
- **Light / Heavy** is the level for the missions without a weather of their own; a mission's own weather wins.
- **Random** picks Clear, Light or Heavy rain once per flight, when the mission's files are read
  (`MissionRuntime.mission_files` → `Settings.mission_weather`, into `Settings.flight_weather`); the flight's end
  clears it (`Settings.clear_runway_wind`), so the next flight picks again.
- The weather changes only what is drawn: the flight model, the AI's sight and the braking stay the same.

`terrain_view.gd apply_render_options()` calls `Weather.apply_env` and, while it rains, makes the `Weather` node; its
`update` runs each frame with the camera.

| part | Light | Heavy | how |
|---|---|---|---|
| Falling rain | 6,000 drops | 9,000 drops | `rain.gdshader`: one MultiMesh quad per drop, placed in the vertex shader (below) |
| Drops on the canopy | 35 % of the cells | 70 % of the cells | `canopy_drops.gdshader`, cockpit views only (below) |
| Visibility (fog density) | 0.0002: about 15 km | 0.0005: about 6 km | `apply_env`; the scene's own is 0.00003 (about 100 km) |
| Overcast (`fog_sky_affect`) | 0.6 | 0.9 | the fog covers that share of the sky, so the sky turns the fog's grey |
| Sun | 50 % | 25 % | the sun's energy, under the overcast |
| Wet ground (`rain_wet`) | 0.6 | 1.0 | the global shader parameter read by `terrain.gdshader` and `model_detail.gdshaderinc` |

Visibility is given as the distance where the fog leaves 5 % contrast, 3 / density (Godot's exponential fog). The
levels are our choice (inferred): light rain keeps the far hills, heavy rain hides the ground beyond a few km while the
HUD, radar and TSD work as before.

**The environment** changes in one function, `Weather.apply_env(env, sun)`, called after `RenderOptions.apply` and
after each change of the sky: the fog's density and its share of the sky; the distance haze from the fog's colour
instead of the sky's (`fog_aerial_perspective` 0, as the Atmospheric sky's blue haze looks wrong under an overcast);
the ambient light from the overcast's grey (`Weather.OVERCAST`, a colour source in place of the sky; the time of day
keeps its energy); the sun's energy; `rain_wet`; the wet ground's specular `rain_spec` (0.3 under the Original sky,
0.12 under the Atmospheric sky, whose reflections stay a clear sky's blue). Off puts the scene's own values back. The
fog colour of the time of day (§4) is greyed toward its own brightness (`Weather.fog_tint`), by the overcast's share,
and so is the Original sky's zenith colour, so its reflections are the overcast's grey. `atmosphere.gdshader` itself
is unchanged.

**Falling rain.** Each drop has a fixed seed spot in a 40 m cube. The cube wraps around a point 14 m ahead of the
camera, so a drop stays at its place in the world while the camera flies through it, and the drops never run out. The
drops fall at 7 m/s (about a 2 mm drop's terminal speed[^gunn]) plus the wind (Better physics `wind`). Each is drawn as
the streak it sweeps in 40 ms (what the eye blurs) at its speed seen from the camera, at most 1 m long: short and
falling on the ground, rushing out from the flight path's point across the view at 300+ kt, seen through the canopy in
the cockpit views. A streak is 6 mm wide (the drop's blur) and at least two pixels, fainter when it would be thinner;
drops closer than 4–8 m (the canopy, the nose) and near the cube's edge fade out, and a drop not drawn collapses to a
point so it costs no fill. The streaks take the fog's colour at half its brightness: lighter than the wet ground,
darker than the sky. With TAA or FSR 2 (§1.7) the fast streaks at speed are much fainter: the temporal
resolve averages them out (open). The seed spots come from an integer (PCG) hash of the drop's index. The CPU sets five uniforms a
frame.

**Drops on the canopy** (cockpit views: cockpit, HUD only, free look, padlock). A canvas layer under the cockpit
(layer −1, as the cloud layer's whiteout) draws them, so they show through the cockpit's window only and the HUD stays
on top. Each drop is a small lens: it shows the scene within three radii around it, upside down, with a darker rim
(most at its lower side) and a small highlight. Two sizes of drops in grid cells, one at most per cell, land, stay a
few seconds and dry. The airflow (the camera's speed through the air) drives them up the glass, each column of cells
at its own pace, from 12 m/s on; they stretch into thin streaks and dry fast as the speed grows (fully at 80 m/s), so
at 400 kt only short runs show. At rest they slide down slowly.

**Wet ground** (`terrain.gdshader wet_ground`, a block at the end of the fragment shader): water in the pores darkens
the ground (to 75 %, grey ground such as pavement and rock to 60 %[^lekner]); its film lowers the roughness (to 0.8,
grey ground 0.65) and sets the specular to `rain_spec`. On the Detailed airbases' flat pavement (§7) within 800 m, the
low spots of the detail noise hold puddles a few metres across: flat, roughness 0.3, darker than the pavement around
them (by up to 30 %), with a dim reflection of the grey sky. Without Detailed airbases the
shader does not know the pavement, so there are no puddles. Water surfaces stay as they are. Models with Model detail
(§9) get a wet film up close (darker by 15 %, roughness × 0.45).

**Sound**: none. The install holds no rain or airflow sample (`wind1`–`wind5` are radio messages, docs/sound.md §1).

**Humidity hook**: `Weather.humidity(alt_m)` gives the air's relative humidity for the condensation of `vapour_fx.gd`
(§6): without rain, that file's own assumption (humid below 1.5 km, dry above 6 km); in the rain, saturated up to 3 km
(inferred: the cloud base), dry above 6 km. `vapour_fx.gd` does not read it yet.

**Loading**: the node and its shaders are made in `apply_render_options`, behind the loading screen, and draw there
once, so the pipelines are built before the flight shows. The canopy layer reads the screen (a copy of the 3D view
each frame while it shows).

**Cost** (Iris Xe, TigerLake GT2, 2560 × 1440, Linux, X11 with immediate present, vsync off, the other settings at
their defaults; `_rain_shot.gd RAIN_BENCH=15`, mission 311 in the F-16, the flight model stopped and the jet moved;
2026-10-26; average frame time of two runs each):

| pose | Off | Light | Heavy |
|---|---|---|---|
| lineup on Ramat David's runway, cockpit | 8.0–8.5 ms (118–126 fps) | 8.9 ms (112 fps, −8 %) | 8.9 ms (112 fps, −8 %) |
| 300 m over the Halutza sands at 200 m/s, cockpit | 10.9 ms (92 fps) | 11.6 ms (87 fps, −6 %) | 11.7–11.8 ms (85 fps, −8 %) |
| the same, chase view | 6.9 ms (145 fps) | 6.9 ms | 6.9 ms |

The chase view stays at a 145 fps ceiling in all three (open: likely the display's 144 Hz), so it shows no cost. The
canopy drops take about 0.5 ms of the cockpit's cost (a copy of the screen and the drop shader), the same at both
levels; the rest is the streaks' fill. No new frame spikes: the worst frames are the same with and without rain.

**Tried and dropped** (2026-10-26):

- Streaks up to the full 25–40 ms of travel at speed (5–8 m) cost 4 ms at 200 m/s; the 1 m cap and the near cut
  (4–8 m) brought Heavy to 0.9 ms.
- 12,000 and 16,000 drops for Heavy: 11–14 % at speed with two-pixel streaks; 9,000 keeps it under 10 % and still
  reads as heavy rain.
- One-pixel streaks, lightened: they vanished against the grey overcast; two pixels at half the fog's brightness show
  against both the sky and the ground.
- A `sin()` hash of the drop's index: past a few thousand drops it put drops on the same spot, drawn as one long line
  from the top of the view to the horizon.
- Drops not drawn moved out of the view (a clip position past the corner) instead of collapsed: where one vertex
  stayed, a thin triangle reached to the corner.
- Wet ground reflecting the sky (specular 0.3, roughness 0.55) and mirror puddles (roughness 0.05–0.2): under the
  Atmospheric sky the runway turned deep blue with white puddles.

**Shots**: `tests/godot/_rain_shot.gd` saves, per level, the cockpit on the runway, the chase view and the runway
close from 2 m there, the cockpit and the chase view at 400 kt 150 m over the Halutza sands; `RAIN_BEST=1` with every
graphics option at its best. `RAIN_BENCH=secs` measures the frame rate instead.

[^wtp]: Godot docs, ProjectSettings `threading/worker_pool/low_priority_thread_ratio` (default 0.3):
    https://docs.godotengine.org/en/stable/classes/class_projectsettings.html#class-projectsettings-property-threading-worker-pool-low-priority-thread-ratio
[^nvd]: Wikipedia, "Night-vision device" (Gen III 500–900 nm, the ion barrier's halo effect, green images):
    https://en.wikipedia.org/wiki/Night-vision_device
[^rash]: C. E. Rash, "A 25-year retrospective on NVGs", Flight Safety Foundation AeroSafety World, Aug 2010 (40°
    circular view, gain control, sparkles at low light, halos): https://flightsafety.org/wp-content/uploads/2016/11/asw_aug10_p14-18.pdf
[^omni]: Night Vision International wiki, "Omnibus" (per-contract minimums, a rough guide: Omni I 1982 36 lp/mm,
    SNR 16.2, halo 1.47 mm, P20; Omni IV 1996 64 lp/mm, SNR 21, halo 1.25 mm, P43; Omni VII 0.70 mm):
    https://www.nv-intl.com/wiki/index.php/Omnibus
[^gen2]: US patent 6,288,839 (Gen II about 4:1 SNR and 28 lp/mm; Gen III about 16:1 and 36–40 lp/mm):
    https://patents.google.com/patent/US6288839B1/en
[^pvs5]: Night Vision International wiki, "AN/PVS-5" (adopted by the US Army in 1972, 40° view):
    https://nv-intl.com/index.php/AN/PVS-5
[^phosphor]: Night Vision International wiki, "Phosphor Screen" (P43 the US military standard; P20's 55 ms tail):
    https://nv-intl.com/index.php/Phosphor_Screen
[^gain]: an NVG training report seen as a search snippet only ("about 2,000 for ANVIS … 800 for AN/PVS-5"):
    https://fsu.i8.dgicloud.com/_flysystem/repo-bin/2022-02/bitstream_10703.pdf
[^autogate]: L3Harris, "Guide to Gen III image intensifier tube technology" (autogating from the 1990s):
    https://l3harris.com/sites/default/files/2025-01/l3harris-guide-gen-iii-image-intensifier-tube-technology-cs-ivs.pdf
[^onv1]: Janes, "Russian helicopters receive new NVG system" (ONV-1 Skosok the standard; GEO-ONV1 Gen 3+ after 2016):
    https://janes.com/osint-insights/defence-news/russian-helicopters-receive-new-nvg-system
[^dcs]: ED Forums (an enthusiast's post, not authoritative), "Night vision mode for cockpit and external view":
    https://forum.dcs.world/topic/369099-night-vision-mode-for-cockpit-and-external-view
[^f35]: AIN, "F-35 pilots will begin flying improved Gen 3 helmet", 21 Jan 2014 (ISIE-10 / ISIE-11, acuity, tested
    against ANVIS-9): https://backend.ainonline.com/aviation-news/2014-01-21/f-35-pilots-will-begin-flying-improved-gen-3-helmet
[^f35alt]: Military.com, "Pentagon scraps alternative F-35 helmet", 10 Oct 2013:
    https://www.military.com/defensetech/2013/10/10/pentagon-scraps-alternative-f-35-helmet?amp
[^zhurnal]: IAF magazine (בטאון חיל האוויר) 125, 1 Feb 1999, the Zhurnal in the helicopter squadrons since the early
    1980s: https://www.iaf.org.il/244-18482-he/IAF.aspx
[^f15i]: GlobalSecurity, "F-15I Ra'am" (night-vision-goggle compatible cockpits; seen as a search snippet):
    https://www.globalsecurity.org/military/world/israel/f-15i.htm
[^f16nvg]: Flight International, 24 Jan 1996, "NVG modifications begin on F-16s":
    https://flightglobal.com/nvg-modifications-begin-on-f-16s/11115.article
[^bekaa]: Air & Space Forces Magazine, the Bekaa Valley 1982 (seen as a search summary):
    https://www.airandspaceforces.com/article/0602bekaa/
[^dtic]: DTIC ADA517298 (one incompatible cockpit light degrades the goggles' picture):
    https://apps.dtic.mil/sti/pdfs/ADA517298.pdf
[^gzw]: Gray Zone Warfare devlog 7 (grain in dark areas, halos, auto-shutdown in bright light):
    https://www.grayzonewarfare.com/news/devlog-7-daylight-to-darkness
[^ambientcg]: ambientCG, https://ambientcg.com/. Licence: "All ambientCG assets are provided under the Creative Commons CC0 1.0 Universal License", https://docs.ambientcg.com/license/ (read 2026-10-22).
[^acg-pm002]: ambientCG, Painted Metal 002, https://ambientcg.com/a/PaintedMetal002
[^acg-m016]: ambientCG, Metal 016, https://ambientcg.com/a/Metal016
[^acg-c029]: ambientCG, Concrete 029, https://ambientcg.com/a/Concrete029
[^acg-r004]: ambientCG, Rubber 004, https://ambientcg.com/a/Rubber004
[^wtv]: Wikipedia, "Wingtip vortices" (the cores condense when they cool below the dew point; most common at high angles
    of attack, e.g. fighters in high-G manoeuvres; the F/A-18's leading-edge extension vortices):
    https://en.wikipedia.org/wiki/Wingtip_vortices
[^kj]: Wikipedia, "Kutta–Joukowski theorem" (lift per unit span L′ = ρ∞·V∞·Γ):
    https://en.wikipedia.org/wiki/Kutta%E2%80%93Joukowski_theorem
[^f16]: Wikipedia, "General Dynamics F-16 Fighting Falcon", specifications (wing area 300 sq ft (27.87 m²), gross
    weight 20 300 lb (9 207 kg)): https://en.wikipedia.org/wiki/General_Dynamics_F-16_Fighting_Falcon
[^vcone]: Wikipedia, "Vapor cone" (transonic flight, not necessarily at Mach 1; the cloud ends at the stern shock):
    https://en.wikipedia.org/wiki/Vapor_cone
[^hydra]: General Dynamics OTS, "Hydra-70 Rocket System" data sheet (Mk 66 motor, time of burning 1.07 s at 77 °F), https://www.gd-ots.com/wp-content/uploads/2021/02/HYDRA-70_202010.pdf
[^r60]: Wikipedia (Russian), "Р-60" ("Время работы двигателя — 3-5 секунд"), https://ru.wikipedia.org/wiki/Р-60
[^s75fx]: Wikipedia, "S-75 Dvina" ("The booster fires for about 4–5 seconds and the main engine for about 22 seconds"), https://en.wikipedia.org/wiki/S-75_Dvina
[^s125]: Military Russia (rbase), "ЗРК С-125" (starting booster 2–4 s, sustainer up to 20 s), http://rbase.new-factoria.ru/missile/wobb/c125/c125.shtml
[^osa]: Wikipedia, "9K33 Osa" (booster 2 s, sustainer 15 s), https://en.wikipedia.org/wiki/9K33_Osa
[^hillaire]: Sébastien Hillaire, "A Scalable and Production Ready Sky and Atmosphere Rendering Technique", Computer Graphics Forum 39 (4), EGSR 2020, https://sebh.github.io/publications/egsr2020.pdf
[^gunn]: R. Gunn, G. D. Kinzer, "The terminal velocity of fall for water droplets in stagnant air", Journal of
    Meteorology 6 (4), 1949, pp. 243–248 (a 2 mm drop falls at about 6.5 m/s):
    https://doi.org/10.1175/1520-0469(1949)006%3C0243:TTVOFF%3E2.0.CO;2
[^lekner]: J. Lekner, M. C. Dorf, "Why some things are darker when wet", Applied Optics 27 (7), 1988, pp. 1278–1280:
    https://doi.org/10.1364/AO.27.001278
