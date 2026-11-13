# Real-render pictures of Modern IAF's front end, every screen in English and Hebrew (modern-iaf/docs/front-end.md):
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=/tmp/fe -- --log-file /tmp/fe.log --path modern-iaf \
#     -s ../modern-iaf/tests/_front_end_shot.gd
# Writes SHOT_DIR/<screen>_<lang>.png (the Preferences: prefs_<section>_*; the Pilot screens: _pilot) at 1920×1080 (the
# front end in a viewport of that size, whatever the window's) with the sample pilot log and debrief of
# test_front_end.gd (debrief_fail: its take-off with the gear never raised; fly_again: the debrief's Fly again).
# SHOT_ONLY=<screen> takes that screen alone (e.g. SHOT_ONLY=hangar).
extends "res://../tests/godot/base.gd"

const SCREENS := ["hangar", "mission", "debrief", "debrief_fail", "fly_again", "log", "credits"]


func run() -> void:
	var dir := OS.get_environment("SHOT_DIR")
	check(dir != "", "SHOT_DIR is set")
	DirAccess.make_dir_recursive_absolute(dir)
	var only := OS.get_environment("SHOT_ONLY")
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
		for g in [] if only != "" else ["graphics", "sound", "devices", "language"]:
			fe.pref_group = g
			fe.show_page("prefs")
			await frames(10)
			var gp: String = dir.path_join("prefs_%s_%s.png" % [g, lang])
			check(vp.get_texture().get_image().save_png(gp) == OK, "saved " + gp)
		for p in [only] if only != "" else SCREENS:
			if p == "debrief":
				fe.open_debrief(ids.pass)
			elif p == "debrief_fail":
				fe.open_debrief(ids.fail)
			elif p == "fly_again":  # the debrief's Fly again: the flown mission's briefing
				fe.open_debrief(ids.pass)
				await frames(2)
				fe.find_child("FlyAgain", true, false).pressed.emit()
			else:
				fe.mission_i = 1
				fe.show_page(p)
			await frames(10)
			var path: String = dir.path_join("%s_%s.png" % [p, lang])
			check(vp.get_texture().get_image().save_png(path) == OK, "saved " + path)
		if only == "":
			await _pilot(fe, vp, dir, lang)
	s.language = "en"
	s.pilot_name = ""


## The Pilot screens with a sample profile (a drawn silhouette as its picture): the first start's (pilot_first), the
## Pilot screen with the sample log's logbook (pilot), the Reset's warning (pilot_reset), the pilot list with a second
## pilot (pilots) and the Hangar with the name, nickname and picture (hangar_pilot); then the profile put back.
func _pilot(fe: Control, vp: SubViewport, dir: String, lang: String) -> void:
	var s := settings()
	var db: String = s.records_db()
	s.pilot_name = ""
	var he := lang == "he"
	IafPilotLog.set_pilot(db, s.pilot(), "", "")
	fe.show_page("hangar")
	await _shot(vp, dir, "pilot_first_" + lang)
	IafPilotLog.set_pilot(db, s.pilot(), "נועה גולן" if he else "Noa Golan", "עקרב" if he else "Viper")
	var png := OS.get_temp_dir().path_join("iaf2026-shot-pilot-%d.png" % OS.get_process_id())
	_silhouette().save_png(png)
	IafPilotLog.set_picture(db, s.pilot(), png)
	fe.show_page("credits")
	fe.show_page("pilot")
	await _shot(vp, dir, "pilot_" + lang)
	fe.reset_log()
	await _shot(vp, dir, "pilot_reset_" + lang)
	fe.close_modal()
	var other: int = IafPilotLog.add_pilot(db, "דנה לוי" if he else "Dana Levi", "")
	fe.show_page("pilots")
	await _shot(vp, dir, "pilots_" + lang)
	fe.show_page("hangar")
	await _shot(vp, dir, "hangar_pilot_" + lang)
	IafPilotLog.set_pilot(db, other, "", "")
	IafPilotLog.set_pilot(db, s.pilot(), "", "")
	IafPilotLog.set_picture(db, s.pilot(), "")
	DirAccess.remove_absolute(png)


func _shot(vp: SubViewport, dir: String, name: String) -> void:
	await frames(10)
	var path: String = dir.path_join(name + ".png")
	check(vp.get_texture().get_image().save_png(path) == OK, "saved " + path)


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
