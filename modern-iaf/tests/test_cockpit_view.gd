# The 3D cockpit's view in every sim jet (shared/cockpit/cockpit.gd view_3d_focal, Settings.zoom_steps;
# modern-iaf/docs/cockpit.md §2). Each jet's start: the same default view, the wide one (VIEW_3D_WIDE_DEG across, zoom
# at ZOOM_MIN) with the head straight ahead, the F-16s' eye at the detailed model's pilot eye (the Barak's view as the
# Sufa's: the Mac play test's P1 of 2026-11-11). The wheel: each step up narrows the view to the narrow end and stops
# there; a step the other way within the scroll is dropped (macOS's end-of-scroll and momentum events), after a pause it
# zooms out; the trackpad's pan zooms the same way. The F-16s' pilot body: the right glove on the stick's grip.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_cockpit_view.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

## Each sim jet's start-up mission.
const JETS := {"f16i": 2011, "f16d": 2021, "f35i": 2031}


func run() -> void:
	var s := settings()
	if not FileAccess.file_exists(s.assets_dir().path_join("converted/modern-iaf/missions/missionlist.json")):
		print("NEEDS DATA: this test reads the sim's compiled missions (./modern-iaf-setup)")
		return
	var am: GDScript = load("res://shared/aircraft/aircraft_model.gd")
	var f16_eye: Vector3 = am.detailed_cockpit(load("res://shared/util/gltf.gd").DETAILED["f16_h.gltf"], true)[1]
	for jet in JETS:
		var tv := await _start(JETS[jet])
		var c: Control = tv.cockpit
		var w: float = c.get_viewport_rect().size.x
		var fov := rad_to_deg(2.0 * atan(w / 2.0 / c.focal_length()))
		check(c.three_d() and c.zoom == c.ZOOM_MIN, "%s: the 3D cockpit at the wide zoom (%.2f)" % [jet, c.zoom])
		check(absf(fov - c.VIEW_3D_WIDE_DEG) < 0.1, "%s: the wide view by default (%.1f°)" % [jet, fov])
		check(tv.views.head_angles() == Vector2.ZERO, "%s: the head straight ahead" % jet)
		if jet.begins_with("f16"):
			check(tv._own_eye.is_equal_approx(f16_eye), "%s: the eye at the F-16's pilot eye (%s)" % [jet, tv._own_eye])
			_right_glove(tv.cockpit_3d, jet)
			_left_glove(tv.cockpit_3d, jet)
		if jet == "f16i":
			await _wheel(c)


## The pilot body's right glove around the stick's grip (tools/f16d/pilot.py STICK_NUDGE; the user, 2026-11-13): at
## the grip's height the glove's centre within 3 cm of the grip's (f16.glb anim000-009), seen from above.
func _right_glove(c3d: Node3D, jet: String) -> void:
	var body: MeshInstance3D = c3d._pilot
	check(body != null, "%s: the pilot's body shown" % jet)
	if body == null:
		return
	var to_model := c3d.global_transform.affine_inverse()
	var grip := _centre(c3d.find_children("anim00?", "MeshInstance3D", true, false), to_model)
	var glove := _centre([body], to_model)
	check(
		Vector2(grip.x - glove.x, grip.z - glove.z).length() < 0.03,
		"%s: the right glove around the stick's grip (grip %s, glove %s)" % [jet, grip, glove]
	)


## The left glove on the throttle's head (tools/f16d/pilot.py NUDGE and GRIP_*; the Mac check, 2026-11-13: the fingers
## lay on the MANUAL PITCH / CHAN panel beside it), in the body's rest pose against the grip's (its shape keys off, the
## THROTTLE node unturned): the palm's centre within 3 cm of the head's top, seen from above, and no finger (the glove
## ahead of the wrist, z < −3.24) more than 2 cm inboard of the grip nor any of the glove 2.5 cm ahead of it.
func _left_glove(c3d: Node3D, jet: String) -> void:
	var body: MeshInstance3D = c3d._pilot
	var thr: MeshInstance3D = c3d.find_child("THROTTLE", true, false)
	check(body != null and thr != null, "%s: the pilot's body and the throttle shown" % jet)
	if body == null or thr == null:
		return
	var to_model := c3d.global_transform.affine_inverse()
	var rest := to_model * (thr.get_parent() as Node3D).global_transform * Transform3D(Basis(), thr.position)
	var grip := _points([thr], rest, func(_g: Vector3) -> bool: return true)
	var head := _mean(grip.filter(func(g: Vector3) -> bool: return g.y > 0.295))
	var inboard: float = grip.map(func(g: Vector3) -> float: return g.x).max()
	var front: float = grip.map(func(g: Vector3) -> float: return g.z).min()
	var glove := _points(
		[body],
		to_model * body.global_transform,
		func(g: Vector3) -> bool: return g.x < -0.28 and g.y > 0.22 and g.z < -3.2 and g.z > -3.4
	)
	var palm := _mean(glove.filter(func(g: Vector3) -> bool: return g.y > 0.3 and g.z < -3.22))
	check(
		Vector2(head.x - palm.x, head.z - palm.z).length() < 0.03,
		"%s: the left palm on the throttle's head (head %s, palm %s)" % [jet, head, palm]
	)
	var fingers := glove.filter(func(g: Vector3) -> bool: return g.z < -3.24)
	var most_in: float = fingers.map(func(g: Vector3) -> float: return g.x).max() if not fingers.is_empty() else INF
	var most_ahead: float = glove.map(func(g: Vector3) -> float: return g.z).min() if not glove.is_empty() else -INF
	check(
		most_in < inboard + 0.02 and most_ahead > front - 0.025,
		(
			"%s: the left fingers on the grip (glove to x %.3f, z %.3f; grip's inboard %.3f, front %.3f)"
			% [jet, most_in, most_ahead, inboard, front]
		)
	)


