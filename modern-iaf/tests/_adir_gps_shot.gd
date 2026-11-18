# The F-35I Adir's GPS bomb cues for its manual (ag-weapons.typ "The helmet's cues"): a GBU-31 in PRE at Nevatim,
# the jet level inside the release range, outside the minimum range, pointed at Target 1: TMR shows. A real render:
#   flock ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=<dir> -- \
#     --resolution 1920x1080 --path modern-iaf -s ../modern-iaf/tests/_adir_gps_shot.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

var tv: Node
var w


func _put(x: float, y: float, hdg := 0.0, up := 3000.0, speed := 220.0, pitch := 0.0) -> void:
	var g = tv.mission_ground(Vector3(x, y, 0.0))
	var pos: Vector3 = tv.world_to_scene(Vector3(x, y, float(g if g != null else 0.0) + up))
	var v := (
		Vector3(
			sin(deg_to_rad(hdg)) * cos(deg_to_rad(pitch)),
			sin(deg_to_rad(pitch)),
			-cos(deg_to_rad(hdg)) * cos(deg_to_rad(pitch))
		)
		* speed
	)
	tv.rig.position = pos
	tv.flight.start(settings().own_dir(), tv.player.fm_section, pos, Vector3(pitch, 0, hdg), v, airborne_flags())
	tv.gear_down = false
	tv.throttle = 0.85


func _tap(k: Key) -> void:
	for d in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.pressed = d
		tv._unhandled_input(e)


func run() -> void:
	await require_data()
	var s := settings()
	s.show_info = false
	var db: String = s.records_db()
	var rec := ProjectSettings.globalize_path("res://data/db/units/f35i.json")
	var lo: String = IafBriefing.put(rec, "", 4, "gbu-31", true)
	IafPilotLog.set_loadout(db, s.pilot(), "f35i", lo)
	var id := sim_mission("nevatim_range")
	load("res://flight/fly.gd").prepare(id)
	tv = await start_mission(id)
	s.mission_files_override = []
	IafPilotLog.set_loadout(db, s.pilot(), "f35i", "")
	tv.addon.result = {"pass": true}
	tv.addon.ui.visible = false
	w = tv.weapons
	var t1: Dictionary = {}
	for e in tv.runtime.entities.values():
		if String(e.get("name", "")) == "Target 1":
			t1 = e
	tv.views.set_cockpit(tv.views.COCKPIT)
	tv.in_cockpit = true
	tv._apply_view()
	_put(t1.world.x, t1.world.y - 20000.0, 0.0, 3000.0)
	await fly(tv, 3.0)
	_tap(KEY_R)
	await fly(tv, 2.5)
	w.select_ag()
	for i in 12:
		if String(w.stores.current_name()).to_lower().contains("gbu"):
			break
		_tap(KEY_BRACKETLEFT)
		await frames(2)
	# PRE aims at the route's Target 1: level at 3,000 m, 220 m/s, heading north at it; shoot when TMR / IN RNG show.
	var hud = tv.cockpit.hud
	tv.views.snap = Vector2.ZERO
	var start: float = tv._sim_time
	var seen := false
	while tv._sim_time - start < 120.0 and not seen:
		await fly(tv, 1.0)
		var d: Vector3 = t1.world - w.own().pos
		var texts := []
		for q in hud.real_hud().get("outer", []):
			if q.k == "text":
				texts.append(String(q.text))
		print("range ", int(Vector2(d.x, d.y).length()), " ", texts)
		seen = texts.any(func(t): return t == "IN RNG" or t.begins_with("TMR"))
	check(seen, "TMR or IN RNG shows")
	await fly(tv, 0.5)
	await _shot("helmet_gps")
	print("RESULT PASS" if seen else "RESULT FAIL")
	tv.queue_free()
	await frames(5)


func _shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png(OS.get_environment("SHOT_DIR").path_join(name + ".png"))
