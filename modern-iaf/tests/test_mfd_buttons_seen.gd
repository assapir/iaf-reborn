# The F-16s' MFD push buttons and rockers from the seat, from the lean and from the full MFD view (finish list
# C4b; modern-iaf/docs/cockpit.md "The MFDs from the seat"). In each jet's cold start-up flight, for each of both MFDs'
# 20 push buttons and their GAIN, CON and BRT rockers: the first surface the eye meets toward it is the part (or lies
# within 15 mm of it), and the pointer there presses it (a push button by its MFD's own press path, a rocker by the
# cockpit's controls).
#   - From the seat's eye in the view the flight opens with, all but ICP_CORNER: the two top inboard buttons of each
#     MFD and the right MFD's GAIN rocker, which the ICP's lower corner stands in front of (as on the F-16C photo the
#     model is fitted to).
#   - From the lean toward an MFD (command 204, Shift + Left / Right held): every one of that MFD's; the release
#     brings the head back.
#   - From the full MFD view (command 207): every one of that MFD's, on the screen, the display over half the screen's
#     height; the same key and Esc go back to the seat's view, the flight running.
# The F-35I: the full view shows the whole panoramic display, from either key.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_mfd_buttons_seen.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

const Click := preload("res://tests/test_switches_click.gd")
const MISSIONS := "converted/modern-iaf/missions"
const JETS := {"f16i": "ramon_startup", "f16": "ramat_david_startup"}
const ADIR := "nevatim_startup"
const ROCKERS := [
	"MFD1_MFDButtonGain",
	"MFD1_MFDButtonCon",
	"MFD1_MFDButtonBrightness",
	"MFD2_MFDButtonGain",
	"MFD2_MFDButtonCon",
	"MFD2_MFDButtonBrightness"
]
const ICP_CORNER := ["MFD2_MFDButtonGain", "MFD_L_R1", "MFD_L_R2", "MFD_R_L1", "MFD_R_L2"]
## A surface this close in front of the part's centre is the part's own (its bezel, its face).
const OWN := 0.015

var _meshes := []
var _parts := {}  # name -> its centre in the model's frame (a push button) or its MeshInstance3D (a rocker)


