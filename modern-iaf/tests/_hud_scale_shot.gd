# Dev helper (not run by tools/test.sh): the Sufa's HUD at a display scale (docs/real-hud.md "Display scale"), a real
# render of mission 2012 started at an --at pose (the look study's Shoham pose below; _sym_wheel_shot.gd's Ramon final
# also works), frozen 3 s after the start, looking ahead:
# SHOT_OUT/hud_scale<SHOT_SCALE>.png. SHOT_SCALE (default 1) is the window's content_scale_factor, as a 2× (Retina)
# display's; give the window that many times the pixels (--resolution) for the same picture.
#   flock -o ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_OUT=<dir> SHOT_SCALE=2 \
#     -- --log-file <t> --resolution 2560x1440 --path modern-iaf -s ../modern-iaf/tests/_hud_scale_shot.gd \
#     -- --at 672750 3537452 240 100 0
# SHOT_MISSION: another mission, by id or name (default 2012; 2022 or ramat_david_range the Barak's); SHOT_GEAR=0:
# the gear up; SHOT_PITCH: the head pitched (rad, up +); SHOT_LEAN: the head moved off the eye (m: x right, y up, z
# aft; views.gd lean); SHOT_NAME: the file's name (default hud_scale<SHOT_SCALE>). SHOT_CAM (an F-16, base.gd
# photo_camera): also <name>_ref.png from a reference photo's camera, the HUD hidden. SHOT_DED=1: the HUD's DED switch
# on DED (DED DATA). SHOT_ALT: the HUD's ALT switch (0 RADAR, 1 BARO, 2 AUTO). SHOT_WIDEST=<master mode 0 1 2 3 5>:
# every readout at its widest (base.gd widest_real_hud_inputs, DED DATA only with SHOT_DED). SHOT_FIT=1 (headless
# will do): no picture; prints the widest side border (and the top border with it) whose field holds on the glass with
# every readout at its widest (test_sim_mfd.gd _on_glass), and DED DATA's size there.
extends "res://../tests/godot/base.gd"


## The Real HUD with its input's readouts replaced by `over`'s (SHOT_WIDEST).
class Widest:
	var rh = ClassDB.instantiate("IafRealHud")
	var over: Dictionary

	func _init(o: Dictionary) -> void:
		over = o

	func frame(field: Rect2, _i: Dictionary) -> Dictionary:
		return rh.frame(field, over)


func run() -> void:
	var k := float(OS.get_environment("SHOT_SCALE")) if OS.get_environment("SHOT_SCALE") != "" else 1.0
	get_root().content_scale_factor = k
	settings().show_info = false
	settings().hud_brightness = 1.0
	var m := _env("SHOT_MISSION", "2012")
	load("res://flight/fly.gd").start(int(m) if m.is_valid_int() else sim_mission(m))
	var tv: Node = null
	while tv == null or tv.get("flight") == null or tv.waiting_for_ground:
		await process_frame
		tv = current_scene
		if tv != null and tv.get("addon") != null and tv.addon.result.is_empty():
			tv.addon.result = {"pass": true}  # no lesson run: an airborne --at start fails one (sim_flight.gd)
	tv.gear_down = _env("SHOT_GEAR", "1") == "1"
	if _env("SHOT_PITCH", "") != "":
		tv.views.snap = Vector2(0.0, float(_env("SHOT_PITCH", "0")))
	if _env("SHOT_LEAN", "") != "":
		var lean := _env("SHOT_LEAN", "0,0,0").split_floats(",")
		tv.views.lean_to = Vector3(lean[0], lean[1], lean[2])
	await create_timer(3.0).timeout
	Engine.time_scale = 0.0
	await frames(30)
	var c: Node = tv.cockpit
	if _env("SHOT_DED", "") == "1":
		c.hud_panel.ded = 0
		await frames(5)
	if _env("SHOT_ALT", "") != "":
		c.hud_panel.alt = int(_env("SHOT_ALT", "1"))
		await frames(5)
	if _env("SHOT_FIT", "") == "1":
		await _fit(c)
		Engine.time_scale = 1.0
		check(true, "fit")
		return
	if _env("SHOT_WIDEST", "") != "":
		var over: Dictionary = widest_real_hud_inputs(c.hud)[maxi(
			0, [0, 1, 2, 3, 5].find(int(_env("SHOT_WIDEST", "0")))
		)]
		if _env("SHOT_DED", "") != "1":
			over.panel.ded = PackedStringArray()
		c.hud._real_hud = Widest.new(over)
		await frames(5)
	print("window ", get_root().size, " scale ", get_root().content_scale_factor, " canvas ", tv.cockpit.size)
	print("ui_scale ", tv.cockpit.ui_scale(), " focal ", tv.cockpit.focal_length())
	print("final ", get_root().get_final_transform(), " screen ", tv.cockpit.hud.get_screen_transform())
	await RenderingServer.frame_post_draw
	var dir := OS.get_environment("SHOT_OUT")
	DirAccess.make_dir_recursive_absolute(dir)
	var file := _env("SHOT_NAME", "hud_scale" + OS.get_environment("SHOT_SCALE"))
	get_root().get_texture().get_image().save_png(dir.path_join(file + ".png"))
	var c3d = tv.get("cockpit_3d")
	var root: Node3D = c3d.find_child("f16_cockpit3d", true, false) if c3d != null else null
	var cam := photo_camera(c3d, root) if root != null else null
	if cam != null:  # the HUD hidden (its layers' own drawing see-through): it is drawn for the eye's camera
		for n in [tv.cockpit.hud, tv.cockpit.hud.outer]:
			n.self_modulate.a = 0.0
		await frames(3)
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png(dir.path_join(file + "_ref.png"))
		cam.queue_free()
	Engine.time_scale = 1.0
	check(true, "shot")


## SHOT_FIT: the side borders from the original's 72 down, each with the top border from the original's 66 down, until
## the field and every Real HUD symbol, its readouts at their widest, lie on the glass at the wide view and zoomed in,
## in the project's window (test_sim_mfd.gd _on_glass).
func _fit(c: Node) -> void:
	var h: Dictionary = c.layout.HUD
	await project_window()
	for side in range(72, 39, -1):
		for top in range(66, 49, -1):
			h.LeftBorder = side
			h.RightBorder = side
			h.TopBorder = top
			var ok := true
			for zoom in [c.ZOOM_MIN, c.ZOOM_MAX]:
				c.zoom = zoom
				c.hud.queue_redraw()
				await frames(3)
				ok = ok and off_glass(c, true).is_empty()
			if ok:
				var i: Dictionary = widest_real_hud_inputs(c.hud)[0]
				var sizes: Array = ClassDB.instantiate("IafRealHud").frame(c.hud._field(), i).outer.map(
					func(p): return float(p.get("size", 1.0))
				)
				print("FIT side %d top %d ded %.3f" % [side, top, sizes.min()])
				return
	print("FIT none")
