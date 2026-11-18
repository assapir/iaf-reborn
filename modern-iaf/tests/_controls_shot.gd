# Dev helper (not run by tools/test.sh): the proof of the F-16s' 3D-cockpit controls (finish-cockpit-controls.md C4,
# C4b). In each F-16's start-up (2011 Sufa, 2021 Barak; one model), started first (MAIN PWR, the JFS, the throttle to
# idle: the lamps and the EHSI powered), every control of the model's own `controls`
# (f16.json; cockpit3d_controls.gd) and the HUD's DAY / AUTO BRT / NIGHT switch goes through its positions in the
# store the cockpit shows (cockpit3d.gd `switches`): a switch or a knob of steps each step from min to max, a
# continuous knob or a stepping button five values, a push button at rest and pressed. For each control the head turns
# to it, zoomed in, the pilot's body hidden; each position is cropped round the part: SHOT_OUT/<unit>/<nnn>_<node>_<k>
# .png (180 x 180), the list in SHOT_OUT/<unit>/index.txt (<nnn> <node> <values>). A control whose crops are all the
# same is printed "STILL <unit> <node>". A part the panel hides from the seat's eye (FlightGear's ICP and instrument
# housing stand 8-23 cm proud of the MFDs' inboard rockers, the throttle's grip over MAX POWER) or whose move runs
# along the eye's line (a push button) is pictured again from the leans (LEANS) the pilot's head can take, until the
# crops differ ("LEAN <unit> <node> <lean>"). Crops compare at their full size: a small part's move (the ASI's bug, a
# 2 mm press) is a few pixels. SHOT_ONLY: these nodes alone (comma-separated).
#   flock -o ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_OUT=<dir> -- --log-file <t> \
#     --resolution 1920x1080 --path modern-iaf -s ../modern-iaf/tests/_controls_shot.gd
extends "res://tests/_switch_shot.gd"

const TILE := 180
## The least view round a part (px at 1920 x 1080).
const MIN_VIEW := 140.0
## The heads leaned (views.gd `lean`, m: x right, y up, z aft; what the lean keys reach: LEAN_MIN..LEAN_MAX, forward
## to its far end) a hidden or pressed part is pictured from, nearest first.
const LEANS: Array[Vector3] = [
	Vector3(-0.06, 0.0, 0.0),
	Vector3(0.06, 0.0, 0.0),
	Vector3(-0.06, -0.15, 0.0),
	Vector3(0.06, -0.15, 0.0),
	Vector3(-0.06, -0.15, -0.1),
	Vector3(0.06, -0.15, -0.1),
	Vector3(0.0, -0.15, -0.1),
	Vector3(-0.06, -0.15, -0.3),
	Vector3(0.06, -0.15, -0.3),
	Vector3(0.0, -0.15, -0.3),
]
## A crop differs where more than this share of its pixels changed (at least DIFF_MIN of them).
const DIFF_SHARE := 0.0005
const DIFF_MIN := 16
## The samples of a continuous knob, a stepping button or a knob of more than MAX_STEPS steps.
const SLIDE_N := 5
const MAX_STEPS := 12


func run() -> void:
	settings().show_info = false
	var dir := OS.get_environment("SHOT_OUT")
	var ids := OS.get_environment("SHOT_MISSIONS")
	var only := OS.get_environment("SHOT_ONLY").split(",", false)
	for id in (ids if ids != "" else "2011,2021").split(","):
		load("res://flight/fly.gd").start(int(id))
		var tv: Node = null
		await process_frame
		while tv == null or tv.get("flight") == null or tv.waiting_for_ground:
			await process_frame
			tv = current_scene
		await create_timer(2.0).timeout
		await _start(tv)
		tv.addon.ui.visible = false
		tv.cockpit.zoom = tv.cockpit.ZOOM_MAX
		var c3d = tv.cockpit_3d
		_surfaces = []
		if c3d.pilot_body != null:  # the body hides the consoles' switches (out of the tree: show_body shows it each frame)
			c3d.pilot_body.get_parent().remove_child(c3d.pilot_body)
		c3d.command = func(_cmd): pass  # the store alone: no system answers and puts a switch back (sync)
		var unit: String = tv.addon.plane
		var out := dir.path_join(unit)
		DirAccess.make_dir_recursive_absolute(out)
		var index := []
		var n := 0
		for e in c3d.clickable._controls:
			var r: Dictionary = e[1]
			var vals := _values(r, e[0].name)
			if vals.is_empty() or (not only.is_empty() and not e[0].name in only):
				continue
			n += 1
			var tag := "%03d_%s" % [n, e[0].name]
			index.append("%03d %s %s" % [n, e[0].name, " ".join(vals.map(func(v): return str(snappedf(v, 0.001))))])
			var moved := await _pictures(tv, e[0], r, vals, out.path_join(tag))
			if not moved:
				for lean in LEANS:
					tv.views.lean_to = lean
					await frames(3)
					if await _seen(tv, e[0], r):
						moved = await _pictures(tv, e[0], r, vals, out.path_join(tag))
						if moved:
							print("LEAN %s %s %s" % [unit, e[0].name, tv.views.lean])
							break
			tv.views.lean_to = null
			if not moved:
				print("STILL %s %s" % [unit, e[0].name])
		var f := FileAccess.open(out.path_join("index.txt"), FileAccess.WRITE)
		f.store_string("\n".join(index) + "\n")
		f.close()
		check(n >= (1 if not only.is_empty() else 150), "%s: %d controls pictured" % [unit, n])
		tv.views.snap = null


