# Dev helper (not run by tools/test.sh): the manuals' cockpit pictures (modern-iaf/docs/manuals.md §4). For each cockpit
# of
# modern-iaf/manuals/shots.json (its cold start-up mission, 2 s after the start, the pilot's body and the game's
# overlays hidden) and each shot, the head turns to the shot's controls, as close as shows them all inside the
# picture's middle (a procedure's pictures, the stick's, the throttle's). A panel's picture (p_<panel>) is taken square
# from in front of the panel instead, what stands before the panel cut away, the battery on and every lamp lit (the
# lamp test), so every control and legend shows. The marks are projected through the camera that took the picture.
# pictures/<cockpit>/<shot>.jpg, and pictures/<cockpit>/marks.json: each control's box in its picture
# ([x0, y0, x1, y1], parts of the picture's width and height). The Typst build draws the numbers and arrows from the
# boxes. Chapter 1's pictures come from the cockpit's systems.json: p_<panel> with a box for every row, overview_<area>
# with a box for every panel. SHOT_JETS: only these jets (comma-separated). SHOT_ONLY: only the shots whose name
# starts so (p_, overview). SHOT_OUT: another folder than modern-iaf/manuals/pictures.
#   flock ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 -- --log-file <t> \
#     --resolution 1600x900 --path modern-iaf -s ../modern-iaf/tests/_manual_shots.gd
extends "res://tests/_switch_shot.gd"

## The zooms tried, closest first (cockpit.gd view_3d_focal: 1 the true size, 2 the narrow view, 0.6 the wide one).
const ZOOMS := [1.3, 1.0, 0.8, 0.6]
## The part of the picture the controls may span at a zoom.
const SPAN := 0.6
## The saved picture's width (px).
const WIDTH := 1600
## A shot's head off the seat's eye (views.gd lean: m, x right, y up, z aft): the stick from its side, the whole
## cockpit from as high and far back as the head goes.
const LEAN := {
	"p_stick": Vector3(-0.15, 0.1, 0.1),
	"overview_all": Vector3(0.0, 0.1, 0.1),
}
## The whole cockpit's picture (overview_all): the view's height (degrees), wider than the game's widest view.
const ALL_FOV := 110.0
## The whole cockpit's picture looks this far (rad) above the panels' middle, so the front panel's top is in it.
const ALL_UP := 0.25
## The shots taken with a lamp at the eye: the stick's grip is the cockpit's one dark part that takes light (the
## panels glow by themselves, cockpit3d.gd _lighting).
const LAMP := ["p_stick"]

## The panels' pictures taken from the pilot's eye: parts that are no flat panel.
const EYE := ["p_stick", "p_throttle", "p_hud", "p_canopy", "p_ded"]
## A square picture's view (degrees): narrow, so a panel's far rows are seen as square as its near ones.
const SQUARE_FOV := 30.0
## A square picture cuts away what is nearer to the camera than this (m) before the panel's nearest marked part.
const CLEAR := 0.04
## The least half height (m) a square picture shows: a panel of one switch keeps its surroundings.
const LEAST := 0.07

var _pose = null  # a square picture's camera, [Transform3D, the near plane (m)]; null the game's
var _near := 0.05  # the game's near plane
var _fwd := Vector3.FORWARD  # the jet's nose and up, from the head at rest (a lesson starts with the head turned)
var _up := Vector3.UP
var _eye := Vector3.ZERO
var _sides := true  # a console's picture may have a side of the jet as its top
var _fov := 0.0  # the camera's view for the next pictures (_pre_draw), 0 the game's
var _cam: Camera3D


