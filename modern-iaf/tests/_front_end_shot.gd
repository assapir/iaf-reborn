# Real-render pictures of Modern IAF's front end, every screen in English and Hebrew (modern-iaf/docs/front-end.md):
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=/tmp/fe -- --log-file /tmp/fe.log --path modern-iaf \
#     -s ../modern-iaf/tests/_front_end_shot.gd
# Writes SHOT_DIR/<screen>_<lang>.png (free: the Scramble screen; free_time, free_random: its Date and time row at 2215
# on day 172 (21 June in 2026) and Random; the Settings: prefs_<section>_*, prefs_about_* (the pane on Buildings and
# trees), prefs_search_*; the Pilot screens: _pilot) at 1920×1080 (the front end in a viewport of that size, whatever
# the window's) with the sample pilot log and debrief of test_front_end.gd (debrief: the sample flight; debrief_fail: a
# record from before the goals and the recording, its take-off with the gear never raised; fly_again: the debrief's Fly
# again; log_filtered: the Pilot log filtered to one mission; hangar_<lang>.json: the boxes of MARKS, the manual's
# numbers). SHOT_ONLY=<screens> takes those alone (comma-separated, e.g. SHOT_ONLY=missions,section; SHOT_ONLY=pilot the
# Pilot screens); SHOT_SIZE=1280x720 renders at that size (the 1920 × 1080 canvas scaled to it). nodata_hangar /
# nodata_missions: a fresh install (IAF_ASSETS_DIR an empty folder for those two).
# SHOT_JET=<unit> picks that jet in the Hangar (the Sufa, f16i, if unset).
extends "res://../tests/godot/base.gd"

const SCREENS := [
	"hangar",
	"missions",
	"free",
	"free_time",
	"free_random",
	"section",
	"mission",
	"debrief",
	"debrief_fail",
	"fly_again",
	"log",
	"log_filtered",
	"credits"
]

# The game manual's numbered parts of a screen (modern-iaf/docs/manuals.md §4): screen -> the nodes whose boxes are
# written to SHOT_DIR/<screen>_<lang>.json.
const MARKS := {
	"hangar": ["CrumbOn", "Settings", "PilotBlock", "Jets", "Turntable", "JetCard", "Fly", "credits", "manuals", "quit"]
}


func run() -> void:
	var dir := OS.get_environment("SHOT_DIR")
	check(dir != "", "SHOT_DIR is set")
	DirAccess.make_dir_recursive_absolute(dir)
	var only := OS.get_environment("SHOT_ONLY")
	var s := settings()
	var ids: Dictionary = load("res://tests/test_front_end.gd").fixture(s)
	s.sim_jet = "f16i"
	var vp := SubViewport.new()
	var size := OS.get_environment("SHOT_SIZE").split("x")
	vp.size = Vector2i(int(size[0]), int(size[1])) if size.size() == 2 else Vector2i(1920, 1080)
	vp.size_2d_override = Vector2i(1920, 1080)
	vp.size_2d_override_stretch = true
	vp.oversampling_override = vp.size.y / 1080.0
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var fe: Control = load("res://main.tscn").instantiate()
	vp.add_child(fe)
	await frames(5)
	for lang in ["en", "he"]:
		s.language = lang
		s.pilot_name = "נועה גולן" if lang == "he" else "Noa Golan"
		s.sim_jet = OS.get_environment("SHOT_JET") if OS.has_environment("SHOT_JET") else "f16i"
		for g in ["graphics", "sound", "devices", "language", "updates"] if only == "" or "prefs" in only.split(",") else []:
			fe.pref_group = g
			fe.pref_search = ""
			fe.show_page("prefs")
			await _shot(vp, dir, "prefs_%s_%s" % [g, lang])
			if g == "graphics":
				# The pane on a setting with its Off / On picture (the mock's Buildings and trees), then a search.
				fe._about("scenery")
				await _shot(vp, dir, "prefs_about_" + lang)
				fe.pref_search = "צל" if lang == "he" else "shadow"
				fe.show_page("prefs")
				await _shot(vp, dir, "prefs_search_" + lang)
				fe.pref_search = ""
		for p in Array(only.split(",")).filter(func(x): return x != "prefs") if only != "" else SCREENS:
			if p == "debrief":
				fe.open_debrief(ids.pass)
			elif p == "debrief_fail":
				fe.open_debrief(ids.fail)
			elif p == "fly_again":  # the debrief's Fly again: the flown mission's briefing
				fe.open_debrief(ids.pass)
				await frames(2)
				fe.find_child("FlyAgain", true, false).pressed.emit()
			elif p == "free":
				s.free_combat = {}
				fe.FreeCombatPage.reset()
				fe.show_page("free")
			elif p in ["free_time", "free_random"]:  # 2215 on 21 June 2026, then both with Random
				fe.FreeCombatPage.when = {
					"time": 22 * 60 + 15,
					"time_random": p == "free_random",
					"date": 172,
					"date_random": p == "free_random"
				}
				fe.show_page("free")
			elif p == "log_filtered":  # the Pilot log filtered to the last flight's mission
				var att: Array = fe.sorties()
				fe.log_mission = int(att[-1].mission_id)
				fe.show_page("log")
				fe.log_mission = -1
			else:
				fe.section = "training"
				fe.mission_i = 1
				fe.show_page(p)
			await frames(10)
			var path: String = dir.path_join("%s_%s.png" % [p, lang])
			check(vp.get_texture().get_image().save_png(path) == OK, "saved " + path)
			if p in MARKS:
				_marks(fe, dir.path_join("%s_%s.json" % [p, lang]), MARKS[p])
		if only == "" or "pilot" in only.split(","):
			await _pilot(fe, vp, dir, lang)
		if only == "":
			await _no_data(fe, vp, dir, lang)
	s.language = "en"
	s.pilot_name = ""


