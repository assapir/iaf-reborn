# Dev helper (not run by tools/test.sh): a real-render capture of the Debrief screen (docs/front-end.md §13.14)
# after a real mission DEB_MISSION (default 115): up to DEB_PER_TYPE (2) enemy units of each type and the player's
# jet are set destroyed, the flight ends through DEBRIEF, and each tab (Debriefing / Kill Tally / Losses) is saved
# as DEB_SHOT with _0 / _1 / _2 before ".png", in DEB_LANG (en / he).
#   DEB_LANG=he DEB_SHOT=/tmp/deb.png IAF_DEFAULT_SETTINGS=1 godot --path game --resolution 1280x960 -s \
#     ../tests/godot/_debrief_shot.gd
extends "res://../tests/godot/base.gd"


func run() -> void:
	settings().language = OS.get_environment("DEB_LANG") if OS.get_environment("DEB_LANG") != "" else "en"
	var id := int(OS.get_environment("DEB_MISSION")) if OS.get_environment("DEB_MISSION") != "" else 115
	var per := int(OS.get_environment("DEB_PER_TYPE")) if OS.get_environment("DEB_PER_TYPE") != "" else 2
	var tv = await start_mission(id)
	var rt = tv.runtime
	var p: Dictionary = rt.player_entity()
	var seen := {}
	for ent in rt.entities.values():
		if ent == p:
			ent.state = 4
		elif ent.side != p.side and int(seen.get(ent.type_code, 0)) < per:
			seen[ent.type_code] = int(seen.get(ent.type_code, 0)) + 1
			ent.state = 4
	tv._end_flight(true)
	var fe: Control = null
	while fe == null or fe.get("debrief_view") == null or fe.busy or fe.panel_shown < 1.0:
		await process_frame
		fe = current_scene as Control
	# Shows our EXPORT FLIGHT DATA button (it needs this flight's recording; any existing file will do here).
	settings().blackbox_file = "res://project.godot"
	var path := OS.get_environment("DEB_SHOT")
	print("debrief: ", settings().debrief.stats)
	for t in 3:
		fe.debrief_view.tab = t
		await frames(5)
		await RenderingServer.frame_post_draw
		var out := path.get_basename() + "_%d.png" % t
		root.get_viewport().get_texture().get_image().save_png(out)
		print("saved ", out)
