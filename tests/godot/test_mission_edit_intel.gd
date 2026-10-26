# The mission editor's intel and randomness (docs/mission-editor.md §14, §15) on a fork of 115: the "shown on the
# pilot's TSD" flag (0x35c) per unit and by the quick picks, kept by Save and Open with the briefing links and the
# random settings; the intel preview shows only known units; Fly (roll_seed fixed) gives the game the rolled mission (a
# 0 % tank gone), and its TSD shows only the known units and the briefing's links. Writes only under
# user://missions_test_intel.
extends "res://../tests/godot/base.gd"

const DIR := "user://missions_test_intel"


func _clean() -> void:
	if not DirAccess.dir_exists_absolute(DIR):
		return
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(f))
	DirAccess.remove_absolute(DIR)


func _keys(tsd) -> Array:
	return tsd.units.map(func(u): return String(u.key))


func run() -> void:
	await require_data()
	_clean()
	var ed = load("res://editor/mission_editor.tscn").instantiate()
	ed.missions_dir = DIR
	root.size = Vector2i(1600, 1000)
	root.add_child(ed)
	await frames(3)
	ed.open_original(115)
	check(ed.briefing.entries.size() == 6, "the original's 6 briefing links come with it")
	ed.fork("Intel 1")
	# Every red ground unit hidden, then tank t551 (4) shown.
	ed.set_known(ed.units_of(ed.KNOWN_KINDS[2][1], 2), false)
	ed.set_known(PackedInt64Array([4]), true)
	check(int(ed.entity(3)["0x35c"]) == 0 and int(ed.entity(4)["0x35c"]) == 1, "hide all red ground units, show 4")
	ed.set_intel_preview(true)
	var keys := _keys(ed.tsd)
	check(not ed.tsd.edit and "0:4" in keys and not "0:3" in keys, "intel preview: only known units")
	ed.set_intel_preview(false)
	check(ed.tsd.edit and "0:3" in _keys(ed.tsd), "edit view: every unit")
	# Links: the original's removed, the MiG-21's added from the mission's types.
	while not ed.briefing.entries.is_empty():
		ed.remove_link(0)
	var mig: Array = ed.api.intel_links(ed.data).filter(func(l): return "mig21" in String(l.file))
	check(mig.size() == 1, "the MiG-21 has a model link")
	ed.add_link(mig[0])
	ed.briefing.en = "Edited intel briefing"
	# Random: tank t552 (5) never appears, t553 (6) spreads 2 km; a target that may not appear warns.
	ed.set_random(PackedInt64Array([5]), 0.0, 0.0)
	ed.set_random(PackedInt64Array([6]), 100.0, 2.0)
	check(ed.issues.any(func(i): return int(i.id) == 5 and "not needed to pass" in String(i.text)), "target warning")
	ed.set_roll_preview(true)
	check(not "0:5" in _keys(ed.tsd), "roll preview: the 0 % tank is gone")
	ed.set_roll_preview(false)
	check("0:5" in _keys(ed.tsd), "back to the mission as edited")
	ed.save()
	var path: String = ed.file
	ed.open_file(path)
	check(int(ed.entity(3)["0x35c"]) == 0 and int(ed.entity(4)["0x35c"]) == 1, "the flags round-trip")
	check(ed.random.has("5") and float(ed.random["6"].spread_km) == 2.0, "the random settings round-trip")
	check(ed.briefing.entries.size() == 1 and ed.briefing.entries[0].file == mig[0].file, "the links round-trip")
	ed.roll_seed = 3
	var want: Dictionary = ed._fly_files()[0].data
	ed.fly(true)
	var fe: Node = null
	while fe == null or fe.get("tsd") == null:
		await process_frame
		fe = current_scene if current_scene != null and current_scene.has_method("_fly") else null
	await frames(3)
	var got: Dictionary = settings().mission_files_override[0].data
	check(got.hash() == want.hash() and ed.entity(5).size() > 0, "Fly gives the game the roll, the file keeps 5")
	check(got.entities.items.all(func(e): return int(e["0x1e"]) != 5), "the 0 % tank is not in the flown mission")
	var tsd = fe.tsd
	keys = _keys(tsd)
	check("0:4" in keys and not "0:3" in keys and not "0:6" in keys, "the TSD shows only known units: %s" % [keys])
	settings().language = "en"
	var b: Dictionary = tsd._briefing()
	check(tsd._link_names(b) == ["mig-21"], "the briefing's link (%s)" % [tsd._link_names(b)])
	check(tsd._text_of(b).ends_with("Intel: [u]MiG-21[/u]"), "listed in the text: %s" % tsd._text_of(b))
	tsd.open_briefing(true)
	tsd.brief_window.link_clicked.emit("mig-21")
	await frames(2)
	check(is_instance_valid(tsd.link_windows.get(2)), "the link opens the model window")
	ed.queue_free()
	_clean()
