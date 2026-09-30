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


## True while a flame is drawn (level > 74, 'J' in FUN_004121e0).
func lit() -> bool:
	return level > 74


func _process(_delta: float) -> void:
	rebuild()


## One frame of the flame (fresh random numbers, as the original draws it every frame).
func rebuild() -> void:
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
