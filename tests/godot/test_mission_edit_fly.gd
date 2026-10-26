# The mission editor's Fly (docs/mission-editor.md): mission 115 edited (Bravo's leader moved 5 km east, three jeeps
# given a 2 km route east at 36 km/h, an English and a Hebrew briefing) and flown through Settings.fly_edited as Bravo:
# mission_files gives the edited files, the front end opens the TSD with Bravo selected and the edited briefing (en,
# he), the player starts at the moved position, the jeeps drive their route at the speed, and IafMissionEdit's
# ground height matches the terrain's.
extends "res://../tests/godot/base.gd"


func run() -> void:
	await require_data()
	var rt = load("res://mission/mission_runtime.gd")
	IafMissionEdit.set_assets(settings().assets_dir())
	var files: Array = rt.mission_files(115)
	var main: Dictionary = files[0].data
	var at := Vector2.ZERO
	for e in main.entities.items:
		if int(e["0x1e"]) == 37:
			e["0x2e4"] = float(e["0x2e4"]) + 5000.0
			at = Vector2(float(e["0x2e4"]), float(e["0x2ee"]))
	var jeep := Vector2.ZERO
	for e in main.entities.items:
		if int(e["0x1e"]) == 29:
			jeep = Vector2(float(e["0x2e4"]), float(e["0x2ee"]))
	var route := PackedVector3Array([Vector3(jeep.x, jeep.y, 0), Vector3(jeep.x + 2000.0, jeep.y, 0)])
	var edited = JSON.parse_string(
		IafMissionEdit.set_route(JSON.stringify(main), PackedInt64Array([29, 30, 31]), route, 36.0, true)
	)
	files[0].data = edited
	var issues: Array = JSON.parse_string(IafMissionEdit.check(JSON.stringify(edited)))
	check(
		issues.filter(func(i): return i.level == "error").is_empty(),
		"the edited mission passes the Fly check (%s)" % [issues.filter(func(i): return i.level == "error")]
	)
	var brief := {"en": "Edited briefing EN [b]plain[/b]", "he": "תדריך ערוך"}
	settings().fly_edited(115, files, brief, 2, "user://missions/test.json")
	var fe: Node = null
	while fe == null or fe.get("tsd") == null:
		await process_frame
		fe = current_scene if current_scene != null and current_scene.has_method("_fly") else null
	await frames(3)
	var got: Array = rt.mission_files(115)
	check(
		got.size() == files.size() and got[0].data.hash() == edited.hash(), "mission_files(115) gives the edited files"
	)
	var tsd = fe.tsd
	check(fe.screen == "tsd" and tsd.sel_flight == 2, "the TSD opens with Bravo selected (%d)" % tsd.sel_flight)
	settings().language = "en"
	check(
		tsd._text_of(tsd._briefing()) == "Edited briefing EN [lb]b]plain[lb]/b]",
		"the English briefing is the edited one, as plain text"
	)
	settings().language = "he"
	check(tsd._text_of(tsd._briefing()) == brief.he, "the Hebrew briefing is the edited one")
	settings().language = "en"
	fe._fly()
	var tv: Node = null
	while tv == null or tv.get("flight") == null or tv.waiting_for_ground:
		await process_frame
		tv = current_scene
	check(tv.player_flight_number == 2, "the player flies Bravo")
	var p: Vector3 = tv.scene_to_world(tv.flight.state().position)
	check(Vector2(p.x, p.y).distance_to(at) < 100.0, "the player starts at the moved position (%s, %s)" % [p, at])
	var g = tv.terrain.height_at(tv.flight.state().position)
	var mine = IafMissionEdit.ground_height(p.x, p.y)
	check(
		g != null and mine != null and absf(float(g) - float(mine)) < 1.0, "ground height %s = terrain %s" % [mine, g]
	)
	var ent: Dictionary = tv.runtime.entities.get("0:29", {})
	check(not ent.is_empty() and ent.get("path") != null, "jeep 29 drives its route")
	if not ent.is_empty():
		var x0: float = ent.world.x
		await fly(tv, 5.0)
		var v: float = (ent.world.x - x0) / 5.0
		check(absf(v - 10.0) < 1.5 and absf(ent.world.y - jeep.y) < 1.0, "east at 36 km/h (%.1f m/s)" % v)
