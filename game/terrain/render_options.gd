# Our render options for high resolutions (Preferences > Graphics → MORE; docs/rendering.md): anti-aliasing, the
# terrain close up (detail texture, normal detail, 16× anisotropic filtering), the atmospheric sky and the water. The
# defaults are the look we had (the original's look, rendered by Godot); each improvement is opt-in. Rendering
# only: nothing here touches the simulation.
extends RefCounted

const GroundTextures := preload("res://terrain/ground_textures.gd")

## Anti-aliasing: Settings.antialiasing -> [MSAA 3D, screen-space AA, TAA].
const AA := {
	"msaa4": [Viewport.MSAA_4X, Viewport.SCREEN_SPACE_AA_DISABLED, false],
	"msaa4_fxaa": [Viewport.MSAA_4X, Viewport.SCREEN_SPACE_AA_FXAA, false],
	"taa": [Viewport.MSAA_DISABLED, Viewport.SCREEN_SPACE_AA_DISABLED, true],
}

## Upscaling: Settings.upscaling -> the 3D render scale; "off" = native (bilinear at 1.0). The 3D scene renders at
## that fraction of the window, and a spatial upscaler (MetalFX on Metal, FSR 1 on other drivers) scales it up to
## the window. The anti-aliasing row still applies, at the lower resolution. The 2D cockpit, HUD and MFDs are
## canvas items: Godot draws them after the upscale, at the window's resolution. Godot lowers the texture mip bias by
## log2(scale) itself. Spatial, because the temporal upscalers need motion vectors, which cost about 4 ms at 4K
## (docs/graphics-research.md §3.10).
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


## Applies the options to the flight's viewport and its WorldEnvironment.
static func apply(vp: Viewport, env: Environment) -> void:
	var aa: Array = AA.get(Settings.antialiasing, AA["msaa4"])
	vp.msaa_3d = aa[0]
	vp.screen_space_aa = aa[1]
	vp.use_taa = aa[2]
	var scale: float = UPSCALE.get(Settings.upscaling, 1.0)
	vp.scaling_3d_scale = scale
	vp.scaling_3d_mode = upscale_mode() if scale < 1.0 else Viewport.SCALING_3D_MODE_BILINEAR
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
	_surf_origin = Vector2(INF, INF)  # rebuilt around the camera (a new flight has its own world origin)
	if not close and not Settings.water and ground_tex == 0.0 and _surf_tex != null:
		RenderingServer.global_shader_parameter_set("terrain_surface", null)
		_surf_tex = null
		_surf_img = null
	_apply_sky(env, Settings.sky == "atmospheric")


## The spatial upscaler of the running driver: MetalFX on Metal, FSR 1 on the others.
static func upscale_mode() -> Viewport.Scaling3DMode:
	if RenderingServer.get_current_rendering_driver_name() == "metal":
		return Viewport.SCALING_3D_MODE_METALFX_SPATIAL
	return Viewport.SCALING_3D_MODE_FSR


## "Atmospheric": a physically based sky (terrain/atmosphere.gdshader: Rayleigh / Mie scattering with the sun's
## disc and glare) and the distance haze taken from it (aerial perspective, sun scatter); the fog density, i.e.
## the fog distances, stays. No glow (bloom): 3 ms on an Iris Xe for little. Off: the gradient sky as before.
static func _apply_sky(env: Environment, on: bool) -> void:
	var keys := ["sky", "fog_aerial_perspective", "fog_sun_scatter"]
	if not env.has_meta("original_sky"):
		var o := {}
		for k in keys:
			o[k] = env.get(k)
		env.set_meta("original_sky", o)
	var orig: Dictionary = env.get_meta("original_sky")
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


## Per frame with the camera's position: the atmospheric sky's altitude and the surface types for the close up
## and the water.
static func update_view(env: Environment, cam: Vector3, terrain: Node) -> void:
	if env.sky != null and env.sky.sky_material is ShaderMaterial:
		var mat: ShaderMaterial = env.sky.sky_material
		var alt := snappedf(maxf(cam.y, 0.0), SKY_ALT_STEP)
		if mat.get_shader_parameter("altitude") != alt:
			mat.set_shader_parameter("altitude", alt)
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
