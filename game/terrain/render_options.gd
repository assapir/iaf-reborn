# Our render options for high resolutions (Preferences > Graphics → MORE; docs/rendering.md): anti-aliasing, the
# terrain close up (detail texture, normal detail, 16× anisotropic filtering), the atmospheric sky and the water. The
# defaults are the look we had (the original's look, rendered by Godot); each improvement is opt-in. Rendering
# only: nothing here touches the simulation.
extends RefCounted

const GroundTextures := preload("res://terrain/ground_textures.gd")
const Scenery := preload("res://terrain/scenery.gd")
const ImageryLayers := preload("res://terrain/imagery_layers.gd")
const Weather := preload("res://terrain/weather.gd")

## Anti-aliasing: Settings.antialiasing -> [MSAA 3D, screen-space AA, TAA].
const AA := {
	"msaa4": [Viewport.MSAA_4X, Viewport.SCREEN_SPACE_AA_DISABLED, false],
	"msaa4_fxaa": [Viewport.MSAA_4X, Viewport.SCREEN_SPACE_AA_FXAA, false],
	"taa": [Viewport.MSAA_DISABLED, Viewport.SCREEN_SPACE_AA_DISABLED, true],
	# The temporal upscaler (temporal_mode()) anti-aliases the 3D scene itself, in place of MSAA and TAA.
	"temporal": [Viewport.MSAA_DISABLED, Viewport.SCREEN_SPACE_AA_DISABLED, false],
}

## Upscaling: Settings.upscaling -> the 3D render scale; "off" = native (1.0). The 3D scene renders at that fraction
## of the window and an upscaler scales it up to the window (upscale_mode()). With the other anti-aliasing choices it
## is spatial (MetalFX spatial on Metal, FSR 1 on other drivers) and the anti-aliasing row still applies, at the lower
## resolution. With anti-aliasing "temporal" it is the temporal upscaler (FSR 2.2; MetalFX temporal on Metal), which
## also anti-aliases, at every scale (at native it is anti-aliasing only). Temporal needs motion vectors, the pass TAA
## pays too (about 4 ms at 4K, docs/graphics-research.md §3.10). The 2D cockpit, HUD and MFDs are canvas items:
## Godot draws them after the upscale, at the window's resolution. Godot lowers the texture mip bias itself.
const UPSCALE := {"off": 1.0, "quality": 0.77, "balanced": 0.67}

## Terrain close up: the detail texture's strength (0 = off; global shader parameter, terrain.gdshader).
const DETAIL := 1.0
## The value last given to the global shader parameter (the RenderingServer does not read it back at run time).
static var terrain_detail := 0.0
## Water: 1 = waves, sun glint and sky reflection on the water (global `terrain_water`, terrain.gdshader), 0 = the
## original flat-shaded water.
static var terrain_water := 0.0
## Ground textures: 1 = the ambientCG textures near the camera (global `ground_tex`, terrain/ground_textures.gd),
## 0 = the original look (also when setup has not downloaded them).
static var ground_tex := 0.0

## terraintype.dat around the camera for the close up and the water (global `terrain_surface`: R = water, G = airbase):
## SURF_N² texels of SURF_CELL m (24.6 km across), rasterised in Rust (IafSurface) once the camera is SURF_MOVE m from
## its centre.
const SURF_N := 256
const SURF_CELL := 96.0
const SURF_MOVE := 4000.0
static var _surf_img: Image
static var _surf_tex: ImageTexture
static var _surf_origin := Vector2(INF, INF)  # x0, z0 of the texture shown

## Atmospheric sky: the camera altitude given to the sky shader, in steps of SKY_ALT_STEP m.
const SKY_ALT_STEP := 250.0
## Atmospheric sky: the ambient light. Godot takes the sky's share (SKY_SHARE, ambient_light_sky_contribution) at the
## sky's full radiance, and the rest from ambient_light_color × ambient_light_energy (SKY_AMBIENT): bounce(), the
## sunlit ground's and the haze's light, warm (BOUNCE per unit of the sun's light on level ground; tuned: the shade
## about 1/5 of the sunlit ground and a little cooler, as in photographs). The sky's radiance alone lit a shade with
## 1.8× the sun's light, deep blue: every shadow navy, the sunlit ground blue (docs/rendering.md §1.2).
const SKY_AMBIENT := 1.0
const SKY_SHARE := 0.1
const BOUNCE := Color(0.64, 0.62, 0.48)
const BOUNCE_SIN := 0.64
## Atmospheric sky: the haze's scale height (m; the shader's Mie scale height). The fog's density is the sea level's
## times the mean over the air below the camera, so from altitude the ground stays clear (haze_factor()).
const HAZE_HEIGHT := 1500.0
## Atmospheric sky's auto-exposure: the 3D scene's mean luminance (Godot's: the mean of each pixel's brightest
## channel; ≈ 1 by day, the blue sky's) that keeps the exposure at 1, and the factor either way it may adapt by (to
## 1 / RANGE … RANGE). Godot's default speed (0.5: about 2 s) eases a glance from the sky to the ground in.
const EXPOSURE_REF := 1.0
const EXPOSURE_RANGE := 1.25

