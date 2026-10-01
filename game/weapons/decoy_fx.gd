extends Node3D
## The look of chaff and flares in the air (docs/weapons.md §10). Every rendered frame the original
## draws each live decoy by its render type (FUN_00412c60):
## - flare (model 0x753e, type 5): the missFLR.tga sprite (FUN_00411f80, size 0.8..1.2 re-rolled
##   each frame, centred, white) plus one white smoke3 puff (event 0x8400) of 0.3 s, 3.2 -> 9.6 m;
## - chaff (model 0x753f, type 6): an event 0x10004 of 20 chaff.bmp triangles (FUN_00417bb0 /
##   FUN_00417d40): from the decoy's spot, velocity (rand%15 - 7)·2 m/s per axis, spin
##   (rand%65 - 32)·0.1 rad/s per axis, start delay rand%30·0.01 s, then 3 s falling (y - 15 t²),
##   grey 220, unlit.
## Ours: the same at a fixed 30 Hz (the original's density follows its frame rate); the flare
## additive; the chaff pieces are one shader-driven MultiMesh (a ring of CAP pieces).

const Stores := preload("res://weapons/stores.gd")
const RATE := 30.0
## missFLR.tga is 64 px; sprite width = 0.2 · size · texture width (docs/damage.md §6.1).
const FLARE_W := 0.2 * 64.0
## [Animations] smokeFlare 0.25 on the 64 px smoke3 sprite; slot 7 lifetime 0.3 s.
const FLARE_SMOKE_W := 0.2 * 0.25 * 64.0
const FLARE_SMOKE_LIFE := 0.3
const CHAFF_PIECES := 20
const CHAFF_LIFE := 3.0
const CHAFF_SPEED := 2.0
const CHAFF_MAX_DELAY := 0.29
const CAP := 32768
## The piece (0x416380): one triangle, engine coordinates (z negated here), uv (0,0) (1,0) (1,1).
const PIECE := [Vector3(0.25, 0.4, 0.25), Vector3(0.6, 0.15, -0.5), Vector3(-0.15, -0.1, -0.3)]
const CHAFF_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform float now;
uniform float life;

mat3 rot(vec3 a) {
	vec3 c = cos(a);
	vec3 s = sin(a);
	mat3 rx = mat3(vec3(1, 0, 0), vec3(0, c.x, s.x), vec3(0, -s.x, c.x));
	mat3 ry = mat3(vec3(c.y, 0, -s.y), vec3(0, 1, 0), vec3(s.y, 0, c.y));
	mat3 rz = mat3(vec3(c.z, s.z, 0), vec3(-s.z, c.z, 0), vec3(0, 0, 1));
	return rz * ry * rx;
}

void vertex() {
	// INSTANCE_CUSTOM: velocity (m/s), start time; COLOR.rgb: spin (rad/s), COLOR.a: phase.
	float t = now - INSTANCE_CUSTOM.w;
	if (t < 0.0 || t > life) {
		VERTEX = vec3(0.0);
	} else {
		VERTEX = rot(COLOR.rgb * t + COLOR.a * vec3(1.0, 2.0, 3.0)) * VERTEX
			+ INSTANCE_CUSTOM.xyz * t - vec3(0.0, 15.0 * t * t, 0.0);
	}
}

