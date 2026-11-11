# Dev helper (not run by tools/test.sh): the Sufa's start-up switches clicked with the mouse (modern-iaf/docs/cockpit.md
# §5.2), a real render of mission 2011 (Start-up at Ramon, parked cold), from 2 s after the start. For each switch
# the head turns to it, then SHOT_OUT/<node>_rest.png (the pointer away), SHOT_OUT/<node>_hover.png (the pointer over
# it, lit) and SHOT_OUT/<node>_on.png (clicked through the input path: the step taken, the switch turned, the pointer
# moved away). Switches: SHOT_SWITCHES
# (comma-separated nodes of f16_controls.json, default MAIN_PWR,JFS; the steps a switch needs before it are taken by
# their keys' commands first; a guarded switch: also <node>_guard.png, its guard lifted by the first click). The view
# zoomed in (cockpit.ZOOM_MAX), the pilot's body hidden. SHOT_MISSION: another start-up mission (2031:
# the F-35I at Nevatim, its nodes of f35i_controls.json); a knob (a turn control) is only lit and clicked.
#   flock -o ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_OUT=<dir> \
#     -- --log-file <t> --resolution 1920x1080 --path modern-iaf -s ../modern-iaf/tests/_switch_shot.gd
extends "res://../tests/godot/base.gd"

## A node -> the checklist steps (commands) taken before it, by their keys' commands.
const BEFORE := {
	"JFS": [[210, 0, 0]],
	"INS": [[210, 0, 0], [211, 0, 0], [5, 0, 0], [213, 0, 0]],
	"AVIONICS_MMC": [[210, 0, 0], [211, 0, 0], [5, 0, 0]],
	"ENG": [[210, 0, 0]],  # the F-35I's: the battery, then the IPP up to speed (IPP_SPOOL_S)
}
## The F-35I's IPP before its ENG switch: on this long (sim s), as test_mvp's 11 s.
const IPP_SPOOL_S := 11.0


func run() -> void:
	settings().show_info = false
	var mission := OS.get_environment("SHOT_MISSION")
	load("res://flight/fly.gd").start(int(mission) if mission != "" else 2011)
	var tv: Node = null
	while tv == null or tv.get("flight") == null or tv.waiting_for_ground:
		await process_frame
		tv = current_scene
	await create_timer(2.0).timeout
	tv.cockpit.zoom = tv.cockpit.ZOOM_MAX
	var pilot = tv.cockpit_3d.get("_pilot")
	if pilot != null:  # the pilot's hand over the ELEC panel hides MAIN PWR
		(pilot.owner if pilot.owner is Node3D else pilot).visible = false
	var nodes := OS.get_environment("SHOT_SWITCHES")
	for node in (nodes if nodes != "" else "MAIN_PWR,JFS").split(","):
		for cmd in BEFORE.get(node, []):
			tv._command(cmd)
			if cmd[0] == 211:  # the JFS up to 20 % before the throttle, the generators before the avionics
				Engine.time_scale = 8.0
				while float(tv.flight.state().rpm) < 0.2:
					await process_frame
			elif cmd[0] == 5:
				while float(tv.flight.state().rpm) < 0.55:
					await process_frame
				Engine.time_scale = 1.0
		if node == "ENG":
			tv._command([211, 0, 0])
			Engine.time_scale = 8.0
			await create_timer(IPP_SPOOL_S).timeout
			Engine.time_scale = 1.0
		await _shoot(tv, node)


func _shoot(tv: Node, node: String) -> void:
	var c3d = tv.cockpit_3d
	var mi: MeshInstance3D = c3d.find_child(node, true, false)
	var centre := func() -> Vector3: return mi.global_transform * mi.get_aabb().get_center()
	var at := await _aim(tv, centre, 0.0)
	print(node, " at ", at)
	await _save(node + "_rest")
	var hover := InputEventMouseMotion.new()
	hover.position = at
	Input.parse_input_event(hover)
	await frames(10)
	check(mi.material_overlay != null, "%s: the pointer over it lights it" % node)
	await _save(node + "_hover")
	var rest := mi.transform
	# A guarded switch (its guard <node>_GUARD): the first click lifts the guard (SHOT_OUT/<node>_guard.png), the second
	# moves the switch.
	var guarded: bool = c3d.find_child(node + "_GUARD", true, false) != null
	for n in 2 if guarded else 1:
		if n == 1:
			await frames(10)
			check(mi.transform.is_equal_approx(rest), "%s: the first click lifts its guard, the switch stays" % node)
			await _save(node + "_guard")
		for pressed in [true, false]:
			var e := InputEventMouseButton.new()
			e.position = at
			e.button_index = MOUSE_BUTTON_LEFT
			e.pressed = pressed
			Input.parse_input_event(e)
			await process_frame
	hover.position = Vector2.ZERO
	Input.parse_input_event(hover)
	await frames(10)
	if not node in ["CANOPY_HANDLE", "HMD_BRT", "MFD_BRT"]:  # a hit area or a knob: a click turns nothing
		check(not mi.transform.is_equal_approx(rest), "%s: clicked, the switch turned" % node)
	await _save(node + "_on")


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var dir := OS.get_environment("SHOT_OUT")
	DirAccess.make_dir_recursive_absolute(dir)
	get_root().get_texture().get_image().save_png(dir.path_join(name + ".png"))


## The head turned until the point `p()` (world) is straight ahead (camera.rotation = (pitch, −yaw): terrain_view.gd),
## then lifted by `up` (rad); the point on the screen.
func _aim(tv: Node, p: Callable, up: float) -> Vector2:
	var cam: Camera3D = tv.cockpit_3d.camera
	var h := Vector2.ZERO
	for i in 6:  # `p` asked anew each step: the head bends forward looking down (terrain_view.gd LOOK_DOWN_LEAN)
		tv.views.snap = h
		await frames(3)
		var d: Vector3 = cam.global_transform.affine_inverse() * p.call()
		h += Vector2(-atan2(-d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()))
	tv.views.snap = h + Vector2(0.0, up)
	await frames(3)
	return cam.unproject_position(p.call())
