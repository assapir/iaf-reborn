# Night lights = Detailed (docs/rendering.md §5, docs/deviations.md §2): the lights of every airbase at night, built
# from the Detailed airbases' data (airbases.gd: the runways, iaf.ibx's taxi paths, the paved-surface mask; §7).
# - Runway edge lights every 60 m, white, yellow over the last 600 m of the rollout; red between a displaced
#   threshold and the pavement's end. Threshold bar green toward the approach, end bar red toward the runway.
# - An approach light system (900 m of 5-light barrettes, a crossbar at 300 m) and a PAPI at each end.
# - Taxiway edge lights, blue, along the taxi paths.
# - Apron floodlights: masts on the wide paved areas off the runways (the mask's aprons and shelter areas; none at the
#   bases only in the coarse art: Inshas, Ryak, Aman), a sodium lamp head and a pool of light on the ground under
#   each (SpotLight3D, no shadows, at most MAX_MASTS per base, faded out by FADE_FAR m).
# The lights are glow points (night_lights.gd GLOW_SHADER, the light sets' material: no new shader). The three home
# bases whose original light set (lt_rmn_h, lt_tnf_h, lt_dvd_h) is in the mission keep that set for the runway and
# taxiway edges; they get the rest. Each base is built once the terrain under it has loaded (its heights).
extends Node3D

const NightLights := preload("res://terrain/night_lights.gd")
const Airbases := preload("res://terrain/airbases.gd")

const EDGE_STEP := 60.0
const CAUTION := 600.0
const BAR_STEP := 3.0
const APPROACH := 900.0
const APPROACH_STEP := 30.0
const TAXI_STEP := 30.0
const TAXI_HALF := 12.0
## PAPI: 300 m past the threshold, the inner unit 15 m outside the edge, 9 m apart; their angles inner to outer.
const PAPI_IN := 300.0
const PAPI_OUT := 15.0
const PAPI_GAP := 9.0
const PAPI_DEG := [3.5, 3.17, 2.83, 2.5]
## Apron floodlight masts: lamp height, spacing, count per base, the pool's cone.
const MAST_H := 25.0
const MAST_GAP := 90.0
const MAX_MASTS := 24
const POOL_ANGLE := 70.0
const POOL_RANGE := 100.0
const POOL_ENERGY := 16.0
const FADE_FAR := 3000.0
## High-pressure sodium.
const SODIUM := Color(1.0, 0.66, 0.32)
const WHITE := Color(1.0, 0.93, 0.8)
const YELLOW := Color(1.0, 0.75, 0.15)
const GREEN := Color(0.15, 1.0, 0.4)
const RED := Color(1.0, 0.12, 0.06)
const BLUE := Color(0.2, 0.4, 1.0)
## The home bases' original light sets (night_lights.gd BASE_LIGHTS) by airbases.json name.
const ORIGINAL_SETS := ["Ramon", "TelNof", "David"]
## A base is built when the camera is this near (its terrain heights are loaded).
const BUILD_RANGE := 30000.0

var _tv: Node
var _bases := []
var _v := PackedVector3Array()
var _c := PackedColorArray()
var _poll := 0.0


## Every base's lights for the flight scene `tv` (terrain_view.gd).
func setup(tv: Node) -> void:
	_tv = tv
	name = "AirbaseLights"
	var sets := _original_sets(tv)
	for b: Dictionary in Airbases.bases():
		var c := Airbases.centre(b)
		var own := String(b.name) in ORIGINAL_SETS and sets.any(func(p): return c.distance_to(p) < 2500.0)
		var mi := MeshInstance3D.new()
		mi.material_override = NightLights.glow()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_bases.append({"b": b, "full": not own, "mesh": mi, "state": 0})


## The engine-metre spots of the original runway light sets in the mission (mission units and BaseLights).
static func _original_sets(tv: Node) -> Array:
	var out := []
	if tv.runtime != null:
		for e in tv.runtime.entities.values():
			if e.get("light_set", false):
				out.append(Vector2(e.world.x, e.world.y))
	for n: Node3D in tv.find_children("BaseLights*", "Node3D", false, false):
		var w: Vector3 = tv.scene_to_world(n.position)
		out.append(Vector2(w.x, w.y))
	return out


func _process(delta: float) -> void:
	_poll -= delta
	var cam := get_viewport().get_camera_3d()
	if _poll > 0.0 or cam == null or not is_visible_in_tree():
		return
	_poll = 0.5
	var o: Vector2 = _tv.terrain.world_origin
	for i in _bases.size():
		var e: Dictionary = _bases[i]
		if e.state != 0:
			continue
		var c := _scene(Airbases.centre(e.b), o)
		if Vector2(c.x, c.z).distance_to(Vector2(cam.global_position.x, cam.global_position.z)) > BUILD_RANGE:
			continue
		if _tv.terrain.height_at(c) == null:
			continue
		e.state = 1
		var b: Dictionary = e.b
		var path := Settings.assets_dir().path_join("converted/terrain").path_join(
			String(b.get("mask", {}).get("file", ""))
		)
		WorkerThreadPool.add_task(func(): _built.call_deferred(i, masts(b, path)))


