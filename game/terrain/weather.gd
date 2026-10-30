# Rain (ours, Preferences > Graphics → MORE "Rain": Off / Light / Heavy; docs/rendering.md §10). The original has no
# weather: Off (the default) makes nothing and changes nothing, whatever the mission says. Light / Heavy: a mission's
# own weather (Settings.flight_weather: the mission editor's and the Mission Creator's Weather; Clear stays dry) or,
# for a mission without one (the originals), the switch's level. Light / Heavy rain: falling drops around the camera
# (rain.gdshader), drops on the canopy in the cockpit views (canopy_drops.gdshader), wet ground (the global `rain_wet`:
# terrain.gdshader, model_detail.gdshaderinc), a shorter visibility and a dimmer sun (apply_env), all under a cloud
# deck with a base and a top (§10.1): inside it dense fog, above it a clear sky over the deck's floor
# (deck_floor.gdshader; with Clouds Volumetric the raymarched deck of volumetric_clouds.gd instead). Rendering only:
# nothing here touches the simulation. terrain_view.gd makes the node when the rain is on and feeds it each frame.
extends Node3D

const RenderOptions := preload("res://terrain/render_options.gd")
const CloudLayer := preload("res://terrain/cloud_layer.gd")
const Img := preload("res://util/img.gd")

## Per level: drops around the camera, the fog's density (Godot's exponential fog: the 5 % contrast visibility is
## 3 / density: 15 km Light, 6 km Heavy; the scene's own 0.00003 is 100 km), how far the fog covers the sky (the
## overcast), the sun's share, the ground's wetness 0..1, the share of canopy cells holding a drop and the cloud deck's
## base and top (m above `ground_ref`): light rain from a stratocumulus or a thin nimbostratus, heavy rain from a deep
## nimbostratus (docs/rendering.md §10.1).
const LEVELS := {
	"light":
	{"drops": 6000, "fog": 0.0002, "sky": 0.6, "sun": 0.5, "wet": 0.6, "canopy": 0.35, "base": 800.0, "top": 3000.0},
	"heavy":
	{"drops": 9000, "fog": 0.0005, "sky": 0.9, "sun": 0.25, "wet": 1.0, "canopy": 0.7, "base": 450.0, "top": 5500.0},
}
## Inside the deck: the fog's density (3 / 0.02 = 150 m visibility) and the sun's share. The base blends over
## ± EDGE m and the top over ± EDGE_TOP m (the fog thins ×700 there), so the fog changes by at most ×1.6 per 25 m: no
## pop. The deck stands on the ground under the camera smoothed over GROUND_TAU s: it rises over a plateau and does not
## jump at each hill.
const DECK_FOG := 0.02
const DECK_SUN := 0.1
const EDGE := 150.0
const EDGE_TOP := 300.0
const GROUND_TAU := 60.0
## The deck's floor seen from above (deck_floor.gdshader): a square this wide (m) under the camera (the far plane's
## 200 km each way) and the cloud texture it takes its lumps from (Cloud256_5, the overcast one).
const FLOOR_SIZE := 400000.0
const FLOOR_TEX := 5
## The drops' cube (m), their fall speed (m/s: about a 2 mm drop's terminal speed) and the drop's streak time (s).
const BOX := 40.0
const FALL := 7.0
## The overcast's ambient light (its colour; the time of day keeps the energy) and the wet ground's specular (Godot's
## 0..1; also its grazing reflection), under either sky (the Atmospheric one turns grey in the rain, rendering.md §10).
const OVERCAST := Color(0.72, 0.74, 0.77)
const WET_SPEC := 0.3
## Grey of the fog in the rain (its colour's luminance, kept) and how far toward it.
const FOG_GREY := 0.8
## The canopy airflow: no run below RUN_FROM m/s, then RUN_PER screen heights per s per m/s; at rest the drops slide
## down SLIDE screen heights per s. FLOW_FULL m/s streams them fully.
const RUN_FROM := 12.0
const RUN_PER := 0.02
const SLIDE := 0.004
const FLOW_FULL := 80.0

## The wetness last set (the RenderingServer does not read global shader parameters back at run time).
static var wet := 0.0
## The camera's place in the deck, set each frame by update(): `into` 0 below the base → 1 inside it, `out` 0 → 1
## above its top; `ground_ref` the smoothed ground height (m) the deck stands on.
static var into := 0.0
static var out := 0.0
static var ground_ref := 0.0
static var _ground_set := false

var streaks: MultiMeshInstance3D
var canopy: ColorRect
## The deck's floor seen from above (with Clouds Original).
var deck_floor: MeshInstance3D
var _layer: CanvasLayer
var _mat: ShaderMaterial
var _drops: ShaderMaterial
var _drift := Vector3.ZERO
var _run := 0.0
var _now := 0.0
var _cam_last := Vector3.INF
var _cam_vel := Vector3.ZERO
var _drift_world := Vector3.ZERO


