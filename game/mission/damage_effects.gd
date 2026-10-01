# Explosions, debris and smoke of destroyed / damaged units (docs/damage.md §6). Timing, sizes,
# speeds and counts are the original's (the Tgen explosion object FUN_00416880 and its per-flag
# updates, the class switch FUN_0059df20, the damage-smoke emitter FUN_004d20a0); the drawing is
# ours: soft procedural billboards in one MultiMesh per material instead of the 1998 sprite strips
# (airexp1 / smoke3), and a short light for the one-frame lens flash.
# Positions are Godot scene coordinates (metres, Y up).
extends Node3D

## Explosion flag bits (FUN_00416880 / FUN_00416a70, docs/damage.md §6.1).
const F_SHATTER := 0x2
const F_SMOKE_TRAILS := 0x8
const F_FIREBALL := 0x10
const F_BURN_PIECES := 0x20
const F_NO_DELAY := 0x40
const F_KICK := 0x80
const F_PUFF := 0x100
const F_WHITE := 0x400
const F_COLUMN := 0x800
const F_REST := 0x1000
const F_CLUSTER := 0x2000
const F_FLASH := 0x4000
const F_SMALL_FIRE := 0x10000000

## World size of a sprite: full width = 0.2 · size · texture width (FUN_00410690; UNCERTAIN, see
## docs/damage.md §6.1): AirExp1 (128 px, size 10) and smoke3 (64 px, size 1).
const FIREBALL_WIDTH := 0.2 * 10.0 * 128.0
const SMALL_FIRE_WIDTH := FIREBALL_WIDTH * 0.15
const SMOKE_WIDTH := 0.2 * 1.0 * 64.0
const FIREBALL_TIME := 1.2
const PUFF_TIME := 2.5
## Gravity of pieces and streamers: z -= 15 t² (g = 30 world units / s²).
const PIECE_G := 30.0
## Smoke column (FUN_00416ed0): 33 / (4 - detail) puffs, one every 1.6 s, visible from 0.3 s until
## 36 / (4 - detail) s. The detail setting's default is not traced: the highest (3) is used.
const COLUMN_DETAIL := 3
## Puff emitters (damage smoke, smoking pieces, streamers) spawn one puff per rendered frame in the
## original, so the density follows the frame rate; here a fixed 30 Hz "frame" (our choice).
const PUFF_RATE := 30.0
## Shatter: one piece per model polygon (FUN_004172b0). Without a model (tests), box chunks.
const PIECES := 24
## Our models are triangulated (and subdivided by --smooth): above this many triangles, neighbouring
## triangles (consecutive in the index list) fly together as one piece.
const MAX_MODEL_PIECES := 600
## A "large" piece (smoke trail, may flare) is an original polygon of more than 6 vertices; our
## triangles don't keep that, so the largest pieces by area, this share of them, count as large.
const LARGE_SHARE := 0.1
const SHATTER_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform float age;
uniform float g = 30.0;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool has_tex = false;
uniform vec4 albedo : source_color = vec4(1.0);
varying float hide;
mat3 rot(vec3 a) {
	vec3 c = cos(a), s = sin(a);
	mat3 rx = mat3(vec3(1, 0, 0), vec3(0, c.x, s.x), vec3(0, -s.x, c.x));
	mat3 ry = mat3(vec3(c.y, 0, -s.y), vec3(0, 1, 0), vec3(s.y, 0, c.y));
	mat3 rz = mat3(vec3(c.z, s.z, 0), vec3(-s.z, c.z, 0), vec3(0, 0, 1));
	return rz * ry * rx;
}
void vertex() {
	// CUSTOM0 = centre (xyz) + start delay, CUSTOM1 = velocity + stop time, CUSTOM2 = spin + end time.
	float t = age - CUSTOM0.w;
	hide = (t < 0.0 || t > CUSTOM2.w) ? 1.0 : 0.0;
	float tf = clamp(t, 0.0, CUSTOM1.w);
	mat3 r = rot(CUSTOM2.xyz * tf);
	VERTEX = CUSTOM0.xyz + CUSTOM1.xyz * tf + vec3(0.0, -0.5 * g * tf * tf, 0.0) + r * VERTEX;
	NORMAL = r * NORMAL;
}
void fragment() {
	if (hide > 0.5) { discard; }
	vec4 c = albedo;
	if (has_tex) { c *= texture(tex, UV); }
	if (c.a < 0.5) { discard; }
	ALBEDO = c.rgb;
}
"""

var _rng := RandomNumberGenerator.new()
## Live puffs: {pos, vel, age, life, w0, w1 (width at birth / death), grey, fire, delay}.
var _puffs: Array = []
var _pieces: Array = []  # {node, vel, spin, age, life, rest, ground_y, large, delay, smoke_t}
## Model shatters: {node, materials, age, end, large: [{c, vel, delay, stop, end, burn_t, smoke_t}], smoke, burn}
var _shards: Array = []
var _shard_shader: Shader
var _streamers: Array = []
var _columns: Array = []  # {pos, age, n, end}
var _clusters: Array = []  # {age, end, subs: [{pos, delay, column, done}]}
var _smokers := {}  # Node3D -> accumulated time (damage smoke, FUN_004d20a0)
var _mm_smoke: MultiMeshInstance3D
var _mm_fire: MultiMeshInstance3D
## Terrain height at a scene position (null when unknown), supplied by the host.
var ground_at: Callable


func _ready() -> void:
	_mm_smoke = _make_layer(false)
	_mm_fire = _make_layer(true)


func _make_layer(fire: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var quad := QuadMesh.new()
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _soft_texture(fire)
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	if fire:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	quad.material = mat
	mm.mesh = quad
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(inst)
	return inst


## A soft round sprite (smoke: grey noise-free blob; fire: hot core).
static func _soft_texture(fire: bool) -> Texture2D:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(x - n / 2.0 + 0.5, y - n / 2.0 + 0.5).length() / (n / 2.0)
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)
			if fire:
				img.set_pixel(x, y, Color(1.0, lerpf(0.35, 0.95, a), lerpf(0.05, 0.6, a * a), a))
			else:
				img.set_pixel(x, y, Color(1, 1, 1, a * 0.85))
	return ImageTexture.create_from_image(img)


# --- the explosion object (FUN_00416880) ---------------------------------------------------------

## What a destroyed unit's explosion looks like (FUN_0059df20) by unit class, bdb type code (0x5b4)
## and where it is: `low` = below ground + 10.5 m (0x6119ec), `water` = terrain type 1 / 2 (our
## terrain has no types: never). Returns {flags, scale, duration} ({} = none); the constructor's
## scale 4 and the event duration 95 s unless the class says otherwise. Aircraft low on land also
## place a crater 1 s later (CreateCraterEv; the pool of class-0x1f objects is empty in the shipped
## data). The sound is SFX_AIRCRAFT_EXPLODED for every unit class (code 0x11).
static func explosion_for(klass: int, type_code: int, low: bool, water: bool) -> Dictionary:
	var e := {"flags": 0, "scale": 4.0, "duration": 95.0}
	match klass:
		1, 2, 3, 0x1c:
			e.flags = (0x640ba if water else 0x58ba) if low else 0x407a
		5, 10:
			e.flags = 0x58ba
		6, 8, 9, 0xb:
			e.flags = 0x188a
		0xc, 0xd:
			if type_code == 410:
				e.flags = 0x4810
			elif type_code == 420:
				e.flags = 0x1892
				e.scale = 2.0
			else:
				e.flags = 0x800
		0xf, 0x10:
			e.flags = 0x640ba
			e.scale = 1.5
		_:
			return {}
	return e


## One explosion event at `pos`: `flags` as above, `scale` (param[7]), `duration` (param[6], the
## lifetime of the whole event), `ground_y` = terrain height under it, `radius` = the unit's size
## (the shatter pieces start within it).
func explosion(pos: Vector3, flags: int, scale: float, duration: float, ground_y: float, radius := 6.0,
		model: Node3D = null) -> void:
	if flags & F_FLASH:
		_flash(pos)
	if flags & F_FIREBALL:
		_add_puff(pos, Vector3.ZERO, FIREBALL_TIME, FIREBALL_WIDTH, FIREBALL_WIDTH, 250, true, 0.0, true)
	if flags & F_SMALL_FIRE:
		_add_puff(pos, Vector3.ZERO, FIREBALL_TIME, SMALL_FIRE_WIDTH, SMALL_FIRE_WIDTH, 250, true, 0.0, true)
	if flags & F_PUFF:
		smoke_puff(pos, flags & F_WHITE != 0)
	if flags & F_SHATTER:
		if model == null or not _shatter_model(model, pos, flags, scale, duration, ground_y):
			_shatter(pos, flags, scale, duration, ground_y, radius)
	elif flags & F_SMOKE_TRAILS:
		_streamers_at(pos, scale)
	if flags & F_COLUMN:
		_columns.append({"pos": pos, "age": 0.0, "n": 33 / (4 - COLUMN_DETAIL), "born": 0, "end": duration})
	if flags & F_CLUSTER:
		_cluster(pos, radius, duration)


## 0x2000 (FUN_00418000 / FUN_004181c0): 48 sub-bursts in 3 rings of 16, 10 m below the burst; ring
## radius r = max(radius, 5)·0.65^k, each burst at r ± a jitter of 0.15·r (rand % 2j + r − j), the
## angle stepping −π/8 (−π/16 more per ring); each goes off after (rand & 7)·0.1 s as a small fire,
## every second one with a 5 s smoke column; the bursts end with the event (age / duration ≥ 1).
func _cluster(pos: Vector3, radius: float, duration: float) -> void:
	var subs := []
	var r := maxf(radius, 5.0)
	var a := 0.0
	for ring in 3:
		var j := maxi(int(r * 0.15), 1)
		for k in 16:
			var d := float(_rng.randi() % (2 * j)) + r - float(j)
			subs.append({"pos": pos + Vector3(cos(a) * d, -10.0, -sin(a) * d), "delay": float(_rng.randi() & 7) * 0.1,
				"column": subs.size() % 2 == 1, "done": false})
			a -= PI / 8.0
		r *= 0.65
		a -= PI / 16.0
	_clusters.append({"age": 0.0, "end": duration, "subs": subs})


func _update_clusters(delta: float) -> void:
	for c in _clusters.duplicate():
		c.age += delta
		for b in c.subs:
			if not b.done and c.age > b.delay:
				b.done = true
				_add_puff(b.pos, Vector3.ZERO, FIREBALL_TIME, SMALL_FIRE_WIDTH, SMALL_FIRE_WIDTH, 250, true, 0.0, true)
				if b.column:
					_columns.append({"pos": b.pos, "age": 0.0, "n": 33 / (4 - COLUMN_DETAIL), "born": 0, "end": 5.0})
		if c.age >= c.end or c.subs.all(func(b): return b.done):
			_clusters.erase(c)


## 0x100: smoke3 puff, 2.5 s, width 1x -> 3x, grey 40 (0x400: white), rising 5.6..10.1 m/s with
## ±2.4 m/s sideways jitter (no wind: the mission weather is not decoded). The flare's smoke (0x8000,
## docs/weapons.md §10) is the same puff with its own `life` and start `width`.
func smoke_puff(pos: Vector3, white := false, life := PUFF_TIME, width := SMOKE_WIDTH) -> void:
	var v := Vector3((_rng.randi() & 15) - 8, 8.0 + ((_rng.randi() & 15) - 8) * 0.3, (_rng.randi() & 15) - 8)
	v.x *= 0.3
	v.z *= 0.3
	_add_puff(pos, v, life, width, width * 3.0, 255 if white else 40, false, 0.0, true)


func _add_puff(pos: Vector3, vel: Vector3, life: float, w0: float, w1: float, grey: int, fire: bool, delay: float,
		bottom: bool) -> void:
	_puffs.append({"pos": pos, "vel": vel, "age": 0.0, "life": life, "w0": w0, "w1": w1, "grey": grey,
			"fire": fire, "delay": delay, "bottom": bottom})


## 0x4000: the lens flash, drawn for one frame in the original; a 0.1 s light here.
func _flash(pos: Vector3) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.85, 0.6)
	l.light_energy = 16.0
	l.omni_range = 600.0
	add_child(l)
	l.position = pos
	var t := create_tween()
	t.tween_property(l, "light_energy", 0.0, 0.1)
	t.tween_callback(l.queue_free)


## 0x2: the model shatters (FUN_004172b0 / FUN_00417610): each piece flies at
## (offset + base) · k · scale, k in {0.5, 1, 1.5}, base = 5 up with 0x80; spin up to ±0.96 rad/s;
## g = 30; life (1 + rand%100·0.01) · duration · 0.5; start delay 0..0.3 s unless 0x40. With 0x1000
## pieces come to rest at the origin altitude - 0.5 and lie there (ours: on the terrain under each
## piece, so a crash up to 10.5 m above the ground or on a slope leaves no pieces in the air), else
## they vanish at the ground.
## With 0x8 large flying pieces trail smoke; with 0x20 they may flare into a small fire (1/32 per
## frame) and vanish.
func _shatter(pos: Vector3, flags: int, scale: float, duration: float, ground_y: float, radius: float) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.15, 0.14)
	for i in PIECES:
		# A polygon's position in the model: a random point within the unit's size (ours).
		var off := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.25, 0.4), _rng.randf_range(-1, 1)) * radius
		var base := Vector3(0, 5.0, 0) if flags & F_KICK else Vector3.ZERO
		var k: float = [0.5, 1.0, 1.5][_rng.randi() % 3]
		var box := BoxMesh.new()
		box.size = Vector3(_rng.randf_range(0.4, 2.0), _rng.randf_range(0.1, 0.5), _rng.randf_range(0.4, 2.0))
		box.material = mat
		var node := MeshInstance3D.new()
		node.mesh = box
		node.position = pos + off
		node.visible = flags & F_NO_DELAY != 0
		add_child(node)
		_pieces.append({
			"node": node, "vel": (off + base) * k * scale,
			"spin": Vector3((_rng.randi() & 63) - 32, (_rng.randi() & 63) - 32, (_rng.randi() & 63) - 32) * 0.03,
			"age": 0.0, "life": (1.0 + (_rng.randi() % 100) * 0.01) * duration * 0.5,
			"delay": 0.0 if flags & F_NO_DELAY else (_rng.randi() % 100) * 0.003,
			"rest": flags & F_REST != 0, "ground_y": ground_y,
			"large": i % 3 == 0, "smoke": flags & F_SMOKE_TRAILS != 0, "burn": flags & F_BURN_PIECES != 0,
			"smoke_t": 0.0, "resting": false,
		})


## 0x2 with the unit's model (FUN_004172b0): one piece per polygon, starting where it is drawn. Its
## velocity is (centre in the model frame, rotated with the unit, + base) · k · scale with the other
## rules as `_shatter`; the original's "large" polygons (> 6 vertices) are our largest by area. All
## pieces of one material are one mesh moved by a shader (CUSTOM0..2 per piece); the CPU solves when
## each piece reaches the terrain (rest there with 0x1000, else vanish) and runs the large pieces'
## smoke and fire. Returns false when the model has no triangles.
func _shatter_model(model: Node3D, pos: Vector3, flags: int, scale: float, duration: float, ground_y: float) -> bool:
	var root_inv := model.global_transform.affine_inverse()
	var basis := model.global_transform.basis.orthonormalized()
	var base := Vector3(0, 5.0, 0) if flags & F_KICK else Vector3.ZERO
	var groups := {}  # material -> {v, n, uv, c0, c1, c2}
	var all: Array = []  # [area, centre, vel, delay, stop, end]
	var tris := 0
	var meshes: Array = model.find_children("*", "MeshInstance3D", true, false)
	if model is MeshInstance3D:
		meshes.append(model)
	# Only array meshes (the model's polygons): an ImmediateMesh (e.g. the jet's drawn lines) has none.
	meshes = meshes.filter(func(mi): return mi.mesh is ArrayMesh)
	for mi in meshes:
		if _shown_in(mi, model):
			for si in mi.mesh.get_surface_count():
				if mi.mesh.surface_get_primitive_type(si) == Mesh.PRIMITIVE_TRIANGLES:
					var ix = mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_INDEX]
					tris += (ix.size() if ix != null else mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX].size()) / 3
	if tris == 0:
		return false
	var per := ceili(float(tris) / MAX_MODEL_PIECES)
	if _shard_shader == null:
		_shard_shader = Shader.new()
		_shard_shader.code = SHATTER_SHADER
	for mi in meshes:
		if mi.mesh == null or not _shown_in(mi, model):
			continue
		var xf: Transform3D = mi.global_transform
		for si in mi.mesh.get_surface_count():
			if mi.mesh.surface_get_primitive_type(si) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var a: Array = mi.mesh.surface_get_arrays(si)
			var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var ns = a[Mesh.ARRAY_NORMAL]
			var uvs = a[Mesh.ARRAY_TEX_UV]
			var ix = a[Mesh.ARRAY_INDEX]
			if ix == null:
				ix = PackedInt32Array(range(vs.size()))
			var mat: Material = mi.get_active_material(si)
			if not groups.has(mat):
				groups[mat] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(),
						"c0": PackedFloat32Array(), "c1": PackedFloat32Array(), "c2": PackedFloat32Array()}
			var g: Dictionary = groups[mat]
			var t := 0
			while t < ix.size() / 3:
				var n_t := mini(per, ix.size() / 3 - t)
				var wv: Array = []
				var c := Vector3.ZERO
				var area := 0.0
				for k in n_t * 3:
					var w: Vector3 = xf * vs[ix[(t * 3) + k]]
					wv.append(w)
					c += w
				c /= wv.size()
				for k in n_t:
					area += (wv[k * 3 + 1] - wv[k * 3]).cross(wv[k * 3 + 2] - wv[k * 3]).length() * 0.5
				var kk: float = [0.5, 1.0, 1.5][_rng.randi() % 3]
				var vel: Vector3 = (basis * (root_inv * c) + base) * kk * scale
				var delay := 0.0 if flags & F_NO_DELAY else (_rng.randi() % 100) * 0.003
				var life := (1.0 + (_rng.randi() % 100) * 0.01) * duration * 0.5
				var stop := _ground_time(c, vel, life, ground_y)
				var end := life if (flags & F_REST and stop < life) else minf(stop, life)
				var spin := Vector3((_rng.randi() & 63) - 32, (_rng.randi() & 63) - 32, (_rng.randi() & 63) - 32) * 0.03
				var rel := c - pos
				for k in n_t * 3:
					var vi: int = ix[(t * 3) + k]
					g.v.append(wv[k] - c)
					g.n.append((xf.basis * ns[vi]).normalized() if ns != null else Vector3.UP)
					g.uv.append(uvs[vi] if uvs != null else Vector2.ZERO)
					g.c0.append_array([rel.x, rel.y, rel.z, delay])
					g.c1.append_array([vel.x, vel.y, vel.z, stop])
					g.c2.append_array([spin.x, spin.y, spin.z, end])
				all.append([area, c, vel, delay, stop, end])
				t += n_t
	var node := MeshInstance3D.new()
	var mesh := ArrayMesh.new()
	var fmt: int = Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT \
			| Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT \
			| Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT
	var mats: Array = []
	for mat in groups:
		var g: Dictionary = groups[mat]
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = g.v
		arr[Mesh.ARRAY_NORMAL] = g.n
		arr[Mesh.ARRAY_TEX_UV] = g.uv
		arr[Mesh.ARRAY_CUSTOM0] = g.c0
		arr[Mesh.ARRAY_CUSTOM1] = g.c1
		arr[Mesh.ARRAY_CUSTOM2] = g.c2
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, fmt)
		var sm := ShaderMaterial.new()
		sm.shader = _shard_shader
		if mat is BaseMaterial3D:
			sm.set_shader_parameter("albedo", mat.albedo_color)
			if mat.albedo_texture != null:
				sm.set_shader_parameter("tex", mat.albedo_texture)
				sm.set_shader_parameter("has_tex", true)
		mesh.surface_set_material(mesh.get_surface_count() - 1, sm)
		mats.append(sm)
	node.mesh = mesh
	node.position = pos
	node.extra_cull_margin = 16384.0  # the vertices move in the shader
	add_child(node)
	# The largest pieces trail smoke (0x8) and may flare into a small fire and vanish (0x20).
	all.sort_custom(func(x, y): return x[0] > y[0])
	var large: Array = []
	for i in ceili(all.size() * LARGE_SHARE):
		var e: Array = all[i]
		large.append({"c": e[1], "vel": e[2], "delay": e[3], "stop": e[4], "end": e[5], "smoke_t": 0.0, "burnt": false})
	var last := 0.0
	for e in all:
		last = maxf(last, e[3] + e[5])
	_shards.append({"node": node, "mats": mats, "age": 0.0, "last": last, "large": large,
			"smoke": flags & F_SMOKE_TRAILS != 0, "burn": flags & F_BURN_PIECES != 0})
	return true


## `mi` is drawn as part of `model` (its own and its parents' visibility below the model; the model
## itself may be hidden, e.g. the player's jet in the cockpit view).
static func _shown_in(mi: Node3D, model: Node3D) -> bool:
	var n: Node = mi
	while n != null and n != model:
		if n is Node3D and not n.visible:
			return false
		n = n.get_parent()
	return true


## When a piece from `c` at `vel` (g = 30) reaches the terrain: the ballistic time to the height under
## its landing point, refined three times; `life` when it never does.
func _ground_time(c: Vector3, vel: Vector3, life: float, ground_y: float) -> float:
	var h := ground_y
	var t := life
	for i in 3:
		# c.y + vel.y t - 15 t² = h
		var disc := vel.y * vel.y + 2.0 * PIECE_G * (c.y - h)
		if disc < 0.0:
			return life
		t = (vel.y + sqrt(disc)) / PIECE_G
		if ground_at.is_valid():
			var p := c + vel * t
			var gh = ground_at.call(Vector3(p.x, c.y, p.z))
			if gh != null:
				h = gh
	return minf(t, life)


func _update_shards(delta: float, step: float) -> void:
	for i in range(_shards.size() - 1, -1, -1):
		var s: Dictionary = _shards[i]
		s.age += delta
		if s.age > s.last:
			s.node.queue_free()
			_shards.remove_at(i)
			continue
		for m in s.mats:
			m.set_shader_parameter("age", s.age)
		for p in s.large:
			var t: float = s.age - p.delay
			if p.burnt or t < 0.0 or t > minf(p.stop, p.end):
				continue
			p.smoke_t += delta
			while p.smoke_t >= step:
				p.smoke_t -= step
				var at: Vector3 = p.c + p.vel * t + Vector3(0, -0.5 * PIECE_G * t * t, 0)
				if s.smoke:
					smoke_puff(at)
				if s.burn and _rng.randi() % 32 == 0:
					_add_puff(at, Vector3.ZERO, FIREBALL_TIME, SMALL_FIRE_WIDTH, SMALL_FIRE_WIDTH, 250, true, 0.0, true)
					p.burnt = true
					break


## 0x8 without 0x2 (FUN_004182e0): 12 smoke streamers every 30°, 5·scale sideways and 3·scale up,
## g = 30, each trailing puffs until it drops 1 m below the origin; then a 9 s smoke column.
func _streamers_at(pos: Vector3, scale: float) -> void:
	var s := {"pos": pos, "items": [], "t": 0.0}
	for i in 12:
		var a := deg_to_rad(30.0 * i)
		s.items.append({"p": pos - Vector3(0, 0.5, 0), "v": Vector3(cos(a) * 5.0 * scale, 3.0 * scale, sin(a) * 5.0 * scale), "on": true})
	_streamers.append(s)


# --- damage smoke (FUN_004d1f90 / FUN_004d20a0) --------------------------------------------------

## Start / stop the damage smoke of a unit: one 0x100 puff per frame at the unit.
func set_smoke(node: Node3D, on: bool) -> void:
	if node == null:
		return
	if on:
		_smokers[node] = 0.0
	else:
		_smokers.erase(node)


func _process(delta: float) -> void:
	var step := 1.0 / PUFF_RATE
	for node in _smokers.keys():
		if not is_instance_valid(node):
			_smokers.erase(node)
			continue
		_smokers[node] += delta
		while _smokers[node] >= step:
			_smokers[node] -= step
			smoke_puff(node.global_position)
	_update_pieces(delta, step)
	_update_shards(delta, step)
	_update_streamers(delta, step)
	_update_clusters(delta)
	_update_columns(delta)
	_update_puffs(delta)


func _update_pieces(delta: float, step: float) -> void:
	for i in range(_pieces.size() - 1, -1, -1):
		var p: Dictionary = _pieces[i]
		var node: MeshInstance3D = p.node
		p.age += delta
		if p.age < p.delay:
			continue
		node.visible = true
		if p.age > p.life:
			node.queue_free()
			_pieces.remove_at(i)
			continue
		if p.resting:
			continue
		p.vel.y -= PIECE_G * delta
		node.position += p.vel * delta
		node.rotation += p.spin * delta
		var g: float = p.ground_y
		if ground_at.is_valid():
			var h = ground_at.call(node.position)
			if h != null:
				g = h
		if node.position.y <= g and p.rest:
			node.position.y = g
			p.resting = true
			continue
		if node.position.y <= g:
			node.queue_free()
			_pieces.remove_at(i)
			continue
		if p.large:
			p.smoke_t += delta
			while p.smoke_t >= step:
				p.smoke_t -= step
				if p.smoke:
					smoke_puff(node.position)
				if p.burn and _rng.randi() % 32 == 0:
					_add_puff(node.position, Vector3.ZERO, FIREBALL_TIME, SMALL_FIRE_WIDTH, SMALL_FIRE_WIDTH, 250, true, 0.0, true)
					p.age = p.life + 1.0


func _update_streamers(delta: float, step: float) -> void:
	for i in range(_streamers.size() - 1, -1, -1):
		var s: Dictionary = _streamers[i]
		s.t += delta
		var live := false
		for it in s.items:
			if not it.on:
				continue
			it.v.y -= PIECE_G * delta
			it.p += it.v * delta
			if it.p.y < s.pos.y - 1.0 or s.t > 30.0:
				it.on = false
				continue
			live = true
		while s.t >= step and live:
			s.t -= step
			for it in s.items:
				if it.on:
					smoke_puff(it.p)
		if not live:
			_columns.append({"pos": s.pos, "age": 0.0, "n": 33 / (4 - COLUMN_DETAIL), "born": 0, "end": 9.0})
			_streamers.remove_at(i)


## 0x800 column (FUN_00417000): puff i is born at i·1.6 s, rises 2.5..5.8 m/s with ±1.5 m/s
## sideways, is visible from 0.3 s to 36/(4 - detail) s, width 12.8 m · (1 + 0.32·age), grey 10..79.
func _update_columns(delta: float) -> void:
	for i in range(_columns.size() - 1, -1, -1):
		var c: Dictionary = _columns[i]
		c.age += delta
		while c.born < c.n and c.age >= c.born * 1.6 and c.born * 1.6 < c.end:
			var v := Vector3((_rng.randi() % 10 - 5) * 0.3, 4.0 + (_rng.randi() % 12 - 5) * 0.3, (_rng.randi() % 10 - 5) * 0.3)
			var life := minf(36.0 / (4 - COLUMN_DETAIL), c.end - c.born * 1.6)
			_add_puff(c.pos, v, life, SMOKE_WIDTH, SMOKE_WIDTH * (1.0 + 0.32 * life), 10 + _rng.randi() % 70, false, 0.3, true)
			c.born += 1
		if c.born >= c.n or c.age >= c.end:
			_columns.remove_at(i)


func _update_puffs(delta: float) -> void:
	var smoke: Array = []
	var fire: Array = []
	for i in range(_puffs.size() - 1, -1, -1):
		var p: Dictionary = _puffs[i]
		p.age += delta
		if p.age >= p.life:
			_puffs.remove_at(i)
			continue
		p.pos += p.vel * delta
		if p.age < p.delay:
			continue
		(fire if p.fire else smoke).append(p)
	_fill(_mm_smoke.multimesh, smoke)
	_fill(_mm_fire.multimesh, fire)


func _fill(mm: MultiMesh, list: Array) -> void:
	mm.instance_count = list.size()
	for i in list.size():
		var p: Dictionary = list[i]
		var f: float = p.age / p.life
		var w: float = lerpf(p.w0, p.w1, f)
		# Bottom-anchored sprites (the quad rises by its height above the point).
		var at: Vector3 = p.pos + Vector3(0, w * 0.5 if p.bottom else 0.0, 0)
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(w, w, w)), at))
		var g: float = p.grey / 255.0
		var a := 1.0 - f if p.fire else clampf(1.0 - f * f, 0.0, 1.0)
		mm.set_instance_color(i, Color(g, g, g, a) if not p.fire else Color(1, 1, 1, a))


## Live counts, for tests.
func counts() -> Dictionary:
	return {"puffs": _puffs.size(), "pieces": _pieces.size(), "shards": _shards.size(), "columns": _columns.size(), "smokers": _smokers.size(), "clusters": _clusters.size()}
