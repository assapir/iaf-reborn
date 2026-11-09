# Real-render pictures of Modern IAF's front end, every screen in English and Hebrew (iaf-2026/docs/front-end.md):
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=/tmp/fe -- --log-file /tmp/fe.log --path iaf-2026 \
#     -s ../iaf-2026/tests/_front_end_shot.gd
# Writes SHOT_DIR/<screen>_<lang>.png (the Preferences: prefs_<section>_*) at 1920×1080 (the
# front end in a viewport of that size, whatever the window's) with the sample pilot log and debrief of
# test_front_end.gd (debrief_fail: its take-off with the gear never raised).
extends "res://../tests/godot/base.gd"

const SCREENS := ["home", "plane", "training", "mission", "debrief", "debrief_fail", "log", "credits"]


func run() -> void:
	var dir := OS.get_environment("SHOT_DIR")
	check(dir != "", "SHOT_DIR is set")
	DirAccess.make_dir_recursive_absolute(dir)
	var s := settings()
	var ids: Dictionary = load("res://tests/test_front_end.gd").fixture(s)
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
		s.sim_jet = "f16i"
		for g in ["graphics", "sound", "devices", "language"]:
			fe.pref_group = g
			fe.show_page("prefs")
			await frames(10)
			var gp: String = dir.path_join("prefs_%s_%s.png" % [g, lang])
			check(vp.get_texture().get_image().save_png(gp) == OK, "saved " + gp)
		for p in SCREENS:
			if p == "debrief":
				fe.open_debrief(ids.pass)
			elif p == "debrief_fail":
				fe.open_debrief(ids.fail)
			else:
				fe.mission_i = 1
				fe.show_page(p)
			await frames(10)
			var path: String = dir.path_join("%s_%s.png" % [p, lang])
			check(vp.get_texture().get_image().save_png(path) == OK, "saved " + path)
		await _pilot(fe, vp, dir, lang)
	s.language = "en"
	s.pilot_name = ""


## The Pilot screen with a sample profile (a drawn silhouette as its picture), then the profile put back.
func _pilot(fe: Control, vp: SubViewport, dir: String, lang: String) -> void:
	var s := settings()
	var db: String = s.records_db()
	s.pilot_name = ""
	var he := lang == "he"
	IafPilotLog.set_pilot(db, s.pilot(), "נועה גולן" if he else "Noa Golan", "נועה" if he else "Noa")
	var png := OS.get_temp_dir().path_join("iaf2026-shot-pilot-%d.png" % OS.get_process_id())
	_silhouette().save_png(png)
	fe.show_page("pilot")
	fe.set_picture(png)
	await frames(10)
	var path: String = dir.path_join("pilot_%s.png" % lang)
	check(vp.get_texture().get_image().save_png(path) == OK, "saved " + path)
	IafPilotLog.set_pilot(db, s.pilot(), "", "")
	IafPilotLog.set_picture(db, s.pilot(), "")
	DirAccess.remove_absolute(png)


## A sample ID photo, 600 × 800: a head and shoulders in slate on a blue-grey ground.
static func _silhouette() -> Image:
	var img := Image.create(600, 800, false, Image.FORMAT_RGB8)
	var dark := Color("2b3440")
	for y in 800:
		var ground := Color("9fb3c8").lerp(Color("5d7186"), y / 800.0)
		for x in 600:
			var head := Vector2(x - 300, y - 310).length() < 130
			var neck := absi(x - 300) < 40 and y > 400
			var body := Vector2((x - 300) / 260.0, (y - 820) / 260.0).length() < 1.0
			img.set_pixel(x, y, dark if head or neck or body else ground)
	return img