## The flight's rain level's row; {} = dry (the switch Off, or a Clear mission).
static func level() -> Dictionary:
	if Settings.rain == "off":
		return {}
	return LEVELS.get(Settings.rain if Settings.flight_weather.is_empty() else Settings.flight_weather, {})


## The deck's base and top (m, scene altitude); (0, 0) when dry.
static func deck() -> Vector2:
	var l := level()
	if l.is_empty():
		return Vector2.ZERO
	return Vector2(l.base, l.top) + Vector2.ONE * ground_ref


## The overcast's share at the camera: the level's below the base, all of it inside the deck, none above it. The fog
## colour and both skies turn grey by it.
static func grey() -> float:
	var l := level()
	if l.is_empty():
		return 0.0
	return lerpf(lerpf(float(l.sky), 1.0, into), 0.0, out)


## Each frame with the ground under the camera (m; null where not loaded): the ground the clouds stand on, eased.
static func track_ground(ground: Variant, delta: float) -> void:
	if ground == null:
		return
	var g := maxf(float(ground), 0.0)
	ground_ref = g if not _ground_set else lerpf(ground_ref, g, minf(delta / GROUND_TAU, 1.0))
	_ground_set = true


## The air's relative humidity 0..1 at `alt_m` (a hook for the condensation of vapour_fx.gd, which assumes its own:
## humid below 1.5 km, dry above 6 km). In the rain the air is saturated up to the deck's top, drying over 3 km above.
static func humidity(alt_m: float) -> float:
	var dry := 1.0 - smoothstep(1500.0, 6000.0, alt_m)
	if level().is_empty():
		return dry
	var top := deck().y
	return maxf(dry, 1.0 - smoothstep(top, top + 3000.0, alt_m))


## The one place the rain changes the environment: the fog's density and its share of the sky (the overcast), the
## distance haze from the fog colour rather than the sky's (Atmospheric sky), the ambient light from the overcast's
## grey (OVERCAST) instead of the sky, the sun's energy, the ground's wetness and its specular, by the camera's place in
## the deck (blend()). Off restores the scene's own values. Called after RenderOptions.apply and after each change of
## the sky (both set the sky's ambient share, kept here as the dry one).
static func apply_env(env: Environment, sun: DirectionalLight3D) -> void:
	var keys := ["fog_density", "fog_sky_affect", "ambient_light_color"]
	if not env.has_meta("dry"):
		var o := {}
		for k in keys:
			o[k] = env.get(k)
		env.set_meta("dry", o)
		_ground_set = false  # a new flight: the deck stands on its own ground
	env.set_meta("dry_sky_share", env.ambient_light_sky_contribution)
	if sun != null and not sun.has_meta("dry_energy"):
		sun.set_meta("dry_energy", sun.light_energy)
	var l := level()
	wet = float(l.get("wet", 0.0))
	RenderingServer.global_shader_parameter_set("rain_wet", wet)
	# The Atmospheric sky's reflections stay blue (its radiance is a clear sky's): wet ground reflects little of it.
	RenderingServer.global_shader_parameter_set("rain_spec", WET_SPEC)
	var dry: Dictionary = env.get_meta("dry")
	if l.is_empty():
		into = 0.0
		out = 0.0
		for k in keys:
			env.set(k, dry[k])
		if sun != null:
			sun.light_energy = float(sun.get_meta("dry_energy"))
		return
	# Dry, the aerial perspective is RenderOptions._apply_sky's, set just before.
	env.fog_aerial_perspective = 0.0
	blend(env, sun, float(dry.fog_density))


## The rain's environment at the camera's place in the deck (into, out): below the base the level's fog, overcast and
## sun; inside the deck DECK_FOG, all overcast and DECK_SUN; above the top the dry scene's (`dry_fog`: its fog density
## at the camera). The density blends on a log scale, so the visibility changes evenly. The ambient keeps the sky as
## its source: a sky share of 0 under the deck (the overcast's grey alone), the dry share above it.
static func blend(env: Environment, sun: DirectionalLight3D, dry_fog: float) -> void:
	var l := level()
	if l.is_empty():
		return
	var dry: Dictionary = env.get_meta("dry")
	env.fog_density = exp(lerpf(lerpf(log(float(l.fog)), log(DECK_FOG), into), log(dry_fog), out))
	env.fog_sky_affect = lerpf(lerpf(float(l.sky), 1.0, into), float(dry.fog_sky_affect), out)
	env.ambient_light_sky_contribution = float(env.get_meta("dry_sky_share")) * out
	env.ambient_light_color = OVERCAST.lerp(dry.ambient_light_color, out)
	if sun != null:
		var share := lerpf(lerpf(float(l.sun), DECK_SUN, into), 1.0, out)
		sun.light_energy = float(sun.get_meta("dry_energy")) * share