func run() -> void:
	await require_data()
	for id in JETS:
		var tv := await _start(JETS[id])
		var c3d = tv.cockpit_3d
		var root := c3d.find_child("f16_cockpit3d", true, false) as Node3D
		check(root != null and c3d.clickable != null, "%s: the F-16 cockpit and its controls" % id)
		if root == null or c3d.clickable == null:
			continue
		c3d.command = func(_c): pass
		_meshes = []
		for mi: MeshInstance3D in c3d.find_children("*", "MeshInstance3D", true, false):
			if mi.mesh != null:
				_meshes.append([mi, mi.mesh.generate_triangle_mesh()])
		_parts = {}
		var buttons: Dictionary = c3d.meta.get("buttons", {})
		for k: String in buttons:
			_parts[k] = c3d._v3(buttons[k])
		for k in ROCKERS:
			_parts[k] = root.find_child(k, true, false)
		check(buttons.size() == 40 and _parts.values().all(func(p): return p != null), "%s: 40 buttons, 6 rockers" % id)
		var hidden := _hidden(c3d, root, _parts.keys()).map(func(h): return h.get_slice(" ", 0))
		hidden.sort()
		check(
			hidden == ICP_CORNER, "%s: from the seat all seen and pressed but the ICP's corners' five %s" % [id, hidden]
		)
		for left in [true, false]:
			var mine := _parts.keys().filter(func(k): return _left(k) == left)
			var side := "left" if left else "right"
			# The lean key toward the MFD, held (Shift + Left / Right).
			_hold(KEY_LEFT if left else KEY_RIGHT, true)
			tv._press([204, 0, -1 if left else 1])
			await create_timer(tv.views.LEAN_S).timeout
			var early: float = absf(tv.views.lean.x)
			await create_timer(0.3).timeout
			var want: float = tv.views.LEAN_MAX.x
			check(
				early > 0.8 * want and is_equal_approx(absf(tv.views.lean.x), want),
				"%s: the lean %s: there in about %.1f s (%.3f, %.3f)" % [id, side, tv.views.LEAN_S, early, want]
			)
			hidden = _hidden(c3d, root, mine)
			check(
				hidden.is_empty(),
				"%s: leaning %s, its MFD's buttons and rockers seen and pressed %s" % [id, side, hidden]
			)
			tv._release_command([204, 0, 0])
			_hold(KEY_LEFT if left else KEY_RIGHT, false)
			await create_timer(0.5).timeout
			check(tv.views.lean == Vector3.ZERO, "%s: the release: back at the seat's eye (%s)" % [id, tv.views.lean])
			# The full MFD view.
			var head: Vector2 = tv.views.head
			var focal: float = tv.cockpit.focal_length()
			tv._press([207, 0 if left else 1, 0])
			await create_timer(0.5).timeout
			tv.views.look_by(Vector2(0.3, 0.1))  # a mouse look in the close-up: dropped with it
			tv._zoom_cockpit(0.2)  # and a zoom there: the seat's zoom is kept
			var view: Rect2 = Rect2(Vector2.ZERO, tv.cockpit.size)
			var box := Rect2(_at(c3d, root, mine[0]), Vector2.ZERO)
			for k in mine:
				box = box.expand(_at(c3d, root, k))
			check(
				view.encloses(box) and box.size.y > 0.5 * view.size.y,
				(
					"%s: the full %s MFD view: every button on the screen, the display large (%s of %s)"
					% [id, side, box, view]
				)
			)
			hidden = _hidden(c3d, root, mine)
			check(
				hidden.is_empty(),
				"%s: the full %s MFD view: every button and rocker seen and pressed %s" % [id, side, hidden]
			)
			tv._press([207, 0, 0] if left else [122, 0, 0])  # the same key; Esc
			await create_timer(0.5).timeout
			check(
				(
					tv.mfd_view < 0
					and tv.views.head.is_equal_approx(head)
					and is_equal_approx(tv.cockpit.focal_length(), focal)
				),
				"%s: %s: back at the seat's view" % [id, "the same key" if left else "Esc"]
			)
			check(not tv.paused and current_scene == tv, "%s: the flight runs on" % id)
	# The F-35I's one display, from either key.
	var tv := await _start(ADIR)
	var c3d = tv.cockpit_3d
	for i in 2:
		check(not c3d.display_frame(i).is_empty(), "f35i: the panoramic display's frame")
		var seat: Array = _corners(c3d)
		var head: Vector2 = tv.views.head
		var focal: float = tv.cockpit.focal_length()
		tv._press([207, i, 0])
		await create_timer(0.5).timeout
		var view: Rect2 = Rect2(Vector2.ZERO, tv.cockpit.size)
		var c: Array = _corners(c3d)
		var box := Rect2(c[0], Vector2.ZERO).expand(c[1]).expand(c[2]).expand(c[3])
		check(
			view.encloses(box) and box.size.x > 0.75 * view.size.x,
			"f35i: key %d: the whole display on the screen, three quarters of its width (%s of %s)" % [i, box, view]
		)
		tv._press([207, i, 0])
		await create_timer(0.5).timeout
		var back: bool = tv.views.head.is_equal_approx(head) and is_equal_approx(tv.cockpit.focal_length(), focal)
		check(
			tv.mfd_view < 0 and back and _corners(c3d)[0].is_equal_approx(seat[0]),
			"f35i: key %d again: back at the seat" % i
		)


func _start(mission: String) -> Node:
	var s := settings()
	var m: Dictionary = s.load_json(s.assets_dir().path_join(MISSIONS).path_join(mission + ".json"))
	load("res://flight/fly.gd").set_jet(m)
	s.mission_files_override = [{"name": mission, "data": m}]
	var tv: Node = await start_mission(int(m.sim.menu_id))
	s.mission_files_override = []
	await frames(5)
	return tv


