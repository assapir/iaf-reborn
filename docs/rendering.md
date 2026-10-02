# Rendering options

The game logic is the original's; the rendering may be better, but the original look is the default and every
improvement is opt-in (Preferences → Graphics for the original's own switches, Preferences → Extras for ours).
Code: `game/terrain/render_options.gd` (applied by `terrain_view.gd apply_render_options()` at the start of a flight
and when the in-flight Preferences close), `terrain/terrain.gdshader`, `terrain/atmosphere.gdshader`,
`terrain/cloud_layer.gd`. Tests: `tests/godot/test_graphics_prefs.gd` (switches → render settings, save / load),
`test_ui_smoke.gd` (Extras rows in EN / HE).

## 1. Options

| Extras row | choices (first = default) | what it sets |
|---|---|---|
| Anti-aliasing | MSAA 4x / + FXAA / TAA | viewport `msaa_3d` 4× (the project's setting since the start); + FXAA: also `screen_space_aa` FXAA (softens shader / texture edges MSAA misses); TAA: `use_taa` **instead of** MSAA (resolves sub-pixel shimmer over time — thin runway lines, distant wires; a little softer, may ghost in fast rolls) |
| Terrain close up | Original / Detailed | 16× anisotropic filtering (default 4×) for the grazing view of the ground; in `terrain.gdshader` a tiling procedural detail texture (`terrain/detail_noise.tres`, brightness × (1 + 0.45·k·n), n of mean 0, two scales 24 m / 5 m in world space) and its normal map (`detail_normal.tres`), k fading from 1 at 300 m to 0 at 1.5 km and 0 on open sea, so colours from afar are the imagery's own; global shader parameter `terrain_detail` |
| Sky | Original / Atmospheric | Original: our gradient sky (ProceduralSkyMaterial) with the fixed fog colour. Atmospheric: `atmosphere.gdshader`, single scattering of the sun's light (Rayleigh λ⁻⁴ coefficients, Mie haze 2.5e-5 /m with Henyey-Greenstein g 0.85, Kasten-Young air mass along the view and the sun ray, scale heights 8 km / 1.2 km), the sun's disc (0.55°) dimmed by its air mass; the fog takes its colour from the sky (`fog_aerial_perspective` 1, `fog_sun_scatter` 0.25 for the glare in the haze); the fog density (the original's fog distances) is unchanged. No glow / bloom (it cost 3 ms) |

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
(MSAA 4× itself is ≈ 6 ms here); terrain close up ≈ +0.6–1.6 ms (near the ground), ≈ 0.5 ms at altitude; atmospheric
sky ≈ +0.2–0.9 ms. MSAA 8× (+5 ms) and MSAA + TAA (+7 ms) were measured and left out.