## The engine started (as _switch_shot.gd's BEFORE): MAIN PWR, the JFS up to 20 %, the throttle to idle, up to 55 %
## (the generators: the lamps and the EHSI powered).
func _start(tv: Node) -> void:
	tv.addon.pick("startup")  # the tower's clearance first (training.md §3.3)
	Engine.time_scale = 8.0
	for cmd in [[210, 0, 0], [211, 0, 0], [5, 0, 0]]:
		tv._command(cmd)
		var rpm := 0.2 if cmd[0] == 211 else (0.55 if cmd[0] == 5 else 0.0)
		while float(tv.flight.state().rpm) < rpm:
			await process_frame
	Engine.time_scale = 1.0
	await create_timer(1.0).timeout


## Control `r` (part `mi`) at each of `vals`, cropped round the part: <path>_<k>.png; whether the crops differ.
func _pictures(tv: Node, mi: MeshInstance3D, r: Dictionary, vals: Array, path: String) -> bool:
	var c3d = tv.cockpit_3d
	# Asked anew after the aim: the cockpit's world moves with the head (_switch_shot.gd _aim).
	await _aim(tv, func() -> Vector3: return _box(c3d, mi, r).get_center(), 0.0)
	var cam: Camera3D = c3d.camera
	var box := _box(c3d, mi, r)
	var rect := Rect2(cam.unproject_position(box.position), Vector2.ZERO)
	for k in 8:
		rect = rect.expand(cam.unproject_position(box.get_endpoint(k)))
	var side := maxf(maxf(rect.size.x, rect.size.y) * 2.0, MIN_VIEW)
	var shot_rect := Rect2i(rect.get_center() - Vector2(side, side) / 2.0, Vector2i(int(side), int(side)))
	var was = _shown(tv, r)
	var cover = c3d.switches.get(r.get("guard", ""))
	var first: Image = null
	var moved := false
	for k in vals.size():
		_show(tv, r, vals[k])
		await frames(2)
		await RenderingServer.frame_post_draw
		var img := get_root().get_texture().get_image().get_region(shot_rect)
		img.convert(Image.FORMAT_RGB8)
		if first == null:
			first = img
		elif not moved:
			moved = _differs(first, img)
		img = img.duplicate()
		img.resize(TILE, TILE, Image.INTERPOLATE_LANCZOS)
		img.save_png("%s_%d.png" % [path, k])
	_show(tv, r, was)
	if r.has("guard"):  # its cover as it was (_show lifts it)
		if cover == null:
			c3d.switches.erase(r.guard)
		else:
			c3d.switches[r.guard] = cover
	return moved


## Whether part `mi` is what the eye sees first at its centre (no other surface of the cockpit in front of it).
func _seen(tv: Node, mi: MeshInstance3D, r: Dictionary) -> bool:
	var c3d = tv.cockpit_3d
	await _aim(tv, func() -> Vector3: return _box(c3d, mi, r).get_center(), 0.0)
	var eye: Vector3 = c3d.camera.global_position
	if _surfaces.is_empty():
		for m: MeshInstance3D in c3d.find_children("*", "MeshInstance3D", true, false):
			if m.mesh != null and m.is_visible_in_tree():
				_surfaces.append([m, m.mesh.generate_triangle_mesh()])
	return first_hit(_surfaces, eye, mi) == mi


