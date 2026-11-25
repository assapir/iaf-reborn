# Dev helper (not run by tools/test.sh): a jet's navigation lights and strobe at a distance (docs/rendering.md §5,
# "Navigation lights and strobe"). The Scramble's Sufa pair in the air from Ramon round Hatzerim at SHOT_TIME (HHMM),
# as _scramble_time_shot.gd starts it; the wingman (the AI's jet: its lights always on) seen from its left front
# quarter, 5° above, at each of SHOT_DISTS (m, comma-separated; 40,300,1000,3000): SHOT_DIR/<SHOT_NAME>_<m>.png, and
# a crop round the jet of each, SHOT_DIR/<SHOT_NAME>_<m>_crop.png (256 px, the pixels doubled). SHOT_JET: the
# flight's jet (f16i, the default; f16d: the Barak pair from Ramat David). SHOT_LIGHTS=off|on: the player's own jet
# seen instead, its exterior lights panel all off or all on. A real render:
#   flock ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=<dir> SHOT_TIME=2200 \
#     SHOT_NAME=night -- --log-file <temp> --resolution 1600x900 --path modern-iaf \
#     -s ../modern-iaf/tests/_navlights_shot.gd
extends "res://../tests/godot/base.gd"


func run() -> void:
	var dir := OS.get_environment("SHOT_DIR")
	DirAccess.make_dir_recursive_absolute(dir)
	await require_data()
	var s := settings()
	s.sim_jet = OS.get_environment("SHOT_JET") if OS.get_environment("SHOT_JET") != "" else "f16i"
	s.show_info = false
	var hhmm := int(OS.get_environment("SHOT_TIME"))
	# The Barak's Scramble flies from Ramat David (its free mission's jet).
	var barak: bool = s.sim_jet == "f16d"
	var home := "David" if barak else "Ramon"
	var fc := {"flight": 2, "area": "Hatzerim", "home": home, "start": "air", "seed": 1}
	fc.start_min = hhmm / 100 * 60 + hhmm % 100
	var id := sim_mission("ramat_david_free" if barak else "ramon_free")
	load("res://flight/fly.gd").prepare_free(id, fc)
	s.free_combat = fc
	var tv: Node = await start_mission(id)
	s.mission_files_override = []
	s.invulnerable = true
	tv._command([292, 0, 1])  # PITCH: ATT HOLD, then ALT HOLD
	tv._command([292, 0, 1])
	await ground_streamed(tv, 30000, 20)
	await fly(tv, 2.0)
	tv.addon.ui.visible = false
	tv.in_cockpit = false
	var cam: Camera3D = tv.chase
	var wing: Array = tv.ai._ai_members.filter(func(m): return not m[1].player).map(func(m): return m[1])
	check(not wing.is_empty(), "a wingman")
	if wing.is_empty():
		return
	# SHOT_LIGHTS=off|on: the player's own jet instead, its exterior lights panel all off / on (the landing light aside).
	var own := OS.get_environment("SHOT_LIGHTS")
	if own != "":
		var ctl: Node = tv.cockpit_3d.clickable
		var on := 1.0 if own == "on" else 0.0
		for sw in [
			"SW_MASTER_50", "SW_WING-TAIL_50", "SW_ANTI_COLLISION_50", "SW_FUSELAGE_50", "SW_KNOB_EXT_FORM_LIGHT_50"
		]:
			var e: Array = ctl._controls.filter(func(c): return c[0].name == sw)
			check(not e.is_empty(), "switch " + sw)
			if not e.is_empty():
				ctl.put(e[0][1], on)
		wing = [{"node": tv.aircraft}]
		await fly(tv, 1.0)
	var dists := OS.get_environment("SHOT_DISTS") if OS.get_environment("SHOT_DISTS") != "" else "40,300,1000,3000"
	for d_s in dists.split(","):
		var d := float(d_s)
		var xf := Transform3D()
		var hold := func():
			var n: Node3D = wing[0].get("node")
			if n == null:
				return
			var at := n.global_position
			var b := n.global_basis
			var fwd := -b.z.normalized()
			var left := -b.x.normalized()
			var off := (fwd + left).normalized() * cos(deg_to_rad(5.0)) + Vector3.UP * sin(deg_to_rad(5.0))
			var e := at + off.normalized() * d
			xf = Transform3D(Basis.looking_at(at - e, Vector3.UP), e)
			cam.global_transform = xf
			RenderingServer.camera_set_transform(cam.get_camera_rid(), xf)
		RenderingServer.frame_pre_draw.connect(hold)
		await frames(20)
		await RenderingServer.frame_post_draw
		var img := root.get_viewport().get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		var name := "%s_%d" % [OS.get_environment("SHOT_NAME"), int(d)]
		check(img.save_png(dir.path_join(name + ".png")) == OK, "saved " + name)
		var c := img.get_region(Rect2i(img.get_width() / 2 - 64, img.get_height() / 2 - 64, 128, 128))
		c.resize(256, 256, Image.INTERPOLATE_NEAREST)
		c.save_png(dir.path_join(name + "_crop.png"))
		RenderingServer.frame_pre_draw.disconnect(hold)