## The centre of `meshes`' vertices right of x 0.2, y 0.29-0.35, z -3.6 to -3.3 (the stick's grip and the hand on it);
## Vector3.INF when none is there, so the distance check fails.
func _centre(meshes: Array, to_model: Transform3D) -> Vector3:
	var all := []
	for mi: MeshInstance3D in meshes:
		all.append_array(
			_points(
				[mi],
				to_model * mi.global_transform,
				func(g: Vector3) -> bool: return g.x > 0.2 and g.y > 0.29 and g.y < 0.35 and g.z > -3.6 and g.z < -3.3
			)
		)
	return _mean(all)


## `meshes`' vertices through `xf` that pass `keep`.
func _points(meshes: Array, xf: Transform3D, keep: Callable) -> Array:
	var out := []
	for mi: MeshInstance3D in meshes:
		for si in mi.mesh.get_surface_count():
			for v: Vector3 in mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]:
				var g := xf * v
				if keep.call(g):
					out.append(g)
	return out


## The mean of `points`; Vector3.INF when there are none, so a distance check fails.
func _mean(points: Array) -> Vector3:
	var sum := Vector3()
	for p: Vector3 in points:
		sum += p
	return sum / points.size() if not points.is_empty() else Vector3.INF


## Wheel and trackpad zoom in the sim (Settings.cockpit_mouse_look: on to the narrow view).
func _wheel(c: Control) -> void:
	var s := settings()
	var w: float = c.get_viewport_rect().size.x / 2.0
	var narrow := w / tan(deg_to_rad(c.VIEW_3D_NARROW_DEG) / 2.0)
	var last: float = c.focal_length()
	var steady := true
	for i in 20:
		await _event(_wheel_event(MOUSE_BUTTON_WHEEL_UP))
		var f: float = c.focal_length()
		steady = steady and f >= last - 0.001
		last = f
	check(steady, "wheel up: every step narrows the view or holds it")
	check(c.zoom == c.zoom_limit() and absf(last - narrow) < 0.5, "wheel up: stops at the narrow view (%.0f)" % last)
	# At the clamp the wheel up still takes steps; one down right after is the scroll's tail: dropped.
	await _event(_wheel_event(MOUSE_BUTTON_WHEEL_UP))
	var z: float = c.zoom
	await _event(_wheel_event(MOUSE_BUTTON_WHEEL_DOWN))
	check(c.zoom == z, "a step back within the scroll: dropped")
	# Turned back without a pause (notches 100 ms apart): the zoom-out starts once the last step in is ZOOM_SETTLE_MS old.
	for i in 4:
		await create_timer(0.1).timeout
		await _event(_wheel_event(MOUSE_BUTTON_WHEEL_DOWN))
	check(c.zoom < z, "turned back mid-scroll, the wheel zooms out (%.2f)" % c.zoom)
	await create_timer(s.ZOOM_SETTLE_MS / 1000.0 + 0.05).timeout
	z = c.zoom
	var pan := InputEventPanGesture.new()
	pan.delta = Vector2(0.0, -1.0)
	await _event(pan)
	check(c.zoom > z, "the trackpad's pan zooms as the wheel up")
	await create_timer(s.ZOOM_SETTLE_MS / 1000.0 + 0.05).timeout
	for i in 40:
		await _event(_wheel_event(MOUSE_BUTTON_WHEEL_DOWN))
	check(c.zoom == c.ZOOM_MIN, "wheel down: stops at the wide view")


func _wheel_event(b: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = b
	e.pressed = true
	e.position = Vector2(2, 2)
	return e


func _event(e: InputEvent) -> void:
	Input.parse_input_event(e)
	await frames(1)


func _start(id: int) -> Node:
	load("res://flight/fly.gd").start(id)
	await frames(2)
	var tv: Node = null
	while tv == null or tv.get("flight") == null or tv.waiting_for_ground:
		await process_frame
		tv = current_scene
	await frames(3)
	return tv
