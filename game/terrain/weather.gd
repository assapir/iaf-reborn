# Rain (ours, Preferences > Graphics → MORE "Rain": Off / Light / Heavy; docs/rendering.md §10). The original has no
# weather: Off (the default) makes nothing and changes nothing, whatever the mission says. Light / Heavy: a mission's
# own weather (Settings.flight_weather: the mission editor's and the Mission Creator's Weather; Clear stays dry) or,
# for a mission without one (the originals), the switch's level. Light / Heavy rain: falling drops around the camera
# (rain.gdshader), drops on the canopy in the cockpit views (canopy_drops.gdshader), wet ground (the global `rain_wet`:
# terrain.gdshader, model_detail.gdshaderinc), a shorter visibility and a dimmer sun (apply_env). Rendering only:
# nothing here touches the simulation. terrain_view.gd makes the node when the rain is on and feeds it each frame.
extends Node3D

## Per level: drops around the camera, the fog's density (Godot's exponential fog: the 5 % contrast visibility is
## 3 / density: 15 km Light, 6 km Heavy; the scene's own 0.00003 is 100 km), how far the fog covers the sky (the
## overcast), the sun's share, the ground's wetness 0..1 and the share of canopy cells holding a drop.
const LEVELS := {
	"light": {"drops": 6000, "fog": 0.0002, "sky": 0.6, "sun": 0.5, "wet": 0.6, "canopy": 0.35},
	"heavy": {"drops": 9000, "fog": 0.0005, "sky": 0.9, "sun": 0.25, "wet": 1.0, "canopy": 0.7},
}
## The drops' cube (m), their fall speed (m/s: about a 2 mm drop's terminal speed) and the drop's streak time (s).
const BOX := 40.0
const FALL := 7.0
## The overcast's ambient light (its colour; the time of day keeps the energy) and the wet ground's specular (Godot's
## 0..1; also its grazing reflection), under the Original and the Atmospheric sky.
const OVERCAST := Color(0.72, 0.74, 0.77)
const WET_SPEC := 0.3
const WET_SPEC_ATMO := 0.12
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

var streaks: MultiMeshInstance3D
var canopy: ColorRect
var _layer: CanvasLayer
var _mat: ShaderMaterial
var _drops: ShaderMaterial
var _drift := Vector3.ZERO
var _run := 0.0
var _now := 0.0
var _cam_last := Vector3.INF
var _cam_vel := Vector3.ZERO


## The flight's rain level's row; {} = dry (the switch Off, or a Clear mission).
static func level() -> Dictionary:
	if Settings.rain == "off":
		return {}
	return LEVELS.get(Settings.rain if Settings.flight_weather.is_empty() else Settings.flight_weather, {})


## The air's relative humidity 0..1 at `alt_m` (a hook for the condensation of vapour_fx.gd, which assumes its own:
## humid below 1.5 km, dry above 6 km). In the rain the air is saturated up to the cloud base (inferred: about 3 km).
static func humidity(alt_m: float) -> float:
	var dry := 1.0 - smoothstep(1500.0, 6000.0, alt_m)
	if level().is_empty():
		return dry
	return maxf(dry, 1.0 - smoothstep(3000.0, 6000.0, alt_m))


## The one place the rain changes the environment: the fog's density and its share of the sky (the overcast), the
## distance haze from the fog colour rather than the sky's (Atmospheric sky), the ambient light from the overcast's
## grey (OVERCAST) instead of the sky, the sun's energy, the ground's wetness and its specular. Off restores the
## scene's own values. Called after RenderOptions.apply and after each change of the sky.
static func apply_env(env: Environment, sun: DirectionalLight3D) -> void:
	var keys := ["fog_density", "fog_sky_affect", "ambient_light_source", "ambient_light_color"]
	if not env.has_meta("dry"):
		var o := {}
		for k in keys:
			o[k] = env.get(k)
		env.set_meta("dry", o)
	if sun != null and not sun.has_meta("dry_energy"):
		sun.set_meta("dry_energy", sun.light_energy)
	var l := level()
	wet = float(l.get("wet", 0.0))
	RenderingServer.global_shader_parameter_set("rain_wet", wet)
	var dry: Dictionary = env.get_meta("dry")
	env.fog_density = l.get("fog", dry.fog_density)
	env.fog_sky_affect = l.get("sky", dry.fog_sky_affect)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR if not l.is_empty() else dry.ambient_light_source
	env.ambient_light_color = OVERCAST if not l.is_empty() else dry.ambient_light_color
	# The Atmospheric sky's reflections stay blue (its radiance is a clear sky's): wet ground reflects little of it.
	RenderingServer.global_shader_parameter_set(
		"rain_spec", WET_SPEC_ATMO if Settings.sky == "atmospheric" else WET_SPEC
	)
	# Off: the aerial perspective is RenderOptions._apply_sky's, set just before.
	if not l.is_empty():
		env.fog_aerial_perspective = 0.0
	if sun != null:
		sun.light_energy = float(sun.get_meta("dry_energy")) * float(l.get("sun", 1.0))


## The fog colour of the time of day (TimeOfDay.fog) greyed toward its own luminance in the rain.
static func fog_tint(c: Color) -> Color:
	var l := level()
	if l.is_empty():
		return c
	var y := c.get_luminance()
	return c.lerp(Color(y, y, y) * FOG_GREY, float(l.sky))


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
	set_level()


## The chosen level's drop count and canopy drops.
func set_level() -> void:
	var l := level()
	streaks.multimesh.visible_instance_count = int(l.get("drops", 0))
	_drops.set_shader_parameter("amount", float(l.get("canopy", 0.0)))


## Each frame: the camera, whether it is a cockpit view, the wind (scene m/s), the fog colour (the streaks take its
## light) and the frame time. The canopy's airflow is the camera's speed through the air (in a cockpit view the jet's).
func update(cam: Camera3D, cockpit_view: bool, wind: Vector3, fog: Color, delta: float) -> void:
	if cam == null or delta <= 0.0:
		return
	_now += delta
	var p := cam.global_position
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
	canopy.visible = cockpit_view
	if cockpit_view:
		var airspeed := (_cam_vel - wind).length()
		_run += (maxf(airspeed - RUN_FROM, 0.0) * RUN_PER - SLIDE) * delta
		_drops.set_shader_parameter("run", _run)
		_drops.set_shader_parameter("flow", smoothstep(RUN_FROM, FLOW_FULL, airspeed))
		_drops.set_shader_parameter("now", _now)
