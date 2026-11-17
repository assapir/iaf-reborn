# Dev helper (not run by tools/test.sh): real-render pictures of the Sufa's (IAF_SIM_JET=f16d: the Barak's) real FCR on
# the weapons range (docs/radar.md §9, avionics-plan.md slice 2), the Graphics preset "Everything on", 1920 wide:
# - fcr_modes.png: the left MFD's FCR in each mode, 3 x 2 at 640 px: RWS (A6 B4) with the drones, RWS A3 with the
#   antenna down onto Drone 2, SAM with Drone 1 bugged, TWS with its files, VSR, ACM with the lock;
# - fcr_<mode>.png: each of those as the whole cockpit view;
# - hud_lock.png: the cockpit with Drone 1 locked (STT) 5 km ahead: the HUD's TD box and the FCR;
# - fcr_pages.png: the left MFD, 3 x 1 at 640 px: SAM with EXP, the CNTL page, NO RAD in OVRD (each also as the whole
#   view, fcr_exp / fcr_cntl / fcr_no_rad.png); hud_acm60.png / hud_slew.png: ACM's HUD cues, nothing in reach.
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=<dir> -- --log-file <temp> --resolution 1920x1080 \
#     --path modern-iaf -s ../modern-iaf/tests/_fcr_shot.gd
extends "res://../tests/godot/base.gd"

const CELL := 640

var dir := ""
var tv: Node
var w
var cells := []


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(dir.path_join(name + ".png"))
	# The left MFD's own picture (the 3D cockpit's SubViewport of the FCR).
	for sc in tv.cockpit_3d._screens:
		if sc[0].page == 2:
			var img: Image = (sc[1] as SubViewport).get_texture().get_image()
			img.convert(Image.FORMAT_RGB8)
			img.resize(CELL, CELL, Image.INTERPOLATE_LANCZOS)
			cells.append(img)
			break
	print("shot ", name)


func _put(pos: Vector3, vel: Vector3, hdg: float) -> void:
	tv.rig.position = pos
	tv.flight.start(settings().own_dir(), tv.player.fm_section, pos, Vector3(0, 0, hdg), vel, airborne_flags())
	tv.gear_down = false
	tv.throttle = 0.85


func _behind(d, dist: float, up := 0.0, side := 0.0) -> void:
	var st: Dictionary = d.state()
	var fw: Vector3 = st.velocity.normalized()
	var pos: Vector3 = st.position - fw * dist + Vector3(0, up, 0) + fw.cross(Vector3.UP).normalized() * side
	_put(pos, st.velocity, float(st.heading))


func _tap(k: Key, shift := false, alt := false, ctrl := false) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.shift_pressed = shift
		e.alt_pressed = alt
		e.ctrl_pressed = ctrl
		e.pressed = down
		tv._unhandled_input(e)


func _drone(name: String):
	return tv.ai.pilots.filter(func(p): return String(p.ent.name).begins_with(name))[0]


## The antenna elevation back to level (the thumbwheel held until it crosses 0).
func _level() -> void:
	var way := -signf(float(w.radar.real.elevation))
	w.radar_event(w.RADAR_ELEVATION, way)
	for i in 200:
		if float(w.radar.real.elevation) * way >= -0.5:
			break
		await fly(tv, 0.05)
	w.radar_event(w.RADAR_ELEVATION, 0.0)


