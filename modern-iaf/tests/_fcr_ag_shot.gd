# Dev helper (not run by tools/test.sh): real-render pictures of the Sufa's (IAF_SIM_JET=f16d: the Barak's) real FCR air
# to ground on the weapons range (docs/radar.md §9.7, avionics-plan.md slice 3), the Graphics preset "Everything on",
# 1920 wide:
# - ag_modes.png: the left MFD, 3 x 3 at 640 px: GM NORM (the hulks 30° left, Ramon), EXP, DBS1 and DBS2 on the hulks,
#   DBS2 on Ramon's runway, FZ, GMT (the towed hulk), SEA (the barge), AGR with the Mk 83; each also as the whole
#   cockpit view (ag_<name>.png);
# - ag_hud_desig.png / ag_hud_ftt.png: the cockpit with a designated point and with Target 1 tracked: the HUD's TD box;
# - fcr_exp_aa.png: the A-A EXP retaken (slice 2's picture): the left MFD, NORM and EXP side by side with the pair of
#   drones (Drones 4) bugged.
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=<dir> -- --log-file <temp> --resolution 1920x1080 \
#     --path modern-iaf -s ../modern-iaf/tests/_fcr_ag_shot.gd
extends "res://../tests/godot/base.gd"

const CELL := 640

var dir := ""
var tv: Node
var w
var cells := []


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(dir.path_join(name + ".png"))
	for sc in tv.cockpit_3d._screens:
		if sc[0].page == 2:
			var img: Image = (sc[1] as SubViewport).get_texture().get_image()
			img.convert(Image.FORMAT_RGB8)
			img.resize(CELL, CELL, Image.INTERPOLATE_LANCZOS)
			cells.append(img)
			break
	print("shot ", name)


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


## The jet `up` m above the ground at world (x, y), heading `hdg` (deg) at 220 m/s.
func _put(x: float, y: float, hdg := 0.0, up := 3000.0) -> void:
	var g = tv.mission_ground(Vector3(x, y, 0.0))
	var pos: Vector3 = tv.world_to_scene(Vector3(x, y, float(g if g != null else 0.0) + up))
	var v := Vector3(sin(deg_to_rad(hdg)), 0.0, -cos(deg_to_rad(hdg))) * 220.0
	tv.rig.position = pos
	tv.flight.start(settings().own_dir(), tv.player.fm_section, pos, Vector3(0, 0, hdg), v, airborne_flags())
	tv.gear_down = false
	tv.throttle = 0.85


func _target(name: String) -> Dictionary:
	for e in tv.runtime.entities.values():
		if String(e.get("name", "")) == name:
			return e
	return {}


