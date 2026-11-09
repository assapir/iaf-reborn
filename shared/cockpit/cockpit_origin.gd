# Ours (Modern IAF, Settings.cockpit_at_origin(); docs/cockpit.md "Cockpit at the origin"): the cockpit-view model
# (terrain_view.gd own_bc, with the 3D cockpit in it) drawn in its own world about the origin, so its vertices keep
# float32's micrometres however far the jet flies from the flight's start. In the flight's world they round to the
# step of the jet's position (3.1 mm 30 km out, 4.4 mm at 60 km: the whole cockpit jumped against the eye, the Mac play
# test's finding 25). A SubViewport the size of the screen draws that world through a camera that copies the flight
# camera's place in the rig, its projection and the rig's attitude (the world's orientation is kept, so the sun and
# the environment need no turning). Its picture, linear and untonemapped with its alpha, is laid over the flight's 3D
# view by a full-screen quad in that view (cockpit_composite.gdshader), so the flight's exposure and tonemap apply.
#   - `rig`: the cockpit world's stand-in for the flight's rig (own_bc's parent), at the origin with the rig's basis;
#   - `camera`: the cockpit world's eye (cockpit3d.gd projects the HUD glass and the screens' clicks through it);
#   - the Sun: the flight's sun copied each frame (the cockpit's shadows; cockpit3d.gd pulls its first split in);
#   - the environment: the flight's (the same ambient light and sky), without fog, tonemap or glow (the flight's apply).
# The flight's world keeps its lights for itself: a light there (a flare, a muzzle flash, the airbase lamps) does not
# reach the cockpit (inferred: none is near enough to matter for the cockpit's own lit panels).
extends Node

## The cockpit sun's shadow range, m: the canopy frame, the HUD and the seat over the panel (the eye in the middle).
const SHADOW_M := 8.0
## The flight environment's settings the cockpit world leaves out: fog over a metre is nothing; the tonemap, the
## exposure, the glow and the adjustments are the flight's, applied once over both (cockpit_composite.gdshader). The
## sky's radiance (the ambient light) is updated once a second (ENV_SYNC_S), as the flight's sun colour moves.
const ENV_OFF := {
	"fog_enabled": false,
	"volumetric_fog_enabled": false,
	"tonemap_mode": Environment.TONE_MAPPER_LINEAR,
	"tonemap_exposure": 1.0,
	"tonemap_white": 1.0,
	"glow_enabled": false,
	"adjustment_enabled": false,
}
const ENV_SYNC_S := 1.0

var rig := Node3D.new()
var camera := Camera3D.new()
var viewport := SubViewport.new()
var _world_camera: Camera3D
var _world_rig: Node3D
var _sun := DirectionalLight3D.new()
var _world_sun: DirectionalLight3D
var _env: WorldEnvironment
var _cockpit_env := Environment.new()
var _sky := Sky.new()
var _sync_t := INF
var _quad := MeshInstance3D.new()
var _shown: Node3D  # the node whose visibility switches the cockpit world on (own_bc)


## Builds the cockpit world beside `world_camera` (a child of `world_rig`), lit by `sun` and `env`.
func setup(world_camera: Camera3D, world_rig: Node3D, sun: DirectionalLight3D, env: WorldEnvironment) -> void:
	name = "CockpitOrigin"
	process_priority = 5  # after the flight scene placed its camera, before cockpit3d.gd (10) projects through ours
	_world_camera = world_camera
	_world_rig = world_rig
	_world_sun = sun
	_env = env
	viewport.world_3d = World3D.new()
	viewport.transparent_bg = true
	viewport.use_hdr_2d = true  # linear and unclamped: the flight's tonemap comes after
	viewport.handle_input_locally = false
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var root := Node3D.new()
	root.name = "CockpitWorld"
	viewport.add_child(root)
	# The sun's shadow over the cockpit only (its world holds nothing else): one map over SHADOW_M.
	_sun.name = "Sun"
	_sun.shadow_enabled = sun != null and sun.shadow_enabled
	_sun.shadow_blur = sun.shadow_blur if sun != null else 1.0
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_sun.directional_shadow_max_distance = SHADOW_M
	root.add_child(_sun)
	rig.name = "Rig"
	root.add_child(rig)
	camera.name = "Camera"
	rig.add_child(camera)
	camera.current = true
	add_child(viewport)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shared/cockpit/cockpit_composite.gdshader")
	mat.set_shader_parameter("cockpit", viewport.get_texture())
	mat.render_priority = Material.RENDER_PRIORITY_MAX  # the last transparent thing drawn
	_quad.mesh = QuadMesh.new()
	_quad.material_override = mat
	_quad.extra_cull_margin = 16384.0
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The main view's only, as the clouds' quad: the EO sensor's camera shares the flight's world and leaves this layer
	# out (terrain_view.gd _update_eo_view), so the cockpit is not laid over the TV picture on the MFD.
	_quad.layers = preload("res://shared/terrain/volumetric_clouds.gd").LAYER
	_quad.visible = false
	world_camera.add_child(_quad)