## The Pilot screens with a sample profile and no picture (the game's default, the initials): the first start's
## (pilot_first), the Pilot screen with the sample log's logbook (pilot), the Reset's warning (pilot_reset), the pilot
## list with a second pilot (pilots) and the Hangar with the name and nickname (hangar_pilot); then the profile put
## back.
func _pilot(fe: Control, vp: SubViewport, dir: String, lang: String) -> void:
	var s := settings()
	var db: String = s.records_db()
	s.pilot_name = ""
	var he := lang == "he"
	IafPilotLog.set_pilot(db, s.pilot(), "", "")
	fe.show_page("hangar")
	await _shot(vp, dir, "pilot_first_" + lang)
	IafPilotLog.set_pilot(db, s.pilot(), "נועה גולן" if he else "Noa Golan", "עקרב" if he else "Viper")
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


## A fresh install: the Hangar and the mission screen with an empty assets folder (IAF_ASSETS_DIR), then the real one.
func _no_data(fe: Control, vp: SubViewport, dir: String, lang: String) -> void:
	var was := OS.get_environment("IAF_ASSETS_DIR")
	var empty := OS.get_temp_dir().path_join("iaf2026-shot-no-data-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(empty)
	OS.set_environment("IAF_ASSETS_DIR", empty)
	settings().sim_jet = "f16i"
	settings().pilot_name = "נועה גולן" if lang == "he" else "Noa Golan"  # _pilot left no profile
	for p in ["hangar", "missions"]:
		fe.show_page(p)
		await _shot(vp, dir, "nodata_%s_%s" % [p, lang])
	if was != "":
		OS.set_environment("IAF_ASSETS_DIR", was)
	else:
		OS.unset_environment("IAF_ASSETS_DIR")
	DirAccess.remove_absolute(empty)
	settings().pilot_name = ""


## The boxes on the 1920 × 1080 canvas, as fractions of the picture ([left, top, right, bottom]): `parts`, each node of
## `nodes` (a picture's drawn part only: the turntable's jet, not its empty frame); `busy`, every other text, button and
## picture shown, where the manual draws no number.
func _marks(fe: Control, path: String, nodes: Array) -> void:
	var parts := {}
	for n in nodes:
		var c: Control = fe.find_child(n, true, false)
		check(c != null, "node " + n)
		parts[n] = _box(_drawn(c))
	var busy := []
	for c in fe.find_children("*", "Control", true, false):
		if c.name in nodes or not c.is_visible_in_tree() or not (c is Label or c is BaseButton or c is TextureRect):
			continue
		if c is Label and c.get_theme_color("font_color").a < 0.2:
			continue  # a faint backdrop text (the Hangar's jet name)
		var r := _drawn(c)
		if r.get_area() > 0 and r.size.x < 960 and r.size.y < 540:  # not a backdrop (the top bar's shade)
			busy.append(_box(r))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"parts": parts, "busy": busy}, "", false))
	f.close()


## `c`'s box on the canvas; a picture with a transparent ground (the turntable) only where it draws.
func _drawn(c: Control) -> Rect2:
	var r := c.get_global_rect()
	if c is TextureRect and c.texture != null:
		var img: Image = c.texture.get_image()
		if img != null and img.detect_alpha() != Image.ALPHA_NONE:
			var u := img.get_used_rect()
			var k := r.size / Vector2(img.get_size())
			r = Rect2(r.position + Vector2(u.position) * k, Vector2(u.size) * k)
	return r


static func _box(r: Rect2) -> Array:
	return [r.position.x / 1920.0, r.position.y / 1080.0, r.end.x / 1920.0, r.end.y / 1080.0].map(
		func(v): return snappedf(v, 0.0001)
	)


func _shot(vp: SubViewport, dir: String, name: String) -> void:
	await frames(10)
	var path: String = dir.path_join(name + ".png")
	check(vp.get_texture().get_image().save_png(path) == OK, "saved " + path)
