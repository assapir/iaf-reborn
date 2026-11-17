# The F-35I Adir's radar, sensors and helmet pictures (avionics-plan.md slice 7 part B): SRCH searching and locked,
# the TSD with the data link's tracks, the TWD with the range's radar drones and a MAW warning, ASR's GM and DBS1 SAR
# picture, the helmet with a lock, with the MAW and with the break X in a dive, the whole display from the pilot's
# eye. Each portal picture is the PCD's glass cropped to portal 0, 1920 wide. A real render: run it hidden, one at a
# time,
#   flock ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=<dir> -- \
#     --resolution 1920x1080 --path modern-iaf -s ../modern-iaf/tests/_adir_s7b_shot.gd --log-file <temp>
extends "res://../tests/godot/base.gd"


class FakeMissile:
	extends RefCounted
	var p0: Vector3
	var v: Vector3
	var t0: float

	func position(now: float) -> Vector3:
		return p0 + v * (now - t0)

	func velocity(_now: float) -> Vector3:
		return v


var dir := ""
var tv: Node
var w
var c
var pcd


func _tap(k: Key, shift := false, ctrl := false) -> void:
	for d in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.shift_pressed = shift
		e.ctrl_pressed = ctrl
		e.pressed = d
		tv._unhandled_input(e)


func _put(pos: Vector3, vel: Vector3, hdg: float) -> void:
	tv.rig.position = pos
	tv.flight.start(settings().own_dir(), tv.player.fm_section, pos, Vector3(0, 0, hdg), vel, airborne_flags())
	tv.gear_down = false
	tv.throttle = 0.85


func _behind(d, dist: float, up := 0.0) -> void:
	var st: Dictionary = d.state()
	_put(st.position - st.velocity.normalized() * dist + Vector3(0, up, 0), st.velocity, float(st.heading))


func _drone(name: String):
	return tv.ai.pilots.filter(func(p): return String(p.ent.name).begins_with(name))[0]


func _contact(d) -> Dictionary:
	for ct in w.radar.contacts:
		if String(ct.key) == String(d.ent.key):
			return ct
	return {}


## The view straight ahead (the helmet's forward set) or down onto the PCD.
func _look(down: bool) -> void:
	tv.views.snap = Vector2(0.0, deg_to_rad(-30.0) if down else 0.0)
	await fly(tv, 0.5)


func cockpit_shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(dir.path_join(name + ".png"))
	print("shot ", name)