void fragment() {
	ALBEDO = texture(tex, UV).rgb * (220.0 / 255.0);
}
"""

## damage_effects.gd (the flare's smoke puffs); null = no smoke.
var effects: Node
var _rng := RandomNumberGenerator.new()
var _flare_tex: Texture2D
var _flares := {}  # decoy (Dictionary) -> {node, next}
var _chaff_next := {}  # decoy -> next emission time
var _mm: MultiMesh
var _mat: ShaderMaterial
var _cursor := 0
## The live chaff bursts (time, scene position), for tests: pieces are drawn until time + 0.29 + 3.
var bursts: Array = []


func _ready() -> void:
	_flare_tex = _texture("missflr.png", "missflr.tga")
	_mat = ShaderMaterial.new()
	_mat.shader = Shader.new()
	_mat.shader.code = CHAFF_SHADER
	_mat.set_shader_parameter("tex", _texture("chaff.png", "chaff.bmp"))
	_mat.set_shader_parameter("life", CHAFF_LIFE)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 3:
		st.set_uv([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)][i])
		st.add_vertex(PIECE[i])
	var mesh := st.commit()
	mesh.surface_set_material(0, _mat)
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = true
	_mm.mesh = mesh
	_mm.instance_count = CAP
	_mm.visible_instance_count = 0
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = _mm
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The pieces move in the shader: never cull the (static) instance bounds.
	inst.custom_aabb = AABB(Vector3(-1e6, -1e6, -1e6), Vector3(2e6, 2e6, 2e6))
	add_child(inst)


## The converted sprite (assets/converted/objects, 4× Lanczos), else the install's original.
static func _texture(png: String, original: String) -> Texture2D:
	var path := Settings.assets_dir().path_join("converted/objects").path_join(png)
	if not FileAccess.file_exists(path):
		path = Settings.assets_dir().path_join("install/resource/3dobjects").path_join(original)
	var img := Image.load_from_file(path) if FileAccess.file_exists(path) else null
	if img == null:
		return null
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Advances to sim time `now`: `decoys` = the decoys released ({type, end, r: {t0, ...}}; those ended since
## the last call still emit up to their end), `pos_at(decoy, t)` = a decoy's scene position at time t.
func update(now: float, decoys: Array, pos_at: Callable) -> void:
	var step := 1.0 / RATE
	for dc in _flares.keys():
		if not dc in decoys or now >= dc.end:
			_flares[dc].node.queue_free()
			_flares.erase(dc)
	for dc in _chaff_next.keys():
		if not dc in decoys:
			_chaff_next.erase(dc)
	for dc in decoys:
		var stop: float = minf(now, dc.end)
		if dc.type == Stores.FLARE:
			if now >= dc.end:
				continue
			if not _flares.has(dc):
				_flares[dc] = {"node": _flare_node(), "next": dc.r.t0}
			var f: Dictionary = _flares[dc]
			var p: Vector3 = pos_at.call(dc, now)
			f.node.position = p
			while f.next <= stop:
				var w := FLARE_W * (0.8 + (_rng.randi() % 41) * 0.01)
				f.node.scale = Vector3(w, w, w)
				if effects != null:
					effects.smoke_puff(pos_at.call(dc, f.next), true, FLARE_SMOKE_LIFE, FLARE_SMOKE_W)
				f.next += step
		else:
			if not _chaff_next.has(dc):
				_chaff_next[dc] = dc.r.t0
			while _chaff_next[dc] <= stop:
				_burst(_chaff_next[dc], pos_at.call(dc, _chaff_next[dc]))
				_chaff_next[dc] += step
	while not bursts.is_empty() and bursts[0][0] + CHAFF_MAX_DELAY + CHAFF_LIFE < now:
		bursts.pop_front()
	_mat.set_shader_parameter("now", now)


## One chaff event 0x10004 (scale 2) at scene position `p`, time `t`.
func _burst(t: float, p: Vector3) -> void:
	bursts.append([t, p])
	for k in CHAFF_PIECES:
		var v := Vector3(_rng.randi() % 15 - 7, _rng.randi() % 15 - 7, _rng.randi() % 15 - 7) * CHAFF_SPEED
		var spin := Vector3(_rng.randi() % 65 - 32, _rng.randi() % 65 - 32, _rng.randi() % 65 - 32) * 0.1
		var delay := (_rng.randi() % 30) * 0.01
		_mm.set_instance_transform(_cursor, Transform3D(Basis.IDENTITY, p))
		_mm.set_instance_custom_data(_cursor, Color(v.x, v.y, v.z, t + delay))
		_mm.set_instance_color(_cursor, Color(spin.x, spin.y, spin.z, _rng.randf() * TAU))
		_cursor = (_cursor + 1) % CAP
		_mm.visible_instance_count = maxi(_mm.visible_instance_count, _cursor if _cursor > 0 else CAP)


func _flare_node() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	mi.mesh = q
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.albedo_texture = _flare_tex
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## Live counts, for tests: flares drawn, chaff pieces drawn at `now`.
func counts(now: float) -> Dictionary:
	var pieces := 0
	for b in bursts:
		if now >= b[0] and now <= b[0] + CHAFF_MAX_DELAY + CHAFF_LIFE:
			pieces += CHAFF_PIECES
	return {"flares": _flares.size(), "chaff": pieces}
