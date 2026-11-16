# The checklist's switches by the mouse (the switches audit's M1, modern-iaf/docs/cockpit.md §5.2): in each jet's cold
# start-up flight every switch the notebook's start-up, taxi / take-off and landing pages name is a clickable part of
# the 3D cockpit, lights under the pointer and sends its key's command on a click (recorded, not run: the order of the
# steps is test_mvp.gd's); the throttle by the mouse: a click and the wheel up add 5 %, the wheel down takes 5 %, a drag
# down begun at idle goes over the detent to OFF (Throttle OFF, command 218), a drag up from OFF back to idle.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_switches_click.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

const MISSIONS := "converted/modern-iaf/missions"
## airframe id -> [its start-up mission, [node, its command on a click (empty: a switch that only moves)]...]; an
## F-16 power switch (AVIONIC POWER, SNSR PWR) its own (219, p1 1: on from the cold jet's OFF, p2 its index), a guarded
## switch on its second click.
const JETS := {
	"f16i": ["ramon_startup", F16],
	"f16": ["ramat_david_startup", F16],
	"f35i":
	[
		"nevatim_startup",
		[
			["BATT", [210, 0, 0]],
			["IPP", [211, 0, 0]],
			["ENG", [212, 0, 0]],
			["START", [212, 1, 0]],
			["throttle", [5, 0, 0]],
			["CANOPY", [215, 0, 0]],
			["gear_handle", [14, 0, 0]],
		]
	],
}
const F16 := [
	["MAIN_PWR", [210, 0, 0]],
	["JFS", [211, 0, 0]],
	["THROTTLE", [5, 0, 0]],
	["AVIONICS_MMC", [219, 1, 0]],
	["AVIONICS_ST_STA", [219, 1, 1]],
	["AVIONICS_MFD", [219, 1, 2]],
	["AVIONICS_UFC", [219, 1, 3]],
	["FCR", [219, 1, 4]],
	["RDR_ALT", [219, 1, 5]],
	["INS", [214, 0, 0]],
	["CANOPY_HANDLE", [215, 0, 0]],
	["GEAR_LEVER", [14, 0, 0]],
]


## The cockpit's command path recorded: the throttle's commands run (the detent reads the lever), the rest only kept.
class Rec:
	var tv: Node
	var sent := []
	var throttle: float:
		get:
			return float(tv.throttle)
	var sounds: Object:
		get:
			return tv.sounds

	func run(cmd: Array) -> void:
		sent.append(cmd.map(func(x): return int(x)))  # the tables' JSON numbers are floats
		if int(cmd[0]) in [5, 6, 218]:
			tv._press(cmd)


## The sim's own data (./modern-iaf-setup), not the original's install.
func run() -> void:
	await require_data()
	var fly_gd: GDScript = load("res://flight/fly.gd")
	for id in JETS:
		var s := settings()
		var name: String = JETS[id][0]
		var m: Dictionary = s.load_json(s.assets_dir().path_join(MISSIONS).path_join(name + ".json"))
		fly_gd.set_jet(m)
		s.mission_files_override = [{"name": name, "data": m}]
		var tv: Node = await start_mission(int(m.sim.menu_id))
		s.mission_files_override = []
		await frames(5)
		var c3d = tv.cockpit_3d
		check(c3d != null and c3d.clickable != null, "%s: the 3D cockpit's clickable controls" % id)
		if c3d == null or c3d.clickable == null:
			continue
		var rec := Rec.new()
		rec.tv = tv
		c3d.command = Callable(rec, "run")
		for sw in JETS[id][1]:
			await _switch(tv, rec, id, sw[0], sw[1])
		await _throttle(tv, rec, id, "throttle" if id == "f35i" else "THROTTLE")
		if id != "f35i":
			await _knob(tv, rec, id, "INS", 214)
		tv.views.snap = null