## Portal 0 showing `f`, cropped from the PCD's glass, 1920 wide.
func portal_shot(name: String, f: String) -> void:
	pcd._show(0, f)
	await fly(tv, 0.5)
	# The flashing symbols (a launch, the MAW's M) in their lit half (pcd_formats.gd: 300 ms phases).
	while int(Time.get_ticks_msec() / 300) % 2 != 0 or Time.get_ticks_msec() % 300 > 150:
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = (pcd.get_parent() as SubViewport).get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	var r: Rect2 = pcd.portals()[0]
	var crop := img.get_region(Rect2i(r.position.floor(), r.size.ceil()))
	crop.resize(1920, int(1920.0 * crop.get_height() / crop.get_width()), Image.INTERPOLATE_LANCZOS)
	crop.save_png(dir.path_join(name + ".png"))
	print("shot ", name)


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "needs a window")
		return
	await require_data()
	dir = OS.get_environment("SHOT_DIR")
	DirAccess.make_dir_recursive_absolute(dir)
	var s := settings()
	var p: Dictionary = load("res://shared/util/pref_choices.gd").preset("everything")
	for k in p:
		s.set(k, p[k])
	s.show_info = false
	var id := sim_mission("nevatim_range")
	load("res://flight/fly.gd").prepare(id)
	tv = await start_mission(id)
	s.mission_files_override = []
	tv.addon.out_dir = OS.get_temp_dir().path_join("s7b-shot-%d" % OS.get_process_id())
	tv.addon.result = {"pass": true}
	w = tv.weapons
	c = tv.cockpit
	pcd = c.pcd
	tv.views.set_cockpit(tv.views.COCKPIT)
	tv.in_cockpit = true
	tv._apply_view()
	# SRCH: CRM behind Drone 1.
	var d1 = _drone("Drone 1")
	for i in 5:
		_behind(d1, 12000.0)
		await fly(tv, 3.0)
		if int(w.radar.mode) < 2:
			_tap(KEY_Q)
		if not _contact(d1).is_empty():
			break
	await portal_shot("srch_crm", "SRCH")
	await _look(true)
	await cockpit_shot("pcd_pilot_eye")
	# The lock: the cursor on it, TMS up twice.
	_behind(d1, 9000.0)
	await fly(tv, 3.0)
	var ct := _contact(d1)
	if not ct.is_empty():
		w.radar_event(w.RADAR_CURSOR, ct.scope)
		_tap(KEY_SLASH)
		await fly(tv, 0.4)
		w.radar_event(w.RADAR_CURSOR, Vector2(_contact(d1).scope))
		_tap(KEY_SLASH)
		await fly(tv, 0.6)
	await portal_shot("srch_stt", "SRCH")
	await _look(false)
	await cockpit_shot("helmet_lock")
	_tap(KEY_SLASH, true)
	# The TSD with the data link (on from the start) and the radar's tracks.
	await fly(tv, 4.5)
	await portal_shot("tsd_link", "TSD-1")
	# The TWD: ahead of Drones 4, their radars on; a missile from ahead for the MAW.
	var dr = _drone("Drones 4")
	var st: Dictionary = dr.state()
	_put(st.position + st.velocity.normalized() * 15000.0, -st.velocity, float(st.heading) + 180.0)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 60000 and not c.ews.get("symbols", []).any(func(x): return x.label == "35"):
		await fly(tv, 0.5)
	st = dr.state()
	_put(st.position + st.velocity.normalized() * 15000.0, -st.velocity, float(st.heading) + 180.0)
	await fly(tv, 0.5)
	var o: Dictionary = w.own()
	var m := FakeMissile.new()
	m.p0 = o.pos + o.fwd.rotated(Vector3(0, 0, 1), -0.6) * 9000.0
	m.v = -o.fwd.rotated(Vector3(0, 0, 1), -0.6) * 600.0
	m.t0 = w.now
	w.rwr.launch(String(dr.ent.key), {"id": 9201, "pos": m.p0, "decoy": false, "m": m})
	await fly(tv, 0.3)
	await portal_shot("twd_maw", "TWD")
	await cockpit_shot("helmet_maw")
	w.rwr.missile_end(String(dr.ent.key), {"id": 9201, "m": m})
	# ASR: the range's hulks 30° left, 42 km out; GM, then DBS1 about Target 1.
	var t1: Dictionary = {}
	for e in tv.runtime.entities.values():
		if String(e.get("name", "")) == "Target 1":
			t1 = e
	var at := Vector2(t1.world.x + 22000.0, t1.world.y - 35700.0)
	var g = tv.mission_ground(Vector3(at.x, at.y, 0.0))
	_put(tv.world_to_scene(Vector3(at.x, at.y, float(g if g != null else 0.0) + 3000.0)), Vector3(0, 0, -220), 0.0)
	await fly(tv, 1.0)
	_tap(KEY_R)
	await fly(tv, 4.0)
	await portal_shot("asr_gm", "SRCH")
	w.radar_event(w.RADAR_GROUND, t1.world)
	_tap(KEY_SEMICOLON, false, true)
	_tap(KEY_SEMICOLON, false, true)
	await fly(tv, 3.0)
	await portal_shot("asr_dbs1", "SRCH")
	await _look(true)
	await cockpit_shot("pcd_pilot_eye_asr")
	# The break X: a 45° dive from 6,000 ft; saved on the first frame that shows it.
	await _look(false)
	o = w.own()
	g = tv.mission_ground(o.pos)
	_put(
		tv.world_to_scene(Vector3(o.pos.x, o.pos.y, float(g if g != null else 0.0) + 1830.0)), Vector3(0, 0, -215), 0.0
	)
	tv.throttle = 0.6
	var start: float = tv._sim_time
	while tv._sim_time - start < 40.0:
		var fs: Dictionary = tv.flight.state()
		tv.scripted_stick = Vector2(0.0, clampf((-45.0 - float(fs.pitch)) * 0.05, -0.4, 0.5))
		await process_frame
		var fr: Dictionary = c.hud.real_hud()
		var x := 0
		for q in fr.get("outer", []):
			if q.get("k", "") == "line" and absf(q.a.x - q.b.x) > 40.0 and absf(q.a.y - q.b.y) > 40.0:
				x += 1
		if x >= 2:
			await cockpit_shot("helmet_break_x")
			break
	tv.scripted_stick = null
	tv.queue_free()
	await frames(5)
