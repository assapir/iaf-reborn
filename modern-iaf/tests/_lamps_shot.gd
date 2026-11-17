# Dev helper (not run by tools/test.sh): the F-16s' 3D-cockpit lamps (the lights audit, modern-iaf/docs/cockpit.md
# "Lamps"), real renders. The jet of SHOT_MISSION (2011 the Sufa at Ramon, default; 2021 the Barak) cold on the ramp,
# MAIN PWR on (the battery: ENGINE, HYD / OIL PRESS, CANOPY, the ELEC panel, ELEC SYS, MASTER CAUTION lit); for each
# view the head turns to it: SHOT_OUT/<view>_battery.png, then MAL & IND LTS held: <view>_test.png. Views: front (the
# eyebrows, the AoA indexer, the gear panel), elec (the left console's ELEC and EPU panels, the test panel), caution
# (the right console's caution panel), threat (the threat warning prime panel and ECM ENBL). --hour H: the mission at H
# o'clock (night: 22).
#   flock -o ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_OUT=<dir> \
#     -- --log-file <t> --resolution 1920x1080 --path modern-iaf -s ../modern-iaf/tests/_lamps_shot.gd -- --hour 22
extends "res://../tests/godot/base.gd"

## Each view: the lamp node the head turns to, the head lifted (rad), the zoom (0: the cockpit's least, the pilot's
## view; 1 its most).
const VIEWS := {
	"front": ["lamp_aoa_on_speed_0", -0.3, 0.0],
	"elec": ["lamp_main_gen_0", 0.0, 1.0],
	"caution": ["lamp_caution_elec_sys_0", 0.0, 1.0],
	"threat": ["lamp_twd_test_0", 0.0, 1.0],
}


func run() -> void:
	settings().show_info = false
	var id := int(OS.get_environment("SHOT_MISSION")) if OS.get_environment("SHOT_MISSION") != "" else 2011
	load("res://flight/fly.gd").start(id)
	var tv: Node = null
	while tv == null or tv.get("flight") == null or tv.get("cockpit_3d") == null:
		await process_frame
		tv = current_scene
	await create_timer(2.0).timeout
	tv.addon.ui.visible = false
	tv.addon.pick("startup")
	var c3d: Node = tv.cockpit_3d
	var ctl: Node = c3d.clickable
	var main: Dictionary = ctl._controls.filter(func(e): return e[0].name == "MAIN_PWR")[0][1]
	ctl.put(main, 2.0)
	await create_timer(1.0).timeout
	print("power ", tv.cockpit.power, " lit ", c3d.lamps_lit.keys().filter(func(k): return c3d.lamps_lit[k]))
	var test: Dictionary = ctl._controls.filter(func(e): return e[0].name == "MAL_IND_LTS")[0][1]
	var pilot = c3d.get("_pilot")
	if pilot != null:  # the pilot's arm hides the ELEC panel
		(pilot.owner if pilot.owner is Node3D else pilot).visible = false
	for v in VIEWS:
		tv.cockpit.zoom = lerpf(tv.cockpit.ZOOM_MIN, tv.cockpit.ZOOM_MAX, float(VIEWS[v][2]))
		var mi := c3d.find_child(VIEWS[v][0], true, false) as MeshInstance3D
		if mi == null:
			print("no node ", VIEWS[v][0])
			continue
		await _aim(tv, mi.global_transform * mi.get_aabb().get_center(), float(VIEWS[v][1]))
		await _save(v + "_battery")
		ctl.press(test)
		await create_timer(0.3).timeout
		await _save(v + "_test")
		ctl.release()
		await create_timer(0.2).timeout


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var dir := OS.get_environment("SHOT_OUT")
	DirAccess.make_dir_recursive_absolute(dir)
	get_root().get_texture().get_image().save_png(dir.path_join(name + ".png"))


## The head turned until the point `p` (world) is straight ahead (as _cockpit_look_shot.gd's), lifted by `up` (rad).
func _aim(tv: Node, p: Vector3, up: float) -> void:
	var cam: Camera3D = tv.cockpit_3d.camera
	var h := Vector2.ZERO
	for i in 6:
		tv.views.snap = h
		await frames(3)
		var d: Vector3 = cam.global_transform.affine_inverse() * p
		h += Vector2(-atan2(-d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()))
	tv.views.snap = h + Vector2(0.0, up)
	await create_timer(0.5).timeout