func run() -> void:
	settings().show_info = false
	var kneeboard: GDScript = load("res://flight/kneeboard.gd")  # it names Settings: loaded here (base.gd)
	var dir := ProjectSettings.globalize_path("res://manuals")
	var spec: Dictionary = settings().load_json(dir.path_join("shots.json"))
	var out := OS.get_environment("SHOT_OUT")
	if out == "":
		out = dir.path_join("pictures")
	var only := OS.get_environment("SHOT_JETS").split(",", false)
	for jet in spec.jets:
		if not only.is_empty() and not jet in only:
			continue
		load("res://flight/fly.gd").start(int(spec.jets[jet].mission))
		var tv: Node = null
		await process_frame
		while tv == null or tv.get("flight") == null or tv.waiting_for_ground:
			await process_frame
			tv = current_scene
		await create_timer(2.0).timeout
		tv.addon.ui.visible = false
		var c3d = tv.cockpit_3d
		c3d.body_off = true  # the body covers the consoles
		_cam = c3d.camera
		_pose = null
		_sides = spec.jets[jet].get("legends", "") != "nose"
		_near = _cam.near
		if not RenderingServer.frame_pre_draw.is_connected(_pre_draw):
			RenderingServer.frame_pre_draw.connect(_pre_draw)
		var marks := {}
		var marks_file := out.path_join(jet).path_join("marks.json")
		var only_shots := OS.get_environment("SHOT_ONLY")
		if only_shots != "":  # only the shots whose name starts so: the others keep their pictures and marks
			marks = settings().load_json(marks_file)
		var cockpit := String(spec.jets[jet].shots)
		var shots: Dictionary = spec.shots[cockpit].duplicate()
		# Chapter 1's pictures: one of each panel of the cockpit's systems.json with every row's parts ("p_<panel>"),
		# and one of each area with its panels ("overview_<area>": the marks are the panels' boxes).
		var systems: Dictionary = settings().load_json(dir.path_join("text/en/%s/systems.json" % cockpit))
		var areas := {}
		for p in systems.panels:
			var rows := []
			for c in p.controls:
				rows.append(c.get("nodes", [c.node]))
			shots["p_" + p.id] = rows
			areas.get_or_add("overview_all", {})[p.id] = rows
		shots.merge(areas)
		var buttons: Dictionary = c3d.meta.get("buttons", {})
		for shot in shots:
			if only_shots != "" and not String(shot).begins_with(only_shots):
				continue
			var overview: bool = shots[shot] is Dictionary
			var parts := []
			var names := []
			var list: Array = shots[shot].keys() if overview else shots[shot]
			for item in list:
				# A mark's parts: a row's nodes (a panel's shot), every node of a panel (an overview).
				var nodes := []
				if overview:
					for row in shots[shot][item]:
						nodes.append_array(row)
				else:
					nodes = item if item is Array else [item]
				var found := []
				for node in nodes:
					var got := _parts(kneeboard, c3d, buttons, String(node))
					check(not got.is_empty(), "%s %s: the cockpit has %s" % [jet, shot, node])
					found.append_array(got)
				if not found.is_empty():
					parts.append(found)
					names.append(String(item if overview or not item is Array else item[0]))
			if parts.is_empty():
				continue
			var file := out.path_join(jet).path_join(String(shot) + ".jpg")
			# A panel's picture: the throttle hidden, as it covers the panels beside it (its own picture keeps it).
			var throttle: Array = kneeboard._part(c3d, "THROTTLE")
			var panel := String(shot).begins_with("p_")
			if panel and shot != "p_throttle" and not throttle.is_empty() and throttle[0] is Node3D:
				throttle[0].visible = false
			tv.views.lean = LEAN.get(shot, Vector3.ZERO)
			_fov = ALL_FOV if shot == "overview_all" else 0.0
			if panel and not c3d.lamp_test:  # the panels' pictures: the battery on, every lamp lit
				tv._command([210, 1, 0])
				c3d.lamp_test = true
				await frames(10)
			if panel and not shot in EYE:
				# The head back at the seat's eye and at rest first: the cockpit is placed about the head.
				tv.views.snap = Vector2.ZERO
				var was := Vector3.INF
				for i in 120:
					if tv.views.lean.is_equal_approx(was):
						break
					was = tv.views.lean
					await frames(2)
				await frames(4)
				_fwd = -_cam.global_basis.z  # the head at rest looks along the nose
				_up = _cam.global_basis.y
				_eye = _cam.global_position
				_pose = _square(parts)
			marks[shot] = await _shot(tv, parts, names, file, overview or panel)
			_pose = null
			if not throttle.is_empty() and throttle[0] is Node3D:
				throttle[0].visible = true
		tv.views.lean = Vector3.ZERO
		_fov = 0.0
		var f := FileAccess.open(marks_file, FileAccess.WRITE)
		f.store_string(JSON.stringify(marks, "", false) + "\n")
		f.close()