## Switch `node`: found among the clickable controls, lit under the pointer, its click sends `cmd` (a guarded one on
## its second click; one with a FlightGear property flips it).
func _switch(tv: Node, rec: Rec, id: String, node: String, cmd: Array) -> void:
	var c3d = tv.cockpit_3d
	var e = c3d.clickable._controls.filter(func(c): return c[0].name == node)
	check(e.size() == 1, "%s: %s is a clickable control" % [id, node])
	if e.is_empty():
		return
	var mi: MeshInstance3D = e[0][0]
	var r: Dictionary = e[0][1]
	var at := _on_part(c3d, mi, await _aim(tv, mi))
	var hit = c3d.clickable.at(at)
	check(hit != null and hit[0] == mi, "%s: the pointer at %s finds %s" % [id, node, hit[0].name if hit else null])
	var vp: Viewport = tv.get_viewport()
	var hover := InputEventMouseMotion.new()
	hover.position = at
	vp.push_input(hover)
	check(mi.material_overlay != null, "%s: %s lights under the pointer" % [id, node])
	var was = c3d.switches.get(r.get("prop", ""), null)
	var n: int = rec.sent.size()
	for i in 2 if r.has("guard") else 1:
		vp.push_input(_click(at, true))
		vp.push_input(_click(at, false))
	var got: Array = rec.sent.slice(n)
	check(got == ([cmd] if not cmd.is_empty() else []), "%s: a click on %s sends %s (%s)" % [id, node, cmd, got])
	if r.get("toggle", false):
		check(c3d.switches.get(r.prop) != was, "%s: %s moved (%s -> %s)" % [id, node, was, c3d.switches.get(r.prop)])
	hover.position = Vector2.ZERO
	vp.push_input(hover)


## The throttle by the mouse: the wheel down to idle, a drag down from idle over the detent to OFF (218), a drag up
## back to idle (5); a drag down begun above idle stops at idle.
func _throttle(tv: Node, rec: Rec, id: String, node: String) -> void:
	var mi: MeshInstance3D = tv.cockpit_3d.find_child(node, true, false)
	tv._press([9, 30, 0])
	await frames(2)
	var at := _on_part(tv.cockpit_3d, mi, await _aim(tv, mi))
	var vp: Viewport = tv.get_viewport()
	# The pointer on the grip lights it; the lit grip keeps the wheel and the drags as it slides from under the pointer.
	var hover := InputEventMouseMotion.new()
	hover.position = at
	vp.push_input(hover)
	check(tv.cockpit_3d.clickable._lit() != null, "%s: the throttle's grip lights under the pointer" % id)
	var n: int = rec.sent.size()
	for i in 5:
		vp.push_input(_wheel(at, MOUSE_BUTTON_WHEEL_DOWN))
		await frames(2)
	check(
		rec.sent.slice(n).size() >= 5 and rec.sent.slice(n).all(func(c): return c == [6, 0, 0]),
		"%s: the wheel down takes 5 %%" % id
	)
	check(float(tv.throttle) == 0.0, "%s: the wheel down stops at idle (%.2f)" % [id, tv.throttle])
	n = rec.sent.size()
	await _drag(vp, at, 3, 1.0)
	check(
		rec.sent.slice(n).count([218, 0, 0]) == 1,
		"%s: a drag down at idle: Throttle OFF once %s" % [id, rec.sent.slice(n)]
	)
	n = rec.sent.size()
	await _drag(vp, at, 1, -1.0)
	check(rec.sent.slice(n) == [[5, 0, 0]] and tv.throttle > 0.0, "%s: a drag up from OFF: idle and up" % id)
	n = rec.sent.size()
	await _drag(vp, at, 3, 1.0)
	check(not [218, 0, 0] in rec.sent.slice(n), "%s: a drag down begun above idle stops at idle" % id)
	vp.push_input(_wheel(at, MOUSE_BUTTON_WHEEL_UP))
	check(rec.sent.back() == [5, 0, 0], "%s: the wheel up adds 5 %%" % id)