func _fov(want: String) -> void:
	for i in 4:
		if String(w.radar.real.get("ag", {}).get("fov", "")) == want:
			break
		_tap(KEY_SEMICOLON, false, false, true)
	await fly(tv, 2.2)


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "needs a window")
		return
	await require_data()
	dir = OS.get_environment("SHOT_DIR")
	DirAccess.make_dir_recursive_absolute(dir)
	var s := settings()
	# The jet: the Sufa, or IAF_SIM_JET=f16d the Barak (base.gd sim_f16s).
	var unit: String = sim_f16s().keys()[0]
	var base: String = sim_f16s()[unit]
	var p: Dictionary = load("res://shared/util/pref_choices.gd").preset("everything")
	for k in p:
		s.set(k, p[k])
	s.show_info = false
	var db: String = s.records_db()
	var rec := ProjectSettings.globalize_path("res://data/db/units/%s.json" % unit)
	var load_out: String = IafBriefing.put(rec, IafBriefing.put(rec, "", 3, "spice-1000", true), 4, "mk-83", true)
	IafPilotLog.set_loadout(db, s.pilot(), unit, load_out)
	var id := sim_mission(base + "_range")
	load("res://flight/fly.gd").prepare(id)
	tv = await start_mission(id)
	s.mission_files_override = []
	IafPilotLog.set_loadout(db, s.pilot(), unit, "")
	tv.addon.out_dir = OS.get_temp_dir().path_join("modern-iaf-fcr-ag-shot-%d" % OS.get_process_id())
	tv.addon.result = {"pass": true}
	w = tv.weapons
	var home := {}
	for b in load("res://shared/terrain/airbases.gd").bases():
		if String(b.name).contains(base.capitalize().get_slice(" ", base.count("_"))):  # airbases.json: "Ramon", "David"
			home = b
	var rw: Array = home.runways[0].ends
	var mid := Vector3((rw[0][0] + rw[1][0]) / 2.0, (rw[0][1] + rw[1][1]) / 2.0, 0.0)
	var t1 := _target("Target 1")
	var at := Vector2(t1.world.x + 22000.0, t1.world.y - 35700.0)  # the hulks 30° left, 42 km out (test_sim_fcr_ag)
	_put(at.x, at.y)
	tv._command([213, 0, 0])
	await fly(tv, 3.0)
	_tap(KEY_R)
	await fly(tv, 6.0)
	await _save("ag_gm")
	w.radar_event(w.RADAR_GROUND, t1.world)
	for f in ["EXP", "DBS1", "DBS2"]:
		await _fov(f)
		await _save("ag_" + f.to_lower())
	_put(mid.x + 12700.0, mid.y - 8600.0)  # the home base 56° left
	await fly(tv, 2.5)
	w.radar_event(w.RADAR_GROUND, mid)
	await fly(tv, 2.2)
	await _save("ag_dbs2_runway")
	await _fov("NORM")
	_put(at.x, at.y)
	await fly(tv, 2.5)
	_tap(KEY_SEMICOLON, false, true)  # FZ
	await fly(tv, 8.0)
	await _save("ag_fz")
	_tap(KEY_SEMICOLON, false, true)
	_tap(KEY_Q)
	await fly(tv, 4.0)
	await _save("ag_gmt")
	_tap(KEY_Q)
	var barge := _target("Target 6")
	_put(barge.world.x, barge.world.y - 25000.0)
	await fly(tv, 5.0)
	await _save("ag_sea")
	_tap(KEY_Q)
	_put(at.x, at.y)
	for i in 8:
		if String(w.stores.current_name()).to_lower().contains("83"):
			break
		_tap(KEY_BRACKETLEFT)
		await frames(2)
	await fly(tv, 1.0)
	await _save("ag_agr")
	# The HUD: 20 km south of Target 1, heading at it, 1200 m up; a point 4 km left of it designated (5 px aside at
	# 40 NM), then FTT on it.
	_put(t1.world.x, t1.world.y - 20000.0, 0.0, 1200.0)
	for i in 16:
		if String(w.stores.current_name()).to_lower().contains("spice"):
			break
		_tap(KEY_BRACKETLEFT)
		await frames(2)
	await fly(tv, 3.0)
	w.radar_event(w.RADAR_GROUND, t1.world + Vector3(-4000.0, 0.0, 0.0))
	await fly(tv, 0.1)
	_tap(KEY_SLASH)
	await fly(tv, 1.0)
	await _save("ag_hud_desig")
	w.radar_event(w.RADAR_GROUND, t1.world)
	await fly(tv, 0.1)
	_tap(KEY_SLASH)
	await fly(tv, 1.0)
	await _save("ag_hud_ftt")
	# The A-A EXP retaken: the pair of drones (Drones 4) 15 km ahead, the leader bugged, NORM then EXP.
	_tap(KEY_SLASH, true)
	_tap(KEY_R)
	var pair: Array = tv.ai.pilots.filter(func(q): return String(q.ent.name).begins_with("Drones 4"))
	var st: Dictionary = pair[0].state()
	tv.rig.position = st.position - st.velocity.normalized() * 15000.0
	tv.flight.start(
		s.own_dir(), tv.player.fm_section, tv.rig.position, Vector3(0, 0, st.heading), st.velocity, airborne_flags()
	)
	await fly(tv, 9.0)
	for c in w.radar.contacts:
		if String(c.key) == String(pair[0].ent.key):
			w.radar_event(w.RADAR_CURSOR, c.scope)
			_tap(KEY_SLASH)
	await fly(tv, 1.0)
	await _save("fcr_norm_aa")
	_tap(KEY_SEMICOLON, false, false, true)
	await fly(tv, 1.0)
	await _save("fcr_exp_aa")
	var grid := func(name: String, picks: Array) -> void:
		var out := Image.create(3 * CELL, CELL * ceili(picks.size() / 3.0), false, Image.FORMAT_RGB8)
		out.fill(Color.BLACK)
		for i in picks.size():
			if picks[i] < cells.size():
				out.blit_rect(cells[picks[i]], Rect2i(0, 0, CELL, CELL), Vector2i((i % 3) * CELL, (i / 3) * CELL))
		out.save_png(dir.path_join(name + ".png"))
	# Shot order: gm, exp, dbs1, dbs2, dbs2_runway, fz, gmt, sea, agr, hud_desig, hud_ftt, norm_aa, exp_aa.
	grid.call("ag_modes", [0, 1, 2, 3, 4, 5, 6, 7, 8])
	grid.call("fcr_exp_aa_pair", [11, 12])
	print("RESULT PASS")
	tv.queue_free()
	await frames(5)