## The parts of `node` to box: its mesh (a control's, a lamp's, a display's), the meshes under it (a gauge's needle),
## else its place (a part without a mesh), or a bezel button's place of the cockpit's `buttons`.
func _parts(kneeboard: GDScript, c3d: Node, buttons: Dictionary, node: String) -> Array:
	var e: Array = kneeboard._part(c3d, node)
	if not e.is_empty() and e[0] is MeshInstance3D:
		return [e[0]]
	var n: Node = c3d.find_child(node, true, false)
	if n != null:
		var meshes := n.find_children("*", "MeshInstance3D", true, false)
		return meshes if not meshes.is_empty() else ([n] if n is Node3D else [])
	if buttons.has(node):
		var b: Array = buttons[node]
		var root: Node3D = c3d.find_child("*_cockpit3d", true, false)
		return [root.global_transform * Vector3(b[0], b[1], b[2])] if root != null else []
	return []


## The world box of one of _parts' parts: a mesh's, else 12 mm about a place.
func _box(part) -> AABB:
	if part is MeshInstance3D:
		return part.global_transform * part.get_aabb()
	var at: Vector3 = part.global_position if part is Node3D else part
	return AABB(at - Vector3.ONE * 0.006, Vector3.ONE * 0.012)


## The camera square in front of `parts` (per mark its parts): on the normal of the plane through the parts' middles,
## on the pilot's side, as far as shows them all in 0.8 of the picture; [its transform, its near plane]. The near
## plane is CLEAR before the nearest part, so the stick, a neighbour panel's edge or the sill is not drawn over them.
func _square(parts: Array) -> Array:
	var mids := PackedVector3Array()
	var corners := PackedVector3Array()
	for mark in parts:
		for part in mark:
			var b := _box(part)
			mids.append(b.get_center())
			for k in 8:
				corners.append(b.get_endpoint(k))
	var c := Vector3.ZERO
	for m in mids:
		c += m / mids.size()
	# The plane's normal: the pairs' cross products, each turned to the largest one's side.
	var ref := Vector3.ZERO
	for i in mids.size():
		for j in i:
			var x := (mids[i] - c).cross(mids[j] - c)
			if x.length_squared() > ref.length_squared():
				ref = x
	var n := Vector3.ZERO
	for i in mids.size():
		for j in i:
			var x := (mids[i] - c).cross(mids[j] - c)
			n += x * signf(x.dot(ref))
	var to_eye := (_eye - c).normalized()
	var reach := 0.0
	var far := Vector3.ZERO  # the middle farthest from the centre: the line's direction when the marks span no plane
	for m in mids:
		if (m - c).length() > reach:
			reach = (m - c).length()
			far = m - c
	if ref.length() < 0.15 * reach * reach or reach < 1e-4:
		# Marks on one line (a row of switches) or one mark: across the line, on the eye's side.
		var along := far.normalized() if reach >= 1e-4 else Vector3.ZERO
		n = (to_eye - along * to_eye.dot(along)).normalized()
	else:
		n = n.normalized() * (1.0 if n.dot(to_eye) >= 0.0 else -1.0)
	# The picture's top is the pilot's own: of the jet's up, nose and two sides, the one nearest to the top of the
	# pilot's view of the panel from the seat (up on the front panels, the nose on a console ahead of the seat,
	# outboard on one beside it), as the F-16's consoles' legends are turned. A cockpit whose consoles' legends all
	# read toward the nose says so in shots.json ("legends": "nose").
	var seen := _up - to_eye * to_eye.dot(_up)
	seen -= n * n.dot(seen)
	var top := _up
	if not _sides:
		top = _fwd if absf(n.dot(_up)) >= 0.5 else _up
	else:
		for axis in [_fwd, _fwd.cross(_up), _up.cross(_fwd)]:
			if axis.dot(seen) > top.dot(seen):
				top = axis
	var basis := Basis.looking_at(-n, top)
	var half := Vector2(LEAST, LEAST)
	var front := 0.0
	for p in corners:
		var d := (p - c) * basis  # in the camera's axes: x right, y up, z toward the camera
		half = half.max(Vector2(absf(d.x), absf(d.y)))
		front = maxf(front, d.z)
	var screen: Vector2 = _cam.get_viewport().get_visible_rect().size
	var dist := maxf(half.y, half.x * screen.y / screen.x) / (0.8 * tan(deg_to_rad(SQUARE_FOV / 2.0)))
	dist = maxf(dist, front + CLEAR + 0.02)
	return [Transform3D(basis, c + n * dist), dist - front - CLEAR]


