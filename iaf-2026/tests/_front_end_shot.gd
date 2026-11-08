# Real-render pictures of Modern IAF's front end, every screen in English and Hebrew (iaf-2026/docs/front-end.md):
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=/tmp/fe -- --log-file /tmp/fe.log --path iaf-2026 \
#     -s ../iaf-2026/tests/_front_end_shot.gd
# Writes SHOT_DIR/<screen>_<lang>.png (home_first_*: before a plane is picked; prefs_<section>_*) at 1920×1080 (the
# front end in a viewport of that size, whatever the window's) with the sample pilot log and debrief of
# test_front_end.gd.
extends "res://../tests/godot/base.gd"

const SCREENS := ["home", "plane", "training", "mission", "prefs", "debrief", "log", "credits"]


func run() -> void:
	var dir := OS.get_environment("SHOT_DIR")
	check(dir != "", "SHOT_DIR is set")
	DirAccess.make_dir_recursive_absolute(dir)
	var s := settings()
	var file: String = load("res://tests/test_front_end.gd").fixture(s)
	s.sim_jet = "f16i"
	var vp := SubViewport.new()
	vp.size = Vector2i(1920, 1080)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var fe: Control = load("res://main.tscn").instantiate()
	vp.add_child(fe)
	await frames(5)
	for lang in ["en", "he"]:
		s.language = lang
		s.pilot_name = "נועה גולן" if lang == "he" else "Noa Golan"
		s.sim_jet = ""
		fe.show_page("home")
		await frames(10)
		check(vp.get_texture().get_image().save_png(dir.path_join("home_first_%s.png" % lang)) == OK, "home_first")
		s.sim_jet = "f16i"
		for g in ["graphics", "sound", "devices", "language"]:
			fe.pref_group = g
			fe.show_page("prefs_section")
			await frames(10)
			var gp: String = dir.path_join("prefs_%s_%s.png" % [g, lang])
			check(vp.get_texture().get_image().save_png(gp) == OK, "saved " + gp)
		for p in SCREENS:
			if p == "debrief":
				fe.open_debrief(file)
			else:
				fe.mission_i = 1
				fe.show_page(p)
			await frames(10)
			var path: String = dir.path_join("%s_%s.png" % [p, lang])
			check(vp.get_texture().get_image().save_png(path) == OK, "saved " + path)
	s.language = "en"
	s.pilot_name = ""
