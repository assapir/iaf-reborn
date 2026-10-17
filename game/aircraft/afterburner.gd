# The afterburner flame of one nozzle, drawn like the original's hardware path (FUN_004121e0,
# docs/aircraft.md §3): two nested 12-segment cones from the nozzle ring toward the tail (+Z),
# rebuilt every frame with fresh random length / tip / texture offset, textured with
# afterburn.tga (opaque at the nozzle, fading at the tip). Nothing is drawn below level 75.
# Rendering is additive (a glow) — the original's blend state is not decoded (UNCERTAIN).
extends MeshInstance3D

## Nozzle centre (model space, metres) and base radius |ΔY(EngineX, EngineX1)|.
var nozzle := Vector3.ZERO
var radius := 0.4
## Clump scale of the model (5.0): the fixed part of the flame length is 1.5·i scaled units.
var scale_factor := 5.0
## Render level 0..100 (FUN_005abc90: 75 + 12.5·afterburner stage, else RPM·0.74 ≤ 74).
var level := 0

const SEGMENTS := 12
## Hardware path: cones i = 2 (radius 0.7 r) and i = 3 (radius r); the software path draws only i = 3.
const CONES := [[2, 0.7], [3, 1.0]]

var _mesh := ImmediateMesh.new()
var _material: StandardMaterial3D
## Heat haze (Detailed effects, Preferences > Graphics > MORE): a refracting cone behind the nozzle, a sibling so it shows
## while the flame is off. null = the original look.
var haze: MeshInstance3D

const HAZE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D noise : repeat_enable, filter_linear_mipmap;
uniform float strength = 0.0;
varying float along;
varying vec3 axis;
void vertex() {
	// The cylinder's local Y (-0.5 at the nozzle, +0.5 at the far end): `along` runs 0 -> 1 from the nozzle.
	along = VERTEX.y + 0.5;
	axis = normalize((MODELVIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}
void fragment() {
	// Strongest across the middle of the cone as seen, fading along it.
	// Seen from the side, the middle of the cone (facing the eye) shimmers and its silhouette fades; seen along
	// the axis (from behind) the whole cone shimmers.
	float side_on = 1.0 - abs(dot(axis, normalize(VIEW)));
	float facing = mix(1.0, abs(dot(normalize(NORMAL), normalize(VIEW))), side_on);
	vec2 n = vec2(texture(noise, vec2(UV.x * 2.0, along * 1.5 - TIME * 2.2)).r,
		texture(noise, vec2(UV.x * 2.0 + 0.5, along * 1.5 - TIME * 1.7)).g) - 0.5;
	float k = strength * smoothstep(0.0, 0.08, along) * (1.0 - along) * facing * facing;
	ALBEDO = textureLod(screen, SCREEN_UV + n * 0.006 * k, 0.0).rgb;
	// The screen copy holds the opaque scene only: blend it in no further than the shimmer needs.
	ALPHA = clamp(k * 0.8, 0.0, 0.8);
}
"""


func _init() -> void:
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.no_depth_test = false
	_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var tex := preload("res://util/img.gd").load_texture(Settings.assets_dir().path_join("converted/planes/afterburn.png"))
	if tex != null:
		_material.albedo_texture = tex
	else:
		_material.albedo_color = Color(1.0, 0.75, 0.45, 0.6)

	if Settings.particle_effects:
		haze = MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 2.2
		cyl.bottom_radius = 1.0
		cyl.height = 1.0
		cyl.cap_top = false
		cyl.cap_bottom = false
		cyl.radial_segments = 16
		var sm := ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = HAZE_SHADER
		sm.shader = sh
		sm.render_priority = -1  # before the flame: the haze bends what is behind it, the flame glows on top
		sm.set_shader_parameter("noise", preload("res://mission/gpu_fx.gd").noise_texture())
		cyl.material = sm
		haze.mesh = cyl
		haze.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _ready() -> void:
	if haze != null:
		# Along +Z from the nozzle: radius r at the nozzle widening to 2.2 r, 8 r long.
		var length := radius * 8.0
		haze.transform = Transform3D(Basis(Vector3.RIGHT, PI / 2.0) * Basis.from_scale(Vector3(radius, length, radius)),
				nozzle + Vector3(0, 0, length * 0.5))
		get_parent().add_child.call_deferred(haze)


## True while a flame is drawn (level > 74, 'J' in FUN_004121e0).
func lit() -> bool:
	return level > 74


func _process(_delta: float) -> void:
	rebuild()


## One frame of the flame (fresh random numbers, as the original draws it every frame).
func rebuild() -> void:
	if haze != null:
		# Idle engines shimmer faintly, military power more, the afterburner most.
		var lv := clampi(level, 0, 100)
		haze.visible = lv > 30
		haze.get_active_material(0).set_shader_parameter("strength", lv / 100.0 * (1.6 if lv > 74 else 1.0))
	_mesh.clear_surfaces()
	visible = lit()
	if not visible:
		return
	var k: float = maxf((clampi(level, 0, 100) - 75) * 0.04, 0.0)
	var j := (randi() % 21 - 10) * 0.01
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material)
	for cone in CONES:
		var i: int = cone[0]
		var r: float = radius * cone[1]
		var length := (3.5 + j) * k + 1.5 * i / scale_factor
		var tip := r * (j + 0.25)
		var u0 := randf()
		for s in SEGMENTS:
			var a0 := TAU * s / SEGMENTS
			var a1 := TAU * (s + 1) / SEGMENTS
			var u_a := u0 - float(s) / SEGMENTS
			var u_b := u0 - float(s + 1) / SEGMENTS
			var b0 := nozzle + Vector3(cos(a0) * r, sin(a0) * r, 0.0)
			var b1 := nozzle + Vector3(cos(a1) * r, sin(a1) * r, 0.0)
			var t0 := nozzle + Vector3(cos(a0) * tip, sin(a0) * tip, length)
			var t1 := nozzle + Vector3(cos(a1) * tip, sin(a1) * tip, length)
			_vertex(b0, u_a, 0.9999)
			_vertex(t0, u_a, 0.0)
			_vertex(b1, u_b, 0.9999)
			_vertex(b1, u_b, 0.9999)
			_vertex(t0, u_a, 0.0)
			_vertex(t1, u_b, 0.0)
	_mesh.surface_end()


func _vertex(p: Vector3, u: float, v: float) -> void:
	_mesh.surface_set_uv(Vector2(u, v))
	_mesh.surface_add_vertex(p)
