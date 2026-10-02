# Smoke trails (Preferences > Graphics SMOKE TRAILS, docs/damage.md §6.4): the missile / rocket trails with
# their motor glow and the wingtip vortex trails (Tgen Trails.cpp: create FUN_004156a0, addPoint
# FUN_00415890, ageing FUN_00415970, draw FUN_00415b30, glow FUN_00415a60; the owners FUN_004da090).
# One point per rendered frame of the owner; every segment is two crossed quads (one horizontal, one
# vertical) textured with a frame of trail.tga chosen by the segment's age. Positions are scene coordinates.
extends Node3D

## Trail kinds (the sprite slots of FUN_0058a420): lifetime s, half-width at the head, growth (create arg).
const MISSILE := {"life": 3.5, "size": 0.6, "growth": 0.15, "glow": true, "refill": true}
const WINGTIP := {"life": 1.0, "size": 0.1, "growth": 0.01, "glow": false, "refill": false}
## Ring of 256 points per trail (a full missile trail starts a new one, a full wingtip trail stops adding:
## the original ignores that addPoint result); at most 99 trails (createTrail refuses at count + 1 ≥ 100).
const MAX_POINTS := 256
const MAX_TRAILS := 99
## An owner not seen for more than 3 frames loses its trail (FUN_004da090), which then ages out.
const GAP_FRAMES := 3
## A trail with no points is freed after 3 s idle.
const IDLE := 3.0
## The motor glow: missFLR (64 px) at the newest point, size (0.85 + rand%31·0.01)·1.35·trail size,
## world width 0.2·size·64 (FUN_00410690), only while the trail is still growing.
const GLOW_TEX_W := 64.0

var _trails: Array = []  # {kind, pts: [[pos, age]], added, idle}
var _owners := {}  # owner key -> {trail, frame}
var _frame := 0
var _mesh: ImmediateMesh
var _glows: MultiMeshInstance3D
var _glow_list: Array = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_mesh = ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.albedo_texture = _texture("trail.png")
	mi.material_override = mat
	add_child(mi)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var quad := QuadMesh.new()
	var gm := StandardMaterial3D.new()
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	gm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	gm.albedo_texture = _texture("missflr.png")
	quad.material = gm
	mm.mesh = quad
	_glows = MultiMeshInstance3D.new()
	_glows.multimesh = mm
	_glows.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_glows)


static func _texture(name: String) -> Texture2D:
	var path: String = Engine.get_main_loop().root.get_node("Settings").assets_dir().path_join("converted/objects").path_join(name)
	var img := Image.load_from_file(path) if FileAccess.file_exists(path) else null
	return ImageTexture.create_from_image(img) if img != null else null


## The owner `key` (a missile, a wingtip) is drawn this frame with its trail head at `pos`.
func emit(key, pos: Vector3, kind: Dictionary) -> void:
	var o: Dictionary = _owners.get(key, {})
	var tr = o.get("trail")
	if tr == null or _frame - int(o.frame) > GAP_FRAMES:
		tr = null
	if tr != null and tr.pts.size() >= MAX_POINTS:
		if kind.refill:
			tr = null  # addPoint failed: a new trail
		else:
			o.frame = _frame
			return  # wingtip: stays full until it ages
	if tr == null:
		if _trails.size() + 1 >= MAX_TRAILS + 1:  # count + 1 ≥ 100
			return  # "overflow": the owner retries next frame
		tr = {"kind": kind, "pts": [], "added": false, "idle": 0.0}
		_trails.append(tr)
	tr.pts.append([pos, 0.0])
	tr.added = true
	tr.idle = 0.0
	_owners[key] = {"trail": tr, "frame": _frame}


## Live counts, for tests.
func counts() -> Dictionary:
	var n := 0
	for t in _trails:
		n += t.pts.size()
	return {"trails": _trails.size(), "points": n, "glows": _glow_list.size()}


