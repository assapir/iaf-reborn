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
## AVIONIC POWER switch sends the step once the four are on (the last of them), a guarded switch on its second click.
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
	["AVIONICS_MMC", []],
	["AVIONICS_ST_STA", []],
	["AVIONICS_MFD", []],
	["AVIONICS_UFC", [213, 1, 0]],
	["FCR", []],
	["RDR_ALT", []],
	["INS", [214, 0, 0]],
	["CANOPY_HANDLE", [215, 0, 0]],
	["anim023", [14, 0, 0]],
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
func require_data() -> void:
	if DirAccess.dir_exists_absolute(settings().own_dir().path_join("resource")):
		return
	print("NEEDS DATA: Modern IAF's own data (./modern-iaf-setup)")
	await _quit(2)
	await create_timer(3600, true, false, true).timeout


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
	var at := await _aim(tv, mi)
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
	var at := await _aim(tv, mi)
	var vp: Viewport = tv.get_viewport()
	tv._press([9, 30, 0])
	var n: int = rec.sent.size()
	await frames(2)
	for i in 5:
		vp.push_input(_wheel(at, MOUSE_BUTTON_WHEEL_DOWN))
		await frames(2)
	check(rec.sent.slice(n).all(func(c): return c == [6, 0, 0]), "%s: the wheel down takes 5 %%" % id)
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
