# The mission editor's enemy flight (docs/mission-editor.md §12): a mission from scratch on 1998's original (231) with
# a pair of MiG-29s added by IafMissionEdit.set_red_flight at Damascus, Damascus' base mission with it. Flown through
# Settings.mission_files_override: the MiG-29s spawn as AI jets at Damascus, take off and fly their route.
extends "res://../tests/godot/base.gd"


func run() -> void:
	var rt = load("res://mission/mission_runtime.gd")
	IafMissionEdit.set_assets(settings().assets_dir())
	var files: Array = rt.mission_files(231)
	var main = JSON.parse_string(IafMissionEdit.blank(JSON.stringify(files[0].data)))
	var alpha := {"type": 1, "count": 1, "slot_x": 356404.0, "slot_y": 602402.0, "alt": 3000.0, "heading": 270.0}
	main = JSON.parse_string(IafMissionEdit.set_flight(JSON.stringify(main), 1, JSON.stringify(alpha)))
	# A red jet of an original as the template (the editor passes its own template for the type).
	var template := {}
	for e in settings().load_json(settings().assets_dir().path_join("converted/missions/license.json")).entities.items:
		if int(e.get("0x2d0", 0)) == 2 and int(e.get("0x2c6", -1)) == 11:
			template = e
	var spec := {"type": 2, "count": 2, "base": "bmisdmsk", "name": "MiG-29", "template": template}
	main = JSON.parse_string(IafMissionEdit.set_red_flight(JSON.stringify(main), JSON.stringify(spec)))
	var year: Array = JSON.parse_string(IafMissionEdit.year_issues(JSON.stringify(main), 1998.0, false))
	check(year.is_empty(), "MiG-29s from Damascus fit 1998 (%s)" % [year])
	files[0].data = main
	files.append(
		{
			"name": "bmisdmsk",
			"data": settings().load_json(settings().assets_dir().path_join("converted/missions/bmisdmsk.json"))
		}
	)
	settings().mission_files_override = files
	var tv = await start_mission(231)
	await frames(3)
	var migs: Array = tv.ai.pilots.filter(func(p): return String(p.ent.name).begins_with("MiG-29"))
	check(migs.size() == 2, "two MiG-29s flown by the AI (%d)" % migs.size())
	if migs.is_empty():
		settings().mission_files_override = []
		return
	var lead = migs[0]
	var p0: Vector3 = lead.ent.world
	check(Vector2(p0.x, p0.y).distance_to(Vector2(450815, 699907)) < 200.0, "the leader starts at Damascus (%s)" % p0)
	Engine.time_scale = 8.0
	var t0: float = tv.runtime.now
	while tv.runtime.now - t0 < 150.0:
		await process_frame
	Engine.time_scale = 1.0
	var p1: Vector3 = lead.ent.world
	print("  %s wp %d alt %.0f moved %.0f m" % [lead.ent.name, lead.waypoint_index(), p1.z, (p1 - p0).length()])
	check(not lead.state().on_ground and p1.z > 889.0 + 100.0, "the leader took off (alt %.0f)" % p1.z)
	check((p1 - p0).length() > 5000.0, "and flies its route (%.0f m)" % (p1 - p0).length())
	settings().mission_files_override = []
