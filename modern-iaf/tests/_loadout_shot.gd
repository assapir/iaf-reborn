# Real-render pictures of the loadout editor on the briefing's Arming page (modern-iaf/docs/front-end.md §10), the
# Sufa's take-off at Ramon and the Adir's at Nevatim, in English and Hebrew:
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=/tmp/lo -- --log-file /tmp/lo.log --path modern-iaf \
#     -s ../modern-iaf/tests/_loadout_shot.gd
# Writes SHOT_DIR/<jet>_<lang>_drag.png (a bomb dragged over its station: the slots that take it framed, the others
# dimmed), _refused_hover.png (a store held over a station that does not take it), _refused_shake.png (that drop
# refused: the slot mid-shake), _over.png (a heavy loadout against a maximum lowered for the picture: no sourced
# loadout reaches the real one; the take-off weight red, Fly off), _inventory.png (the record's loadout beside the
# whole inventory, two to a row by group), _rack.png (racks: three Mk 82 on a TER on the Sufa's 3 / 7, four GBU-39 on
# a BRU-61 in the Adir's bays 4 / 8, each slot's "×n" badge), at 1920×1080.
extends "res://../tests/godot/base.gd"

## jet → [the store dragged, its station, a store its target refuses, that station, the heavy loadout, the lowered
## maximum (kg)].
const CASES := {
	"f16i": ["mk-84", "3", "tank-370", "2", [[3, "mk-84"], [2, "aim-120"]], 17000, [[3, "mk-82"]]],
	"f35i": ["gbu-31", "4", "gbu-31", "5", [[4, "gbu-31"], [3, "gbu-31"]], 24000, [[4, "gbu-39"], [1, "aim-9x"]]],
}

var vp: SubViewport
var fe: Control
var dir := ""


func run() -> void:
	dir = OS.get_environment("SHOT_DIR")
	check(dir != "", "SHOT_DIR is set")
	DirAccess.make_dir_recursive_absolute(dir)
	var s := settings()
	load("res://tests/test_front_end.gd").fixture(s)
	vp = SubViewport.new()
	vp.size = Vector2i(1920, 1080)
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
			_live("Drawing").dropped({"store": c[2], "from": ""}, c[3])
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
			# Racks.
			lo = ""
			for p in c[6]:
				lo = IafBriefing.put(u, lo, p[0], p[1], true)
			IafPilotLog.set_loadout(db, s.pilot(), jet, lo)
			await _open(jet)
			await _save("%s_%s_rack" % [jet, lang])
			IafPilotLog.set_loadout(db, s.pilot(), jet, "")
	s.language = "en"
	s.pilot_name = ""


## The jet's take-off on the Arming page.
func _open(jet: String) -> void:
	var s := settings()
	s.sim_jet = jet
	fe.show_page("mission")
	fe.mission_i = fe.missions.map(func(x): return str(x.get("id", "")).ends_with("_takeoff")).find(true)
	fe.brief_tab = 2  # entering the screen opens Briefing; the tab kept while it stays
	fe.show_page("mission")
	await frames(10)


## Store `id` dragged (from the inventory) and held over station `to`: the drawing's state for that pointer
## (show_drag; a SubViewport's pushed pointer moves reach it late and out of order).
func _drag(id: String, to: String) -> void:
	var drawing: Control = _live("Drawing")
	drawing.show_drag(id, drawing.slots[to].get_global_rect().get_center() + Vector2(10, 4))
	await frames(4)


## The drag over.
func _drop() -> void:
	_live("Drawing").show_drag("", Vector2.ZERO)
	await frames(2)


## The node named `name` on the page shown (not one of a page being freed).
func _live(name: String) -> Node:
	for n in fe.find_children(name, "", true, false):
		if not n.is_queued_for_deletion():
			return n
	return null


func _save(what: String) -> void:
	await frames(2)
	var path := dir.path_join(what + ".png")
	check(vp.get_texture().get_image().save_png(path) == OK, "saved " + path)
