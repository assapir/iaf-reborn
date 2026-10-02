# Our render options for high resolutions (Preferences > Extras; docs/rendering.md): anti-aliasing, the
# terrain close up (detail texture, normal detail, 16× anisotropic filtering) and the atmospheric sky. The
# defaults are the look we had (the original's look, rendered by Godot); each improvement is opt-in. Rendering
# only: nothing here touches the simulation.
extends RefCounted

## Anti-aliasing: Settings.antialiasing -> [MSAA 3D, screen-space AA, TAA].
const AA := {
	"msaa4": [Viewport.MSAA_4X, Viewport.SCREEN_SPACE_AA_DISABLED, false],
	"msaa4_fxaa": [Viewport.MSAA_4X, Viewport.SCREEN_SPACE_AA_FXAA, false],
	"taa": [Viewport.MSAA_DISABLED, Viewport.SCREEN_SPACE_AA_DISABLED, true],
}

## Terrain close up: the detail texture's strength (0 = off; global shader parameter, terrain.gdshader).
const DETAIL := 1.0
const Terrain := preload("res://terrain/terrain.gd")
## The value last given to the global shader parameter (the RenderingServer does not read it back at run time).
static var terrain_detail := 0.0

## terraintype.dat around the camera for the close up (global `terrain_surface`: R = water, G = airbase):
## SURF_N² texels of SURF_CELL m, rebuilt SURF_ROWS rows per frame once the camera is SURF_MOVE m from its centre.
const SURF_N := 32
const SURF_CELL := 96.0
const SURF_MOVE := 600.0
const SURF_ROWS := 4
static var _surf_img: Image
static var _surf_tex: ImageTexture
static var _surf_origin := Vector2(INF, INF)  # x0, z0 of the texture shown
static var _surf_next := Vector2(INF, INF)  # of the one being built
static var _surf_row := -1

## Atmospheric sky: the camera altitude given to the sky shader, in steps of SKY_ALT_STEP m.
const SKY_ALT_STEP := 250.0


## Applies the options to the flight's viewport and its WorldEnvironment.
static func apply(vp: Viewport, env: Environment) -> void:
	var aa: Array = AA.get(Settings.antialiasing, AA["msaa4"])
	vp.msaa_3d = aa[0]
	vp.screen_space_aa = aa[1]
	vp.use_taa = aa[2]
	var close: bool = Settings.terrain_closeup
	vp.anisotropic_filtering_level = Viewport.ANISOTROPY_16X if close \
			else ProjectSettings.get_setting("rendering/textures/default_filters/anisotropic_filtering_level", 2)
	terrain_detail = DETAIL if close else 0.0
	RenderingServer.global_shader_parameter_set("terrain_detail", terrain_detail)
	_surf_origin = Vector2(INF, INF)  # rebuilt around the camera (a new flight has its own world origin)
	_surf_row = -1
	if not close and _surf_tex != null:
		RenderingServer.global_shader_parameter_set("terrain_surface", null)
		_surf_tex = null
		_surf_img = null
	_apply_sky(env, Settings.sky == "atmospheric")


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
	sky.sky_material = mat
	env.sky = sky
	env.fog_aerial_perspective = 1.0
	env.fog_sun_scatter = 0.1


## Per frame with the camera's position: the atmospheric sky's altitude and the close up's surface types.
static func update_view(env: Environment, cam: Vector3, terrain: Node) -> void:
	if env.sky != null and env.sky.sky_material is ShaderMaterial:
		var mat: ShaderMaterial = env.sky.sky_material
		var alt := snappedf(maxf(cam.y, 0.0), SKY_ALT_STEP)
		if mat.get_shader_parameter("altitude") != alt:
			mat.set_shader_parameter("altitude", alt)
	if terrain_detail > 0.0 and terrain != null:
		_update_surface(Vector2(cam.x, cam.z), terrain)


static func _update_surface(c: Vector2, terrain: Node) -> void:
	var side := SURF_N * SURF_CELL
	if _surf_row < 0:
		if c.distance_to(_surf_origin + Vector2(0.5, 0.5) * side) < SURF_MOVE:
			return
		_surf_next = (c / SURF_CELL).round() * SURF_CELL - Vector2(0.5, 0.5) * side
		_surf_img = Image.create(SURF_N, SURF_N, false, Image.FORMAT_RG8)
		_surf_row = 0
	for j in range(_surf_row, mini(_surf_row + SURF_ROWS, SURF_N)):
		for i in SURF_N:
			var p := _surf_next + (Vector2(i, j) + Vector2(0.5, 0.5)) * SURF_CELL
			var f: int = terrain.surface_at(Vector3(p.x, 0.0, p.y))
			# Water (island leaves carry the water bit too: not water), airbase.
			var water := (f & Terrain.SURFACE_WATER) != 0 and (f & Terrain.SURFACE_ISLAND) == 0
			_surf_img.set_pixel(i, j, Color(1.0 if water else 0.0, 1.0 if (f & Terrain.SURFACE_RUNWAY) != 0 else 0.0, 0.0))
	_surf_row += SURF_ROWS
	if _surf_row < SURF_N:
		return
	_surf_row = -1
	_surf_origin = _surf_next
	if _surf_tex == null:
		_surf_tex = ImageTexture.create_from_image(_surf_img)
		RenderingServer.global_shader_parameter_set("terrain_surface", _surf_tex)
	else:
		_surf_tex.update(_surf_img)
	RenderingServer.global_shader_parameter_set("terrain_surface_rect", Vector4(_surf_origin.x, _surf_origin.y, 1.0 / side, 0.0))