## Engine metres → the scene (y 0).
static func _scene(p: Vector2, o: Vector2) -> Vector3:
	return Vector3(p.x - o.x, 0.0, -(p.y - o.y))


## The game point (the 1998 base) → engine metres: World scale Real moves a base (mask_affine maps back).
static func _from_game(b: Dictionary, g: Vector2) -> Vector2:
	if not b.has("mask_affine"):
		return g
	var a: PackedFloat64Array = b.mask_affine
	var t := Transform2D(Vector2(a[0], a[3]), Vector2(a[1], a[4]), Vector2(a[2], a[5]))
	return t.affine_inverse() * g


static func _to_game(b: Dictionary, p: Vector2) -> Vector2:
	if not b.has("mask_affine"):
		return p
	var a: PackedFloat64Array = b.mask_affine
	return Transform2D(Vector2(a[0], a[3]), Vector2(a[1], a[4]), Vector2(a[2], a[5])) * p


## The apron floodlight masts of base `b` (engine metres; a worker thread), its mask at `path`: the mask's paved
## coverage averaged over 16 × 16 pixels (≈ 40 m cells); a cell whose 3 × 3 cells are mostly paved and that lies off the
## runways is apron (taxiways are too narrow to fill them). Masts MAST_GAP apart, the most solidly paved cells first.
static func masts(b: Dictionary, path: String) -> Array:
	var m: Dictionary = b.get("mask", {})
	# A base only in the coarse art has the AI's 3000 m stand-in runway, and its mask is the art's grey blocks.
	if m.is_empty() or not FileAccess.file_exists(path) or b.runways.any(func(r): return r.get("length") == 3000.0):
		return []
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return []
	img.convert(Image.FORMAT_R8)
	var w := img.get_width() / 16
	var h := img.get_height() / 16
	var cell := float(m.px_m) * float(img.get_width()) / w
	img.resize(w, h, Image.INTERPOLATE_TRILINEAR)
	var px := img.get_data()
	var rws := []
	for r in b.runways:
		var e0 := _to_game(b, Vector2(r.ends[0][0], r.ends[0][1]))
		var e1 := _to_game(b, Vector2(r.ends[1][0], r.ends[1][1]))
		var ext := (e1 - e0).normalized() * 200.0  # and the turn pads past the ends
		rws.append([e0 - ext, e1 + ext, float(r.width) * 0.5 + 80.0])
	var cand := []
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			if px[y * w + x] < 205:
				continue
			var sum := 0
			var low := 255
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					sum += px[(y + dy) * w + x + dx]
					low = mini(low, px[(y + dy) * w + x + dx])
			if sum < 9 * 190 or low < 150:  # a runway (≤ 100 m wide) leaves a 120 m square's side cells half empty
				continue
			var g := Vector2(float(m.origin[0]) + (x + 0.5) * cell, float(m.origin[1]) - (y + 0.5) * cell)
			if rws.any(func(r): return Geometry2D.get_closest_point_to_segment(g, r[0], r[1]).distance_to(g) < r[2]):
				continue
			cand.append([sum, g])
	cand.sort_custom(func(a, c): return a[0] > c[0])
	var out := []
	for c in cand:
		if out.size() >= MAX_MASTS:
			break
		if out.all(func(p): return p.distance_to(c[1]) >= MAST_GAP):
			out.append(c[1])
	return out.map(func(g): return _from_game(b, g))


## Base `i`'s lights on the main thread once its masts are known: every point on the ground, the mesh, the pools.
func _built(i: int, mast_spots: Array) -> void:
	var e: Dictionary = _bases[i]
	e.state = 2
	var b: Dictionary = e.b
	var o: Vector2 = _tv.terrain.world_origin
	_v = PackedVector3Array()
	_c = PackedColorArray()
	for r in b.runways:
		_runway(r, e.full)
	if e.full:
		_taxiways(b)
	var n_ground := _v.size()
	for p: Vector2 in mast_spots:
		_add(p, SODIUM)
	var c := _scene(Airbases.centre(b), o)
	var c_h = _tv.terrain.height_at(c)
	var base_h: float = c_h if c_h != null else 0.0
	for k in _v.size():
		var p := _v[k]
		var gh = _tv.terrain.height_at(p)
		p.y = (float(gh) if gh != null else base_h) + (MAST_H if k >= n_ground else 0.0)
		_v[k] = p
	if _v.is_empty():
		return
	e.mesh.mesh = NightLights.point_mesh(_v, _c)
	e.mesh.visible = true
	for k in range(n_ground, _v.size()):
		var s := SpotLight3D.new()
		s.position = _v[k] + Vector3(0, -0.5, 0)
		s.rotation = Vector3(-PI / 2.0, 0, 0)  # straight down
		s.light_color = SODIUM
		s.light_energy = POOL_ENERGY
		s.light_specular = 0.3
		s.spot_angle = POOL_ANGLE
		s.spot_angle_attenuation = 1.0
		s.spot_range = POOL_RANGE
		s.spot_attenuation = 0.5
		s.shadow_enabled = false
		s.distance_fade_enabled = true
		s.distance_fade_begin = FADE_FAR - 1000.0
		s.distance_fade_length = 1000.0
		add_child(s)