## Godot compiles each mesh's pipelines in the background when it enters the scene, for the sample count of this
## project setting (read every frame), not the viewport's. With TAA or the temporal upscaler (no MSAA) the 4× ones did
## not fit, so 23–28 pipelines compiled while drawing the flight's first frames. Kept at the 3D view's sample count
## (docs/rendering.md §1.6).
const PIPELINE_MSAA := "rendering/anti_aliasing/quality/msaa_3d"


## Sets PIPELINE_MSAA for the anti-aliasing setting: by the mission screens (terrain_preload.gd), before the flight's
## meshes enter the scene, and by apply().
static func sync_pipeline_samples() -> void:
	ProjectSettings.set_setting(PIPELINE_MSAA, AA.get(Settings.antialiasing, AA["msaa4"])[0])


## Applies the options to the flight's viewport and its WorldEnvironment.
static func apply(vp: Viewport, env: Environment) -> void:
	var aa: Array = AA.get(Settings.antialiasing, AA["msaa4"])
	sync_pipeline_samples()
	vp.msaa_3d = aa[0]
	vp.screen_space_aa = aa[1]
	vp.use_taa = aa[2]
	var scale: float = UPSCALE.get(Settings.upscaling, 1.0)
	vp.scaling_3d_scale = scale
	vp.scaling_3d_mode = upscale_mode(scale)
	var close: bool = Settings.terrain_closeup
	vp.anisotropic_filtering_level = (
		Viewport.ANISOTROPY_16X
		if close
		else ProjectSettings.get_setting("rendering/textures/default_filters/anisotropic_filtering_level", 2)
	)
	terrain_detail = DETAIL if close else 0.0
	RenderingServer.global_shader_parameter_set("terrain_detail", terrain_detail)
	terrain_water = 1.0 if Settings.water else 0.0
	RenderingServer.global_shader_parameter_set("terrain_water", terrain_water)
	ground_tex = 1.0 if Settings.ground_textures == "ambientcg" and GroundTextures.load_globals() else 0.0
	RenderingServer.global_shader_parameter_set("ground_tex", ground_tex)
	# The Survey 2 m photo's pale hills warmed from grey to tan (terrain.gdshader, docs/imagery.md §5).
	var warm := Settings.imagery_israel == "mapi2015_modern" and ImageryLayers.available("mapi2015_modern")
	RenderingServer.global_shader_parameter_set("terrain_warm", 1.0 if warm else 0.0)
	# Scenery (docs/scenery.md §3): drawn only when Scenery.wanted (terrain.gd makes the node); its wall textures are
	# read here, at the flight's start, not at the first town.
	if Scenery.wanted(ImageryLayers.selected()):
		Scenery.walls()
	_surf_origin = Vector2(INF, INF)  # rebuilt around the camera (a new flight has its own world origin)
	if not close and not Settings.water and ground_tex == 0.0 and _surf_tex != null:
		RenderingServer.global_shader_parameter_set("terrain_surface", null)
		_surf_tex = null
		_surf_img = null
	_apply_sky(env, Settings.sky == "atmospheric", vp.find_world_3d().camera_attributes)


## The 3D scaling mode at `scale`: the temporal upscaler with anti-aliasing "temporal"; else bilinear at native and the
## spatial upscaler below (MetalFX spatial on Metal, FSR 1 on the others).
static func upscale_mode(scale: float) -> Viewport.Scaling3DMode:
	if Settings.antialiasing == "temporal":
		return temporal_mode()
	if scale >= 1.0:
		return Viewport.SCALING_3D_MODE_BILINEAR
	if RenderingServer.get_current_rendering_driver_name() == "metal":
		return Viewport.SCALING_3D_MODE_METALFX_SPATIAL
	return Viewport.SCALING_3D_MODE_FSR


## The temporal upscaler of the running driver: MetalFX temporal on Metal (cheaper there, §3.10), FSR 2.2 on the others.
static func temporal_mode() -> Viewport.Scaling3DMode:
	if RenderingServer.get_current_rendering_driver_name() == "metal":
		return Viewport.SCALING_3D_MODE_METALFX_TEMPORAL
	return Viewport.SCALING_3D_MODE_FSR2


## The temporal upscaler's name on the Anti-aliasing row.
static func temporal_name() -> String:
	return "MetalFX" if temporal_mode() == Viewport.SCALING_3D_MODE_METALFX_TEMPORAL else "FSR 2"