func _process(delta: float) -> void:
	_frame += 1
	# Ageing: drop the points past the lifetime; a trail that added nothing this frame loses its glow.
	_glow_list.clear()
	for i in range(_trails.size() - 1, -1, -1):
		var tr: Dictionary = _trails[i]
		for p in tr.pts:
			p[1] += delta
		while not tr.pts.is_empty() and tr.pts[0][1] > tr.kind.life:
			tr.pts.pop_front()
		if tr.kind.glow and tr.added and not tr.pts.is_empty():
			_glow_list.append(tr.pts[-1][0])
		tr.added = false
		tr.idle += delta
		if tr.pts.is_empty() and tr.idle > IDLE:
			_trails.remove_at(i)
	for k in _owners.keys():
		if _frame - int(_owners[k].frame) > GAP_FRAMES:
			_owners.erase(k)
	_draw()


func _draw() -> void:
	_mesh.clear_surfaces()
	var any := false
	for tr in _trails:
		if tr.pts.size() >= 2:
			any = true
			break
	if any:
		_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for tr in _trails:
			_draw_trail(tr)
		_mesh.surface_end()
	var mm := _glows.multimesh
	mm.instance_count = _glow_list.size()
	for i in _glow_list.size():
		var s: float = (0.85 + (_rng.randi() % 31) * 0.01) * 1.35 * MISSILE.size
		var w: float = 0.2 * s * GLOW_TEX_W
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(w, w, w)), _glow_list[i]))


## Half-widths from the head (newest) to the tail (FUN_00415b30): w = size at the head, the newest ~15 %
## of the points widen by growth · size · 4.5 each, the older 85 % (k = ftol(0.85 · n)) taper to 0.
static func widths(n_points: int, kind: Dictionary) -> PackedFloat32Array:
	var w := PackedFloat32Array()
	w.resize(n_points)
	var n := n_points - 1
	if n_points == 0:
		return w
	var k := int(0.85 * n)
	var cur: float = kind.size
	for i in n_points:  # i = 0 is the newest point
		w[i] = cur
		if i < n - k:
			cur += kind.growth * kind.size * 4.5
		elif k > 0:
			cur -= w[n - k] / k
			cur = maxf(cur, 0.0)
	return w


func _draw_trail(tr: Dictionary) -> void:
	var pts: Array = tr.pts
	var n := pts.size()
	if n < 2:
		return
	var w := widths(n, tr.kind)
	var life: float = tr.kind.life
	# The horizontal offset of each point: perpendicular to the averaged horizontal heading of its segments.
	var side: Array = []
	side.resize(n)
	for i in n:
		var d := Vector3.ZERO
		if i > 0:
			d += pts[i][0] - pts[i - 1][0]
		if i < n - 1:
			d += pts[i + 1][0] - pts[i][0]
		var h := Vector2(d.x, d.z)
		side[i] = Vector3(-h.y, 0, h.x).normalized() if h.length() > 1e-4 else Vector3.RIGHT
	for i in range(n - 1):  # segment from the older point i to the newer i + 1
		var a: Vector3 = pts[i][0]
		var b: Vector3 = pts[i + 1][0]
		var wa: float = w[n - 1 - i]
		var wb: float = w[n - 2 - i]
		var f: int = int(4.0 * minf(pts[i + 1][1] / life, 0.9999))
		var v0 := f * 0.25
		var v1 := v0 + 0.25
		_quad(a, b, side[i] * wa, side[i + 1] * wb, v0, v1)
		_quad(a, b, Vector3.UP * wa, Vector3.UP * wb, v0, v1)


func _quad(a: Vector3, b: Vector3, oa: Vector3, ob: Vector3, v0: float, v1: float) -> void:
	var p := [a - oa, a + oa, b + ob, b - ob]
	var uv := [Vector2(0, v0), Vector2(0, v1), Vector2(1, v1), Vector2(1, v0)]
	for idx in [0, 1, 2, 0, 2, 3]:
		_mesh.surface_set_uv(uv[idx])
		_mesh.surface_add_vertex(p[idx])