## The cockpit world is drawn while `node` (own_bc, a child of `rig`) is visible.
func show_with(node: Node3D) -> void:
	_shown = node


func _process(delta: float) -> void:
	var on := is_instance_valid(_shown) and _shown.visible and _world_camera.current  # own_bc goes on a jet switch
	_quad.visible = on
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	if not on:
		return
	var main := get_viewport()
	viewport.size = Vector2i(main.get_visible_rect().size)
	for p in ["msaa_3d", "screen_space_aa", "use_taa", "use_debanding", "scaling_3d_mode", "scaling_3d_scale"]:
		viewport.set(p, main.get(p))
	# The rig's attitude about the origin; the eye's place and turn in it as the flight camera's (head look, the ground
	# clamp), and its projection (cockpit.gd's frustum with its offset).
	rig.transform = Transform3D(_world_rig.global_basis, Vector3.ZERO)
	camera.transform = _world_camera.transform
	for p in ["projection", "fov", "size", "frustum_offset", "near", "far", "keep_aspect", "h_offset", "v_offset"]:
		camera.set(p, _world_camera.get(p))
	if _env != null:
		_sync_t += delta
		if _sync_t >= ENV_SYNC_S:
			_sync_t = 0.0
			_sync_env(_env.environment)
	if _world_sun != null:
		_sun.global_basis = _world_sun.global_basis
		_sun.visible = _world_sun.visible
		_sun.light_color = _world_sun.light_color
		_sun.light_energy = _world_sun.light_energy


## The cockpit world's environment follows the flight's `env` (the weather and the time of day change it): every
## stored property but ENV_OFF, its sky a copy whose radiance updates only when asked (Sky.PROCESS_MODE_INCREMENTAL).
func _sync_env(env: Environment) -> void:
	if env == null:
		return
	if viewport.world_3d.environment != _cockpit_env:
		viewport.world_3d.environment = _cockpit_env
	for prop in env.get_property_list():
		var n: String = prop.name
		if not (prop.usage & PROPERTY_USAGE_STORAGE) or n == "sky" or ENV_OFF.has(n):
			continue
		var v = env.get(n)
		if _cockpit_env.get(n) != v:
			_cockpit_env.set(n, v)
	for n in ENV_OFF:
		_cockpit_env.set(n, ENV_OFF[n])
	if env.sky != null:
		_sky.sky_material = env.sky.sky_material
		_sky.radiance_size = env.sky.radiance_size
		_sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
		_cockpit_env.sky = _sky


## The pointer's moves reach the cockpit before the flight's GUI takes them (cockpit3d_controls.gd: the hover, a drag).
func _input(event: InputEvent) -> void:
	if _quad.visible and event is InputEventMouseMotion:
		viewport.push_input(event, true)
		if viewport.is_input_handled():
			get_viewport().set_input_as_handled()


## A click reaches the cockpit (cockpit3d.gd's screen buttons) as it reached it in the flight's world.
func _unhandled_input(event: InputEvent) -> void:
	if _quad.visible and event is InputEventMouseButton:
		viewport.push_input(event, true)
		if viewport.is_input_handled():
			get_viewport().set_input_as_handled()