## A light at engine point `p`; `face`: the way it shines (engine direction), Vector2.ZERO = every way. A PAPI unit
## passes its angle as `papi` (deg).
func _add(p: Vector2, col: Color, face := Vector2.ZERO, papi := 0.0) -> void:
	var o: Vector2 = _tv.terrain.world_origin
	_v.append(_scene(p, o))
	if face == Vector2.ZERO:
		col.a = 1.0
	else:
		col.a = minf(fposmod(atan2(-face.y, face.x), TAU) / TAU, 0.99)  # Godot +X toward +Z (south)
	if papi > 0.0:
		col = Color(0.0, 0.0, papi / 10.0, col.a)
	_c.append(col)


## One runway's lights. Its first end's threshold is the landing threshold of that direction, and so on.
func _runway(r: Dictionary, full: bool) -> void:
	var e0 := Vector2(r.ends[0][0], r.ends[0][1])
	var e1 := Vector2(r.ends[1][0], r.ends[1][1])
	var length := e0.distance_to(e1)
	var d := (e1 - e0) / length
	var n := Vector2(-d.y, d.x)  # left of d
	var hw := float(r.width) * 0.5 + 1.5
	var th: Array = r.get("thresholds", [0.0, 0.0])
	var t0 := float(th[0])
	var t1 := float(th[1])
	if full:
		var steps := maxi(1, roundi(length / EDGE_STEP))
		for k in steps + 1:
			var s := length * k / steps
			for side in [-1.0, 1.0]:
				var p: Vector2 = e0 + d * s + n * hw * side
				# Toward an arrival at e0 (it rolls along +d), and toward one at e1.
				_add(p, RED if s < t0 else (YELLOW if length - s < CAUTION else WHITE), -d)
				_add(p, RED if length - s < t1 else (YELLOW if s < CAUTION else WHITE), d)
	for end in 2:
		var at := e0 if end == 0 else e1
		var inward := d if end == 0 else -d
		var t := t0 if end == 0 else t1
		var thr := at + inward * t
		var bars := int(2.0 * hw / BAR_STEP)
		if full:
			for k in bars + 1:
				var x := -hw + 2.0 * hw * k / bars
				_add(thr + n * x, GREEN, -inward)  # the threshold, toward the approach
				_add(at + n * x, RED, inward)  # the runway's end, toward a jet rolling out to it
		# Approach lights: 5-light barrettes on the extended centreline, a crossbar at 300 m.
		var k := 1
		while k * APPROACH_STEP <= APPROACH:
			var c := thr - inward * k * APPROACH_STEP
			for x in [-2.0, -1.0, 0.0, 1.0, 2.0]:
				_add(c + n * x, WHITE, -inward)
			if k * APPROACH_STEP == 300.0:
				for x in range(-15, 16, 2):
					if absf(x) > 2.0:
						_add(c + n * x, WHITE, -inward)
			k += 1
		# PAPI on the left of the approach (n when landing along +d).
		var left := n if end == 0 else -n
		for u in PAPI_DEG.size():
			_add(thr + inward * PAPI_IN + left * (hw + PAPI_OUT + u * PAPI_GAP), Color.WHITE, -inward, PAPI_DEG[u])


## Blue edge lights along the taxi paths, off the runways; one light per 6 m spot where paths overlap.
func _taxiways(b: Dictionary) -> void:
	var rws := []
	for r in b.runways:
		rws.append([Vector2(r.ends[0][0], r.ends[0][1]), Vector2(r.ends[1][0], r.ends[1][1]), float(r.width) * 0.5])
	var seen := {}
	for path: Array in b.get("taxi", []):
		for k in path.size() - 1:
			var a := _from_game(b, Vector2(path[k][0], path[k][1]))
			var z := _from_game(b, Vector2(path[k + 1][0], path[k + 1][1]))
			var seg := z - a
			var seg_len := seg.length()
			if seg_len < 1.0:
				continue
			var dir := seg / seg_len
			var side := Vector2(-dir.y, dir.x) * TAXI_HALF
			var s := 0.0
			while s <= seg_len:
				for p: Vector2 in [a + dir * s + side, a + dir * s - side]:
					var key := Vector2i(roundi(p.x / 6.0), roundi(p.y / 6.0))
					if seen.has(key) or _on_runway(p, rws):
						continue
					seen[key] = true
					_add(p, BLUE)
				s += TAXI_STEP


static func _on_runway(p: Vector2, rws: Array) -> bool:
	for r in rws:
		if Geometry2D.get_closest_point_to_segment(p, r[0], r[1]).distance_to(p) < r[2] + 25.0:
			return true
	return false
