# Dev helper (not run by tools/test.sh): real-render pictures of the weapons range (training.md §3.4) with the
# Graphics preset "Everything on", 1920 wide:
# - range_list_<lang>.png: the Sufa's Training list with the range focused (English, Hebrew);
# - range_gps_<lang>.png: its briefing with a GBU-38 on station 3 and Target 2 picked (only where the briefing has the
#   GPS TARGETS box, the pick's branch);
# - range_radar.png, range_radar_hud.png: 15 km behind Drone 1 at its height, the radar in CRM (the cockpit, the FCR);
# - range_drone.png: 300 m behind Drone 1 from the cockpit;
# - range_targets.png: the ground targets ahead from 1,500 m;
# - range_debrief_<lang>.png: the debrief after a gun kill.
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=<dir> -- --log-file <temp> --resolution 1920x1080 \
#     --path modern-iaf -s ../modern-iaf/tests/_range_shot.gd
extends "res://../tests/godot/base.gd"

var dir := ""
var main_scene: PackedScene
var fe: Control


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "needs a window")
		return
	await require_data()
	dir = OS.get_environment("SHOT_DIR")
	main_scene = load("res://main.tscn")
	DirAccess.make_dir_recursive_absolute(dir)
	var s := settings()
	load("res://tests/test_front_end.gd").fixture(s)
	s.pilot_name = "Noa Golan"
	s.show_info = false
	var p: Dictionary = load("res://shared/util/pref_choices.gd").preset("everything")
	for k in p:
		s.set(k, p[k])
	var rec := ProjectSettings.globalize_path("res://data/db/units/f16i.json")
	IafPilotLog.set_loadout(s.records_db(), s.pilot(), "f16i", IafBriefing.put(rec, "", 3, "gbu-38", true))
	s.sim_jet = "f16i"
	var id := 0
	fe = main_scene.instantiate()
	root.add_child(fe)
	await frames(5)
	for lang in ["en", "he"]:
		s.language = lang
		s.pilot_name = "נועה גולן" if lang == "he" else "Noa Golan"
		fe.section = "training"
		fe.show_page("section")
		await frames(4)
		var i: int = fe.missions.map(func(m): return str(m.id)).find("ramon_range")
		id = int(fe.missions[i].menu_id)
		fe.find_child("List", true, false).get_child(i).grab_focus()
		await frames(6)
		await _save("range_list_" + lang)
		fe.open_mission(i)
		await frames(20)
		var row: Button = fe.find_child("Gps_3", true, false)
		if row != null:
			row.pressed.emit()
			var map: Control = fe.find_child("PageMap", true, false)
			await frames(10)
			await _save("range_gps_armed_" + lang)
			map.target_picked.emit(1)
			await frames(30)
			await _save("range_gps_" + lang)
		fe.show_page("section")
		await frames(3)
	fe.visible = false
	s.language = "en"
	await _flight(id)


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := dir.path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("shot ", path)


func _put(tv: Node, pos: Vector3, vel: Vector3, hdg: float, pitch := 0.0) -> void:
	tv.rig.position = pos
	tv.flight.start(settings().own_dir(), tv.player.fm_section, pos, Vector3(pitch, 0, hdg), vel, airborne_flags())
	tv.gear_down = false
	tv.throttle = 0.85


func _key(tv: Node, k: Key, down := true, shift := false) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.shift_pressed = shift
	e.pressed = down
	tv._unhandled_input(e)


func _flight(id: int) -> void:
	var s := settings()
	load("res://flight/fly.gd").prepare(id)
	var tv: Node = await start_mission(id)
	s.mission_files_override = []
	tv.addon.out_dir = OS.get_temp_dir().path_join("modern-iaf-range-shot-%d" % OS.get_process_id())
	tv.addon.result = {"pass": true}
	await fly(tv, 3.0)
	var d1 = tv.ai.pilots.filter(func(p): return String(p.ent.name).begins_with("Drone 1"))[0]
	var st: Dictionary = d1.state()
	_put(tv, st.position - st.velocity.normalized() * 15000.0, st.velocity, float(st.heading))
	_key(tv, KEY_Q)
	_key(tv, KEY_Q, false)
	await fly(tv, 6.0)
	await _save("range_radar")
	_key(tv, KEY_ENTER)  # lock the nearest
	_key(tv, KEY_ENTER, false)
	await fly(tv, 2.0)
	await _save("range_radar_lock")
	st = d1.state()
	_put(tv, st.position - st.velocity.normalized() * 300.0 + Vector3(0, -15, 0), st.velocity, float(st.heading))
	await fly(tv, 1.5)
	await _save("range_drone")
	# The ground targets: 4 km short of Target 1 at 1,500 m, the nose a little down onto them.
	var t1: Dictionary = tv.runtime.entities.values().filter(func(e): return str(e.name) == "Target 1")[0]
	var tw: Vector3 = tv.world_to_scene(t1.world)
	var back := Vector3(0, 0, 4000.0)
	_put(tv, tw + back + Vector3(0, 1500, 0), Vector3(0, 0, -200.0), 0.0, -18.0)
	await fly(tv, 1.0)
	await _save("range_targets")
	# A gun kill on Drone 1, then the debrief.
	_key(tv, KEY_A, true, true)
	_key(tv, KEY_A, false, true)
	tv.weapons.safety_off = true
	for attempt in 3:
		st = d1.state()
		_put(tv, st.position - st.velocity.normalized() * 200.0, st.velocity, float(st.heading))
		await frames(1)
		var o: Dictionary = tv.weapons.own()
		var aim: Vector3 = tv.weapons.GunRounds.shot_dir(o.fwd, o.up)
		_put(tv, tv.world_to_scene(d1.ent.world - aim * 200.0), d1.state().velocity, float(st.heading))
		_key(tv, KEY_TAB)
		await fly(tv, 0.6)
		_key(tv, KEY_TAB, false)
		await fly(tv, 1.5)
		if int(d1.ent.state) >= 3:
			break
	await _save("range_kill")
	await fly(tv, 1.0)
	tv.addon._finish(tv.addon.score())
	var sortie: int = s.flown_sortie
	tv.queue_free()
	await frames(5)
	fe.visible = true
	for lang in ["en", "he"]:
		s.language = lang
		s.flown_sortie = sortie
		fe.show_page("hangar")
		fe._ready()
		await frames(30)
		await _save("range_debrief_" + lang)