## The mesh of `surfaces` ([mesh, TriangleMesh]) the ray from `eye` to `mi`'s centre meets first.
static func first_hit(surfaces: Array, eye: Vector3, mi: MeshInstance3D) -> MeshInstance3D:
	var to := mi.global_transform * mi.get_aabb().get_center()
	var best := INF
	var first: MeshInstance3D = null
	for e in surfaces:
		var inv: Transform3D = e[0].global_transform.affine_inverse()
		var hit: Dictionary = e[1].intersect_ray(inv * eye, (inv.basis * (to - eye)).normalized())
		if not hit.is_empty() and (e[0].global_transform * hit.position - eye).length() < best:
			best = (e[0].global_transform * hit.position - eye).length()
			first = e[0]
	return first


var _surfaces := []  # [MeshInstance3D, TriangleMesh] of the cockpit (_seen)


## The part `mi` of control `r` and the parts near it its position moves (the ASI's bug by its knob), world frame.
static func _box(c3d: Node, mi: MeshInstance3D, r: Dictionary) -> AABB:
	var box: AABB = mi.global_transform * mi.get_aabb()
	var shows := c3d.find_child(r.get("shows", "-"), true, false) as MeshInstance3D  # its display (the EHSI)
	if shows != null:
		box = box.merge(shows.global_transform * shows.get_aabb())
	for a in c3d._anims:
		var m := a[0] as MeshInstance3D
		if m == null or m == mi or not a[2].any(func(x): return x.get("prop", "") == r.get("prop", "-")):
			continue
		var b: AABB = m.global_transform * m.get_aabb()
		if b.merge(box).get_longest_axis_size() < 0.12:
			box = box.merge(b)
	return box


## The positions control `r` (node `node`) is pictured at; none for the hand-only parts (the throttle, the stick, the
## gear lever) and the MFDs' flat OSBs.
func _values(r: Dictionary, node: String) -> Array:
	if node == "HUD_MODE":
		return [0.0, 1.0, 2.0]
	if not r.has("mode"):
		return []
	var lo := float(r.get("min", 0.0))
	var hi := float(r.get("max", 1.0))
	match r.mode:
		"push":
			return [float(r.rest), float(r.press)]
		"cycle" when round((hi - lo) / absf(float(r.step))) <= MAX_STEPS:
			var st := absf(float(r.step))
			var v := []
			for i in int(round((hi - lo) / st)) + 1:
				v.append(lo + i * st)
			return v
		"cycle":  # a knob of many steps (the HSI's course and heading, 0..360°): its first steps, ten at a time
			var v := []
			for i in SLIDE_N:
				v.append(lo + i * 10.0 * absf(float(r.step)))
			return v
	var v := []
	for i in SLIDE_N:
		v.append(lerpf(lo, hi, i / float(SLIDE_N - 1)))
	return v


## The value the cockpit shows `r` by: the store's, or the Settings a few parts read (cockpit3d.gd _prop).
func _shown(tv: Node, r: Dictionary):
	match r.get("prop", ""):
		"f16/avionics/hud-sym":
			return settings().hud_brightness
		"":
			return float(settings().hud_brt_switch)
	return tv.cockpit_3d.switches.get(r.prop)


func _show(tv: Node, r: Dictionary, v) -> void:
	var sw: Dictionary = tv.cockpit_3d.switches
	match r.get("prop", ""):
		"f16/avionics/hud-sym":
			settings().hud_brightness = v
		"":  # HUD_MODE
			settings().hud_brt_switch = int(v)
		_:
			if r.has("guard") and v != float(r.get("safe", v)):
				sw[r.guard] = 1.0  # its cover up while it is off its safe place
			if v == null:
				sw.erase(r.prop)
			else:
				sw[r.prop] = v


## Whether two crops differ past the renderer's noise: more than DIFF_SHARE of the pixels changed by over 0.1.
static func _differs(a: Image, b: Image) -> bool:
	var n := 0
	for y in a.get_height():
		for x in a.get_width():
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			if absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b) > 0.3:
				n += 1
	return n > maxi(DIFF_MIN, int(a.get_width() * a.get_height() * DIFF_SHARE))
