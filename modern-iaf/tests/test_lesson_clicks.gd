# Every Training lesson that starts cold: its start-up switches answer the real click path (a pointer event at the
# switch's place on the screen, the head turned to it), MAIN PWR one click at a time (the user, 17 Nov: "I am unable to
# click the main power on the second traininig": the pilot's left glove covered the ELEC panel). The body takes no
# click (a click on MAIN PWR behind it works), Hide pilot's body (command 205) hides it held or toggled, and the
# first lesson hides it while it covers the ringed switch (kneeboard.gd _covered).
extends "res://tests/test_mvp.gd"

const LESSONS := ["ramon_startup", "ramon_takeoff", "ramat_david_takeoff", "nevatim_takeoff"]


func run() -> void:
	await require_data()
	fly_gd = load("res://flight/fly.gd")
	out = OS.get_temp_dir().path_join("modern-iaf-clicks-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(out)
	for name in LESSONS:
		var tv := await _start(name)
		Engine.time_scale = 1.0
		await fly(tv, 1.0)
		var f16: bool = (
			tv.flight.start_position("main_power") >= 0 and tv.cockpit_3d.find_child("MAIN_PWR", true, false) != null
		)
		var node := "MAIN_PWR" if f16 else "BATT"
		print(name, " throttle ", tv.throttle, " power ", tv.flight.start_position("main_power"))
		var mi: MeshInstance3D = tv.cockpit_3d.find_child(node, true, false)
		var covered: bool = tv.cockpit_3d.body_covers(mi.global_transform * mi.get_aabb().get_center())
		await _click_control(tv, node)
		print(name, " after click: ", tv.flight.start_position("main_power"))
		check(
			tv.flight.start_on("main_power"),
			"%s: a click on %s turns the power on (body over it: %s)" % [name, node, covered]
		)
		if name == "ramon_startup":
			await _cue(tv)
		if name == "ramon_takeoff":
			await _body_keys(tv)


## The first lesson's ring on MAIN PWR (the power off again, the tower's clearance given) hides the body covering it.
func _cue(tv: Node) -> void:
	tv.flight.start_switch("main_power", 0)
	tv.addon.answers.append("ACFT_CLEAR_TO_START")
	var c3d = tv.cockpit_3d
	var mi: MeshInstance3D = c3d.find_child("MAIN_PWR", true, false)
	await _aim(tv, func() -> Vector3: return mi.global_transform * mi.get_aabb().get_center(), 0.0)
	await frames(3)
	var covered: bool = c3d.body_covers(mi.global_transform * mi.get_aabb().get_center())
	check(
		c3d.body_cue == covered and c3d.pilot_body.visible != covered,
		"the ring's switch covered (%s): the body hidden" % covered
	)
	tv.views.snap = Vector2.ZERO  # the eye ahead: the switch in the open again
	await frames(3)


## Alt + H hides the body while held, Alt + G hides and shows it for the flight (records 192 / 193, command 205).
func _body_keys(tv: Node) -> void:
	var body: Node3D = tv.cockpit_3d.pilot_body
	tv.views.snap = Vector2.ZERO
	await frames(2)
	check(body.visible, "the body shown")
	tv._command([205, 1, 0])
	await frames(2)
	check(not body.visible, "Alt + H held: the body hidden")
	tv._release_command([205, 0, 0])
	await frames(2)
	check(body.visible, "Alt + H let go: the body back")
	tv._command([205, 2, 0])
	await frames(2)
	check(not body.visible, "Alt + G: the body hidden")
	tv._command([205, 2, 0])
	await frames(2)
	check(body.visible, "Alt + G again: the body back")