## A knob by the mouse (the INS knob, cockpit.md §5.2): the wheel up a position on ([cmd, 1, 0]), the wheel down a
## position back ([cmd, -1, 0]), a drag up and down each a position per step, a click a position on ([cmd, 0, 0]).
func _knob(tv: Node, rec: Rec, id: String, node: String, cmd: int) -> void:
	var mi: MeshInstance3D = tv.cockpit_3d.find_child(node, true, false)
	var at := await _aim(tv, mi)
	var vp: Viewport = tv.get_viewport()
	var n: int = rec.sent.size()
	vp.push_input(_wheel(at, MOUSE_BUTTON_WHEEL_UP))
	vp.push_input(_wheel(at, MOUSE_BUTTON_WHEEL_DOWN))
	check(rec.sent.slice(n) == [[cmd, 1, 0], [cmd, -1, 0]], "%s: %s: the wheel a position on and back" % [id, node])
	n = rec.sent.size()
	var px := float(tv.cockpit_3d.clickable._controls.filter(func(c): return c[0] == mi)[0][1].drag_px)
	await _drag(vp, at, int(ceil(2.0 * px / 20.0)), -1.0)
	check(rec.sent.slice(n).count([cmd, 1, 0]) >= 2, "%s: %s: a drag up turns it on %s" % [id, node, rec.sent.slice(n)])
	n = rec.sent.size()
	await _drag(vp, at, int(ceil(2.0 * px / 20.0)), 1.0)
	check(rec.sent.slice(n).count([cmd, -1, 0]) >= 2, "%s: %s: a drag down turns it back" % [id, node])


## A left drag of `steps` × 20 px from `at`, down (way 1) or up (−1).
func _drag(vp: Viewport, at: Vector2, steps: int, way: float) -> void:
	vp.push_input(_click(at, true))
	for i in steps:
		var m := InputEventMouseMotion.new()
		m.position = at + Vector2(0.0, way * 20.0 * (i + 1))
		m.relative = Vector2(0.0, way * 20.0)
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		vp.push_input(m)
		await frames(2)
	vp.push_input(_click(at, false))


## Of the part's triangles' centres seen on the screen, the one nearest `at` where the pointer finds `mi`: the hit area
## is the part's own surface, and its box's centre may lie off it (the F-35I's gear handle: a long lever, most of it
## inside the panel); `at` when none.
static func _on_part(c3d: Node, mi: MeshInstance3D, at: Vector2) -> Vector2:
	var cam: Camera3D = c3d.camera
	var f: PackedVector3Array = mi.mesh.get_faces()
	var best := at
	var best_d := INF
	for i in range(0, f.size(), 3):
		var c: Vector3 = mi.global_transform * ((f[i] + f[i + 1] + f[i + 2]) / 3.0)
		if cam.is_position_behind(c):
			continue
		var p := cam.unproject_position(c)
		if p.distance_to(at) < best_d:
			var hit = c3d.clickable.at(p)
			if hit != null and hit[0] == mi:
				best = p
				best_d = p.distance_to(at)
	return best


## The head turned until `mi`'s centre is straight ahead (test_mvp.gd _aim); its place on the screen.
func _aim(tv: Node, mi: MeshInstance3D) -> Vector2:
	var cam: Camera3D = tv.cockpit_3d.camera
	var p := func() -> Vector3: return mi.global_transform * mi.get_aabb().get_center()
	var h := Vector2.ZERO
	for i in 6:
		tv.views.snap = h
		await frames(3)
		var d: Vector3 = cam.global_transform.affine_inverse() * p.call()
		h += Vector2(-atan2(-d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()))
	tv.views.snap = h
	await frames(3)
	return cam.unproject_position(p.call())


static func _click(at: Vector2, pressed: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.position = at
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	return e


static func _wheel(at: Vector2, button: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.position = at
	e.button_index = button
	e.pressed = true
	return e