## Bugs the drone once the search lists it (up to 15 s, put 15 km behind it every 5 s).
func _bug(d) -> void:
	for i in 30:
		for c in w.radar.contacts:
			if String(c.key) == String(d.ent.key):
				w.radar_event(w.RADAR_CURSOR, c.scope)
				_tap(KEY_SLASH)
				return
		if i % 10 == 9:
			_behind(d, 15000.0)  # the drones manoeuvre: straight behind it again
		await fly(tv, 0.5)
	print("not listed: ", d.ent.name)


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "needs a window")
		return
	await require_data()
	dir = OS.get_environment("SHOT_DIR")
	DirAccess.make_dir_recursive_absolute(dir)
	var s := settings()
	# The jet: the Sufa, or IAF_SIM_JET=f16d the Barak (base.gd sim_f16s).
	var base: String = sim_f16s().values()[0]
	var p: Dictionary = load("res://shared/util/pref_choices.gd").preset("everything")
	for k in p:
		s.set(k, p[k])
	s.show_info = false
	var id := sim_mission(base + "_range")
	load("res://flight/fly.gd").prepare(id)
	tv = await start_mission(id)
	s.mission_files_override = []
	tv.addon.out_dir = OS.get_temp_dir().path_join("modern-iaf-fcr-shot-%d" % OS.get_process_id())
	tv.addon.result = {"pass": true}
	w = tv.weapons
	tv._command([213, 0, 0])
	await fly(tv, 3.0)
	var d1 = _drone("Drone 1")
	var d2 = _drone("Drone 2")
	# RWS, A6 B4: Drone 1 ahead, Drone 3 / the pair wherever they are.
	_behind(d1, 25000.0, 0.0, 4000.0)
	await fly(tv, 9.0)
	await _save("fcr_rws")
	# A3 with the antenna 12° down: Drone 2 (low) 15 km ahead.
	_tap(KEY_APOSTROPHE, true)
	_behind(d2, 15000.0, 3700.0)
	for i in 12:
		w.radar_event(w.RADAR_ELEVATION, -1.0)
		await fly(tv, 0.1)
	w.radar_event(w.RADAR_ELEVATION, 0.0)
	_behind(d2, 15000.0, 3700.0)
	await fly(tv, 5.0)
	await _save("fcr_rws_look_down")
	_tap(KEY_APOSTROPHE, true)
	_tap(KEY_APOSTROPHE, true)
	await _level()
	# SAM: Drone 1 bugged, the search going on.
	_behind(d1, 20000.0, 0.0, 3000.0)
	await fly(tv, 9.0)
	await _bug(d1)
	await fly(tv, 2.0)
	await _save("fcr_sam")
	_tap(KEY_SEMICOLON, false, false, true)
	await fly(tv, 1.0)
	await _save("fcr_exp")
	_tap(KEY_SEMICOLON, false, false, true)
	var fmt = tv.cockpit.radar_mfd().real_fmt
	fmt._own("FCR", 5)
	await fly(tv, 0.5)
	await _save("fcr_cntl")
	fmt._own("FCR", 5)
	_tap(KEY_SLASH, false, false, true)
	await fly(tv, 0.5)
	await _save("fcr_no_rad")
	_tap(KEY_SLASH, false, false, true)
	await fly(tv, 1.0)
	# TWS.
	_tap(KEY_SLASH, true)
	_tap(KEY_SEMICOLON)
	_behind(d1, 20000.0, 0.0, 3000.0)
	await fly(tv, 6.0)
	await _save("fcr_tws")
	# VSR: Drone 1 ahead, the jet faster.
	_tap(KEY_APOSTROPHE)
	var st: Dictionary = d1.state()
	_put(st.position - st.velocity.normalized() * 20000.0, st.velocity * 1.6, float(st.heading))
	for i in 24:
		await fly(tv, 0.5)
		if w.radar.contacts.any(func(c): return String(c.key) == String(d1.ent.key)):
			break
	await _save("fcr_vsr")
	_tap(KEY_APOSTROPHE)
	# ACM: Q, Q from RWS, Drone 1 3 km ahead.
	_tap(KEY_Q)
	_tap(KEY_Q)
	_behind(d1, 3000.0)
	await fly(tv, 2.0)
	await _save("fcr_acm")
	# ACM's HUD cues with nothing in reach: the 10 x 60, then SLEW.
	_tap(KEY_SLASH, true)
	_behind(d1, 30000.0)
	_tap(KEY_SEMICOLON)
	await fly(tv, 1.0)
	await _save("hud_acm60")
	w.radar_event(w.RADAR_CURSOR, Vector2(0.53, 0.5))  # SLEW's patch 3.6° right of the nose
	_tap(KEY_SEMICOLON, true)
	await _level()  # SLEW's patch is about the antenna elevation
	await fly(tv, 0.5)
	await _save("hud_slew")
	# The HUD with a lock: RWS, Drone 1 5 km ahead, bugged then locked.
	_tap(KEY_SLASH, true)
	_tap(KEY_Q)
	_behind(d1, 5000.0, 150.0)
	await fly(tv, 9.0)
	await _bug(d1)
	await fly(tv, 0.3)
	_tap(KEY_SLASH)
	await fly(tv, 2.0)
	await _save("hud_lock")
	# The cells in shot order: rws, look_down, sam, exp, cntl, no_rad, tws, vsr, acm, (acm60, slew, hud_lock).
	var grid := func(name: String, picks: Array) -> void:
		var out := Image.create(3 * CELL, CELL * ceili(picks.size() / 3.0), false, Image.FORMAT_RGB8)
		out.fill(Color.BLACK)
		for i in picks.size():
			if picks[i] < cells.size():
				out.blit_rect(cells[picks[i]], Rect2i(0, 0, CELL, CELL), Vector2i((i % 3) * CELL, (i / 3) * CELL))
		out.save_png(dir.path_join(name + ".png"))
	grid.call("fcr_modes", [0, 1, 2, 6, 7, 8])
	grid.call("fcr_pages", [3, 4, 5])
	print("RESULT PASS")
	tv.queue_free()
	await frames(5)
