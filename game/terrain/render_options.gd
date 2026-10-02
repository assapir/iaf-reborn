# Our render options for high resolutions (Preferences > Extras; docs/rendering.md): anti-aliasing, the
# terrain close up (detail texture, normal detail, 16× anisotropic filtering) and the atmospheric sky. The
# defaults are the look we had (the original's look, rendered by Godot); each improvement is opt-in. Rendering
# only: nothing here touches the simulation.
extends RefCounted

## Anti-aliasing: Settings.antialiasing -> [MSAA 3D, screen-space AA, TAA].
const AA := {
	"msaa4": [Viewport.MSAA_4X, Viewport.SCREEN_SPACE_AA_DISABLED, false],
	"msaa4_fxaa": [Viewport.MSAA_4X, Viewport.SCREEN_SPACE_AA_FXAA, false],
	"taa": [Viewport.MSAA_4X, Viewport.SCREEN_SPACE_AA_DISABLED, true],
}

## Terrain close up: the detail texture's strength (0 = off; global shader parameter, terrain.gdshader).
const DETAIL := 1.0
## The value last given to the global shader parameter (the RenderingServer does not read it back at run time).
static var terrain_detail := 0.0


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
	env.fog_sun_scatter = 0.25