## "Atmospheric": a physically based sky (terrain/atmosphere.gdshader: Rayleigh / Mie scattering with multiple
## scattering, the sun's disc and glare), the ambient light from that sky and the ground's bounce (SKY_*), the
## distance haze taken from it (aerial perspective, sun scatter), thinning with the camera's altitude (update_view),
## and a bounded auto-exposure (EXPOSURE_*). No glow (bloom): 3 ms on an Iris Xe for little. Off: the gradient sky as
## before.
static func _apply_sky(env: Environment, on: bool, attrs: CameraAttributes) -> void:
	var keys := ["sky", "fog_aerial_perspective", "fog_sun_scatter", "ambient_light_sky_contribution", "fog_density"]
	if not env.has_meta("original_sky"):
		var o := {}
		for k in keys:
			o[k] = env.get(k)
		env.set_meta("original_sky", o)
	var orig: Dictionary = env.get_meta("original_sky")
	if attrs != null:
		attrs.auto_exposure_enabled = on
		attrs.auto_exposure_scale = EXPOSURE_REF
		# Sensitivity (ISO) = luminance / 0.00125 (Godot's conversion at its ISO 100 exposure).
		attrs.set("auto_exposure_min_sensitivity", EXPOSURE_REF / EXPOSURE_RANGE / 0.00125)
		attrs.set("auto_exposure_max_sensitivity", EXPOSURE_REF * EXPOSURE_RANGE / 0.00125)
	if not on:
		for k in keys:
			env.set(k, orig[k])
		return
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://terrain/atmosphere.gdshader")
	var sky := Sky.new()
	# The radiance (ambient light) is re-rendered over several frames when the sky changes, not in one.
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.sky_material = mat
	env.sky = sky
	env.fog_aerial_perspective = 1.0
	env.fog_sun_scatter = 0.1
	env.ambient_light_sky_contribution = SKY_SHARE


## Atmospheric sky: the ambient light's own colour, BOUNCE times the sun's light (`color`, `energy`) on level ground,
## `sin_elev` the sine of its elevation; terrain_view.gd sets it with the time of day, when dry. The diffuse light
## falls slower than the direct light as the sun goes down (inferred): by √sin, equal to sin at BOUNCE_SIN (the sun
## 40° up). By sin alone the scene at 19:30 (the sun 6° up) was black in the shade.
static func bounce(color: Color, energy: float, sin_elev: float) -> Color:
	var c := BOUNCE * color * (energy * sqrt(BOUNCE_SIN * maxf(sin_elev, 0.0)))
	c.a = 1.0
	return c


## The mean of the haze's density (exp(−h / HAZE_HEIGHT)) over the air from sea level up to `alt` m, over its sea
## level's: 1 on the ground, 0.3 at 5000 m.
static func haze_factor(alt: float) -> float:
	var x := maxf(alt, 1.0) / HAZE_HEIGHT
	return (1.0 - exp(-x)) / x


## Per frame with the camera's position: the atmospheric sky's altitude, its overcast in the rain (Weather), the
## haze's density by altitude when dry, and the surface types for the close up and the water.
static func update_view(env: Environment, cam: Vector3, terrain: Node) -> void:
	if env.sky != null and env.sky.sky_material is ShaderMaterial:
		var mat: ShaderMaterial = env.sky.sky_material
		var alt := snappedf(maxf(cam.y, 0.0), SKY_ALT_STEP)
		if mat.get_shader_parameter("altitude") != alt:
			mat.set_shader_parameter("altitude", alt)
		var overcast: float = Weather.level().get("sky", 0.0) if Weather.wet > 0.0 else 0.0
		if mat.get_shader_parameter("overcast") != overcast:
			mat.set_shader_parameter("overcast", overcast)
		if Weather.level().is_empty():
			env.fog_density = float(env.get_meta("original_sky").fog_density) * haze_factor(cam.y)
	if (terrain_detail > 0.0 or terrain_water > 0.0 or ground_tex > 0.0) and terrain != null:
		_update_surface(Vector2(cam.x, cam.z), terrain)


static func _update_surface(c: Vector2, terrain: Node) -> void:
	var side := SURF_N * SURF_CELL
	if c.distance_to(_surf_origin + Vector2(0.5, 0.5) * side) < SURF_MOVE:
		return
	_surf_origin = (c / SURF_CELL).round() * SURF_CELL - Vector2(0.5, 0.5) * side
	# Godot (x, z) -> engine metres (X east, Y north): X = origin.x + x, Y = origin.y - z.
	var o: Vector2 = terrain.world_origin
	var rg: PackedByteArray = IafSurface.raster_rg8(o.x + _surf_origin.x, o.y - _surf_origin.y, SURF_CELL, SURF_N)
	_surf_img = Image.create_from_data(SURF_N, SURF_N, false, Image.FORMAT_RG8, rg)
	if _surf_tex == null:
		_surf_tex = ImageTexture.create_from_image(_surf_img)
		RenderingServer.global_shader_parameter_set("terrain_surface", _surf_tex)
	else:
		_surf_tex.update(_surf_img)
	RenderingServer.global_shader_parameter_set(
		"terrain_surface_rect", Vector4(_surf_origin.x, _surf_origin.y, 1.0 / side, 0.0)
	)