## The dry sky's ambient colour (the Atmospheric sky's bounce, terrain_view.gd): set at once when dry, kept for above
## the deck while it rains.
static func set_dry_ambient(env: Environment, c: Color) -> void:
	if level().is_empty() or not env.has_meta("dry"):
		env.ambient_light_color = c
		return
	env.get_meta("dry").ambient_light_color = c


## The fog colour of the time of day (TimeOfDay.fog) greyed toward its own luminance by the overcast's share.
static func fog_tint(c: Color) -> Color:
	if level().is_empty():
		return c
	var y := c.get_luminance()
	return c.lerp(Color(y, y, y) * FOG_GREY, grey())


func _ready() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = QuadMesh.new()
	mm.instance_count = LEVELS.heavy.drops
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://terrain/rain.gdshader")
	_mat.set_shader_parameter("box", BOX)
	streaks = MultiMeshInstance3D.new()
	streaks.multimesh = mm
	streaks.material_override = _mat
	streaks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The drops are placed in the shader: never culled.
	streaks.custom_aabb = AABB(Vector3.ONE * -1e6, Vector3.ONE * 2e6)
	add_child(streaks)
	_drops = ShaderMaterial.new()
	_drops.shader = preload("res://terrain/canopy_drops.gdshader")
	canopy = ColorRect.new()
	canopy.material = _drops
	canopy.set_anchors_preset(Control.PRESET_FULL_RECT)
	canopy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer = CanvasLayer.new()
	_layer.layer = -1  # over the 3D view, under the cockpit (as the cloud layer's whiteout)
	_layer.add_child(canopy)
	add_child(_layer)
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * FLOOR_SIZE
	var fm := ShaderMaterial.new()
	fm.shader = preload("res://terrain/deck_floor.gdshader")
	var tex := Img.load_texture(CloudLayer.path(FLOOR_TEX), true)
	if tex != null:
		fm.set_shader_parameter("tex", tex)
	deck_floor = MeshInstance3D.new()
	deck_floor.mesh = plane
	deck_floor.material_override = fm
	deck_floor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	deck_floor.visible = false
	add_child(deck_floor)
	set_level()


## The chosen level's drop count and canopy drops.
func set_level() -> void:
	var l := level()
	_drops.set_shader_parameter("amount", float(l.get("canopy", 0.0)) * (1.0 - into))
	streaks.multimesh.visible_instance_count = int(float(l.get("drops", 0)) * (1.0 - into))


## Each frame: the camera, whether it is a cockpit view, the wind (scene m/s), the fog colour (the streaks take its
## light) and the frame time. The camera's place in the deck sets the environment (blend()), the drops (none above
## the base) and the floor (above the top). The canopy's airflow is the camera's speed through the air (in a cockpit
## view the jet's).
func update(cam: Camera3D, cockpit_view: bool, wind: Vector3, fog: Color, delta: float) -> void:
	if cam == null or delta <= 0.0:
		return
	_now += delta
	var p := cam.global_position
	var d := deck()
	into = smoothstep(d.x - EDGE, d.x + EDGE, p.y)
	out = smoothstep(d.y - EDGE_TOP, d.y + EDGE_TOP, p.y)
	var env := (get_parent().get_node("WorldEnvironment") as WorldEnvironment).environment
	var dry_fog := float(env.get_meta("dry").fog_density)
	if env.sky != null and env.sky.sky_material is ShaderMaterial:
		dry_fog *= RenderOptions.haze_factor(p.y)  # the Atmospheric sky's haze by altitude
	blend(env, get_parent().get_node("Sun") as DirectionalLight3D, dry_fog)
	set_level()
	deck_floor.visible = p.y > d.y and get_parent().get("vclouds") == null  # Volumetric draws its own deck
	deck_floor.position = Vector3(p.x, d.y, p.z)
	# Its lumps stay put in the world and drift with the wind.
	deck_floor.material_override.set_shader_parameter("drift", Vector2(_drift_world.x, _drift_world.z))
	_drift_world += wind * delta
	# The camera's velocity from its travel; a jump (a view change) keeps the last one.
	if _cam_last != Vector3.INF:
		var v := (p - _cam_last) / delta
		if v.length() < 700.0:
			_cam_vel = v
	_cam_last = p
	var fall := Vector3(0.0, -FALL, 0.0) + wind
	_drift = (_drift + fall * delta).posmod(BOX)
	_mat.set_shader_parameter("fall", fall)
	_mat.set_shader_parameter("drift", _drift)
	_mat.set_shader_parameter("cam_vel", _cam_vel)
	_mat.set_shader_parameter("tint", fog.darkened(0.5))
	canopy.visible = cockpit_view and into < 1.0
	if canopy.visible:
		var airspeed := (_cam_vel - wind).length()
		_run += (maxf(airspeed - RUN_FROM, 0.0) * RUN_PER - SLIDE) * delta
		_drops.set_shader_parameter("run", _run)
		_drops.set_shader_parameter("flow", smoothstep(RUN_FROM, FLOW_FULL, airspeed))
		_drops.set_shader_parameter("now", _now)