## Each mark's box in the picture the camera now takes: {name: [x0, y0, x1, y1]}, parts of the picture.
func _boxes(parts: Array, names: Array) -> Dictionary:
	var screen: Vector2 = _cam.get_viewport().get_visible_rect().size
	var boxes := {}
	for j in parts.size():
		var r := Rect2(_cam.unproject_position(_box(parts[j][0]).position), Vector2.ZERO)
		for part in parts[j]:
			for k in 8:
				r = r.expand(_cam.unproject_position(_box(part).get_endpoint(k)))
		boxes[names[j]] = [
			snappedf(r.position.x / screen.x, 0.0001),
			snappedf(r.position.y / screen.y, 0.0001),
			snappedf(r.end.x / screen.x, 0.0001),
			snappedf(r.end.y / screen.y, 0.0001)
		]
	return boxes


## The picture of `parts` (per name its parts, _parts) saved to `file`; {name: its box in the picture}. `wide`: the
## zooms start closer and the parts may span more of the picture (chapter 1's pictures, which the build crops).
func _shot(tv: Node, parts: Array, names: Array, file: String, wide := false) -> Dictionary:
	var c3d = tv.cockpit_3d
	var cam: Camera3D = c3d.camera
	for zoom in ([2.0] + ZOOMS if wide else ZOOMS) if _pose == null else [1.0]:
		tv.cockpit.zoom = zoom
		if _pose != null:
			await frames(4)
			break
		var world := func() -> Vector3:
			var box := AABB()
			for j in parts.size():
				for part in parts[j]:
					box = (
						_box(part)
						if box.size == Vector3.ZERO and box.position == Vector3.ZERO
						else box.merge(_box(part))
					)
			return box.get_center()
		# A lean is cut short of the cockpit's surfaces a little each frame (terrain_view.gd _lean_off): the head is
		# aimed once it rests, and again from where it rests.
		for pass_no in 2:
			await _aim(tv, world, ALL_UP if _fov > 0.0 else 0.0)
			var was := Vector3.INF
			for i in 60:
				if tv.views.lean.is_equal_approx(was):
					break
				was = tv.views.lean
				await frames(2)
		await frames(2)
		var all := Rect2()
		for b in _boxes(parts, names).values():
			var r := Rect2(b[0], b[1], b[2] - b[0], b[3] - b[1])
			all = r if all.size == Vector2.ZERO else all.merge(r)
		var span := 0.8 if wide else SPAN
		if all.size.x < span and all.size.y < span:
			break
	var lamp: OmniLight3D = null
	if file.get_file().get_basename() in LAMP:
		lamp = OmniLight3D.new()
		lamp.omni_range = 3.0
		lamp.light_energy = 3.0
		cam.add_child(lamp)
		await frames(3)
	var img := await _grab()
	# The marks through the camera that drew this picture: no frame has moved it since.
	var boxes := _boxes(parts, names)
	if lamp != null:
		lamp.queue_free()
	var mean := img.duplicate() as Image
	mean.resize(1, 1, Image.INTERPOLATE_BILINEAR)
	# A dark cockpit brightened toward a mean of 0.3, by at most 2 (more whitens the sky).
	img.adjust_bcs(clampf(0.3 / maxf(mean.get_pixel(0, 0).get_luminance(), 0.01), 1.0, 2.0), 1.0, 1.0)
	DirAccess.make_dir_recursive_absolute(file.get_base_dir())
	check(img.save_jpg(file, 0.82) == OK, "saved " + file)
	return boxes


## The picture on the screen, WIDTH wide.
func _grab() -> Image:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.resize(WIDTH, WIDTH * img.get_height() / img.get_width(), Image.INTERPOLATE_LANCZOS)
	return img


## Before each frame is drawn, after the flight scene set the camera: a square picture's camera (_pose), the whole
## cockpit's wider view (_fov).
func _pre_draw() -> void:
	if not is_instance_valid(_cam):
		return
	if _pose != null:
		_cam.global_transform = _pose[0]
		_cam.force_update_transform()
		RenderingServer.camera_set_transform(_cam.get_camera_rid(), _pose[0])
		_cam.set_perspective(SQUARE_FOV, _pose[1], _cam.far)
	elif _fov > 0.0:
		_cam.set_perspective(_fov, _near, _cam.far)
	else:
		_cam.near = _near