## Shift + `k` held or let go, as the lean keys are (terrain_view.gd _lean_off reads the held keys).
func _hold(k: Key, down: bool) -> void:
	for key in [KEY_SHIFT, k] if down else [k, KEY_SHIFT]:
		var e := InputEventKey.new()
		e.keycode = key
		e.physical_keycode = key
		e.pressed = down
		e.shift_pressed = down
		Input.parse_input_event(e)
	Input.flush_buffered_events()


static func _left(k: String) -> bool:
	return k.begins_with("MFD_L") or k.begins_with("MFD1")


## The panoramic display's four corners on the screen.
static func _corners(c3d: Node) -> Array:
	var e: Array = c3d._pcd
	var out := []
	for uv in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
		out.append(c3d.camera.unproject_position(e[2].global_transform * (e[3] + e[4] * uv.x + e[5] * uv.y)))
	return out


## Part `k`'s place (global; the cockpit moves about the eye with the lean, cockpit_origin.gd: read after the move).
func _spot(root: Node3D, k: String) -> Vector3:
	return root.global_transform * _parts[k] if _parts[k] is Vector3 else _centre(_parts[k])


## Part `k`'s place on the screen (a rocker's: a point of its own surface near its centre).
func _at(c3d: Node, root: Node3D, k: String) -> Vector2:
	var at: Vector2 = c3d.camera.unproject_position(_spot(root, k))
	return Click._on_part(c3d, _parts[k], at) if _parts[k] is MeshInstance3D else at


## Those of `names` not seen or not pressed from where the eye is: "<name> <why>".
func _hidden(c3d: Node, root: Node3D, names: Array) -> Array:
	var out := []
	for k: String in names:
		var p := _spot(root, k)
		var why := _seen(_meshes, c3d.camera.global_position, p)
		if why == "":
			why = _pressed(c3d, k, _parts[k] if _parts[k] is MeshInstance3D else p, _at(c3d, root, k))
		if why != "":
			out.append("%s %s" % [k, why])
	return out


static func _centre(mi: MeshInstance3D) -> Vector3:
	return mi.global_transform * mi.get_aabb().get_center()


## "" when the first surface the eye meets toward `p` lies within OWN of it; else what stands in front.
static func _seen(meshes: Array, eye: Vector3, p: Vector3) -> String:
	var best := INF
	var first := ""
	for e in meshes:
		if not e[0].is_visible_in_tree():
			continue
		var inv: Transform3D = e[0].global_transform.affine_inverse()
		var hit: Dictionary = e[1].intersect_ray(inv * eye, (inv.basis * (p - eye)).normalized())
		if not hit.is_empty():
			var d: float = (e[0].global_transform * hit.position - eye).length()
			if d < best:
				best = d
				first = e[0].name
	return "" if (p - eye).length() - best < OWN else "behind %s" % first


## "" when the pointer at `at` presses the part: a push button through its MFD's press path (cockpit3d.gd
## _unhandled_input), a rocker by the controls' hit test.
static func _pressed(c3d: Node, k: String, part, at: Vector2) -> String:
	if part is MeshInstance3D:
		var hit = c3d.clickable.at(at)
		return "" if hit != null and hit[0] == part else "pointer finds %s" % (hit[0].name if hit != null else null)
	for e in c3d._screens:
		if (e[2] as Node).name != k.left(5):
			continue
		var want := -1
		var near := INF
		var own: Vector2 = c3d._uv(e, part) * c3d.Mfd.SIZE
		for osb in e[6]:
			if own.distance_to(e[6][osb]) < near:
				near = own.distance_to(e[6][osb])
				want = osb
		var hit = c3d._hit_uv(e, c3d._ray(at))
		if hit == null:
			return "pointer off the screen's plane"
		for osb in e[6]:
			if (hit * c3d.Mfd.SIZE).distance_to(e[6][osb]) <= c3d.OSB_REACH:
				return "" if osb == want else "pointer presses OSB %d, not %d" % [osb, want]
		return "pointer presses nothing"
	return "no screen"
