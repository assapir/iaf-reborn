# Real-render pictures of the Loadout screen (modern-iaf/docs/front-end.md §10), the Sufa's take-off at Ramon and the
# Adir's at Nevatim, in English and Hebrew:
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=/tmp/lo -- --log-file /tmp/lo.log --path modern-iaf \
#     -s ../modern-iaf/tests/_loadout_shot.gd
# Writes SHOT_DIR/<jet>_<lang>_inventory.png (the mission's loadout, a saved one on the list), _drag.png (a bomb dragged
# over its station: the callouts that take it framed, the others dimmed), _refused_hover.png (a store held over a
# station that does not take it), _refused_shake.png (that drop refused: the callout mid-shake), _over.png (a heavy
# loadout against a maximum lowered for the picture: no sourced loadout reaches the real one; the take-off weight red,
# Fly off), _one_side.png (one station edited, Mirror off: the wings' balance off centre), _rack.png (racks, every
# store drawn: two GBU-38 on a BRU-57/A on the Sufa's 3 / 7 and three Mk 82 on a TER-9/A on 4 / 6, four GBU-39 on a
# BRU-61 in the Adir's bays 4 / 8, each callout's "×n" badge), at SHOT_SIZE (default 1920x1080; the file names then
# end _<width>).
extends "res://../tests/godot/base.gd"

## jet → [the store dragged, its station, a store its target refuses, that station, the heavy loadout, the lowered
## maximum (kg)].
const CASES := {
	"f16i": ["mk-84", "3", "tank-370", "2", [[3, "mk-84"], [2, "aim-120"]], 17000, [[3, "gbu-38"], [4, "mk-82"]]],
	"f35i": ["gbu-31", "4", "gbu-31", "5", [[4, "gbu-31"], [3, "gbu-31"]], 24000, [[4, "gbu-39"], [1, "aim-9x"]]],
}

var vp: SubViewport
var fe: Control
var dir := ""
var suffix := ""


func run() -> void:
	dir = OS.get_environment("SHOT_DIR")
	check(dir != "", "SHOT_DIR is set")
	DirAccess.make_dir_recursive_absolute(dir)
	var s := settings()
	load("res://tests/test_front_end.gd").fixture(s)
	vp = SubViewport.new()
	var want := OS.get_environment("SHOT_SIZE").split("x")
	vp.size = Vector2i(int(want[0]), int(want[1])) if want.size() == 2 else Vector2i(1920, 1080)
	suffix = "" if vp.size.x == 1920 else "_%d" % vp.size.x
	# The front end lays out on its 1920×1080 canvas, scaled to the picture as the window scales it.
	vp.size_2d_override = Vector2i(1920, 1080)
	vp.size_2d_override_stretch = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	fe = load("res://main.tscn").instantiate()
	vp.add_child(fe)
	await frames(5)
	var db: String = s.records_db()
	for lang in ["en", "he"]:
		s.language = lang
		s.pilot_name = "נועה גולן" if lang == "he" else "Noa Golan"
		for jet in CASES:
			var c: Array = CASES[jet]
			IafPilotLog.set_loadout(db, s.pilot(), jet, "")
			# A saved loadout on the list: the heavy one, under a name of the pilot's.
			var rec_path := ProjectSettings.globalize_path("res://data/db/units/%s.json" % jet)
			var heavy := ""
			for p in c[4]:
				heavy = IafBriefing.put(rec_path, heavy, p[0], p[1], true)
			var title := "תקיפה" if lang == "he" else "Strike"
			var kept: int = IafPilotLog.save_loadout(db, s.pilot(), jet, title, heavy)
			await _open(jet)
			await _save("%s_%s_inventory" % [jet, lang])
			# A drag in progress: the store from the inventory over its station.
			await _drag(c[0], c[1])
			await _save("%s_%s_drag" % [jet, lang])
			await _drop()
			# A refused drop: held over a station that does not take it, then let go there.
			await _drag(c[2], c[3])
			await _save("%s_%s_refused_hover" % [jet, lang])
			await _drop()
			_live("Stage").dropped({"store": c[2], "from": ""}, c[3])
			await frames(3)
			await _save("%s_%s_refused_shake" % [jet, lang])
			await create_timer(0.5).timeout
			# Over a lowered maximum.
			var u := ProjectSettings.globalize_path("res://data/db/units/%s.json" % jet)
			var lo := ""
			for p in c[4]:
				lo = IafBriefing.put(u, lo, p[0], p[1], true)
			IafPilotLog.set_loadout(db, s.pilot(), jet, lo)
			var tmp := OS.get_temp_dir().path_join("modern-iaf-shot-units")
			DirAccess.make_dir_recursive_absolute(tmp)
			var rec: Dictionary = s.load_json(u)
			rec["max_takeoff_kg"] = c[5]
			FileAccess.open(tmp.path_join(jet + ".json"), FileAccess.WRITE).store_string(JSON.stringify(rec))
			fe.units_dir = tmp
			await _open(jet)
			await _save("%s_%s_over" % [jet, lang])
			fe.units_dir = "res://data/db/units"
			# One station edited (Mirror off): the store on the dragged one's station alone, the wings uneven.
			IafPilotLog.set_loadout(db, s.pilot(), jet, IafBriefing.put(u, "", int(c[1]), c[0], false))
			await _open(jet)
			await _save("%s_%s_one_side" % [jet, lang])
			# Racks.
			lo = ""
			for p in c[6]:
				lo = IafBriefing.put(u, lo, p[0], p[1], true)
			IafPilotLog.set_loadout(db, s.pilot(), jet, lo)
			await _open(jet)
			await _save("%s_%s_rack" % [jet, lang])
			IafPilotLog.set_loadout(db, s.pilot(), jet, "")
			IafPilotLog.delete_saved_loadout(db, s.pilot(), kept)
	s.language = "en"
	s.pilot_name = ""


## The jet's take-off on the Loadout screen.
func _open(jet: String) -> void:
	var s := settings()
	s.sim_jet = jet
	fe.show_page("mission")
	fe.mission_i = fe.missions.map(func(x): return str(x.get("id", "")).ends_with("_takeoff")).find(true)
	await frames(2)  # the briefing's deferred map aim runs before its screen goes
	fe.show_page("arming")
	await frames(10)


## Store `id` dragged (from the inventory) and held over station `to`: the drawing's state for that pointer
## (show_drag; a SubViewport's pushed pointer moves reach it late and out of order).
func _drag(id: String, to: String) -> void:
	var drawing: Control = _live("Stage")
	drawing.show_drag(id, drawing.slots[to].get_global_rect().get_center() + Vector2(10, 4))
	await frames(4)


## The drag over.
func _drop() -> void:
	_live("Stage").show_drag("", Vector2.ZERO)
	await frames(2)


## The node named `name` on the page shown (not one of a page being freed).
func _live(name: String) -> Node:
	for n in fe.find_children(name, "", true, false):
		if not n.is_queued_for_deletion():
			return n
	return null


func _save(what: String) -> void:
	await frames(2)
	var path := dir.path_join(what + suffix + ".png")
	check(vp.get_texture().get_image().save_png(path) == OK, "saved " + path)
