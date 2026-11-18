# Dev helper (not run by tools/test.sh): the F-16 manual's chapter 6 weapon pictures from the Sufa's HUD and helmet on
# the weapons range, the Graphics preset "Everything on", 1920 wide (modern-iaf/docs/manuals.md §4). Each picture is
# the HUD's part of the frame (or the helmet's, looking aside), scaled to 1600 px wide:
# - hud_ccip_delayed.png: a Mk 83 in CCIP, the impact point below the HUD's view, the release button held: the
#   steering line and the release cue;
# - hud_gps.png, hud_gps_inrng.png: a GBU-31 on a point designated 20 km out: the box, steering line, range scale and
#   caret with the time to release, then IN RNG.
# The gun's funnel with a lock and the helmet's symbols are owed (manuals.md §7): no radar lock and no padlock on a drone
# came out of a scripted run.
#   flock ~/.cache/iaf-gpu-bench.lock tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=<dir> -- \
#     --resolution 1920x1080 --path modern-iaf -s ../modern-iaf/tests/_f16_weapons_shot.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

var dir := ""
var tv: Node
var w


func _key(k: Key, mods := "", up := true) -> void:
	for d in [true, false]:
		if not d and not up:
			return
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.shift_pressed = "s" in mods
		e.alt_pressed = "a" in mods
		e.ctrl_pressed = "c" in mods
		e.pressed = d
		tv._unhandled_input(e)


func _put(x: float, y: float, hdg := 0.0, up := 3000.0, speed := 220.0, pitch := 0.0) -> void:
	var g = tv.mission_ground(Vector3(x, y, 0.0))
	var pos: Vector3 = tv.world_to_scene(Vector3(x, y, float(g if g != null else 0.0) + up))
	var v := Vector3(sin(deg_to_rad(hdg)), 0.0, -cos(deg_to_rad(hdg))) * speed
	tv.rig.position = pos
	tv.flight.start(settings().own_dir(), tv.player.fm_section, pos, Vector3(pitch, 0, hdg), v, airborne_flags())
	tv.gear_down = false
	tv.throttle = 0.85


func _target(name: String) -> Dictionary:
	for e in tv.runtime.entities.values():
		if String(e.get("name", "")) == name:
			return e
	return {}


## The weapon `part` (lower case) of the current station's name selected with `[` (A-G) or `]` (A-A).
func _select(part: String, ag: bool) -> void:
	for i in 12:
		if String(w.stores.current_name()).to_lower().contains(part):
			return
		_key(KEY_BRACKETLEFT if ag else KEY_BRACKETRIGHT)
		await frames(2)
	print("NOT SELECTED ", part, " now ", w.stores.current_name())


## `name`.png: the frame's `r` (in 1920 x 1080 units) scaled to 1600 wide.
func _crop(name: String, r: Rect2) -> void:
	await fly(tv, 0.4)
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	var s := img.get_width() / 1920.0
	var c := img.get_region(Rect2i(Vector2i(r.position * s), Vector2i(r.size * s)))
	c.resize(1600, int(1600.0 * r.size.y / r.size.x), Image.INTERPOLATE_LANCZOS)
	c.save_png(dir.path_join(name + ".png"))
	print("shot ", name, " hud: ", w.hud_mode, " ", w.stores.current_name())


const HUD := Rect2(760, 210, 400, 280)


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "needs a window")
		return
	await require_data()
	dir = OS.get_environment("SHOT_DIR")
	DirAccess.make_dir_recursive_absolute(dir)
	var s := settings()
	var unit: String = sim_f16s().keys()[0]
	var base: String = sim_f16s()[unit]
	var p: Dictionary = load("res://shared/util/pref_choices.gd").preset("everything")
	for k in p:
		s.set(k, p[k])
	s.show_info = false
	var db: String = s.records_db()
	var rec := ProjectSettings.globalize_path("res://data/db/units/%s.json" % unit)
	var lo: String = IafBriefing.put(rec, "", 3, "gbu-31", true)
	lo = IafBriefing.put(rec, lo, 4, "mk-83", true)
	lo = IafBriefing.put(rec, lo, 1, "python-5", true)
	IafPilotLog.set_loadout(db, s.pilot(), unit, lo)
	var id := sim_mission(base + "_range")
	load("res://flight/fly.gd").prepare(id)
	tv = await start_mission(id)
	s.mission_files_override = []
	IafPilotLog.set_loadout(db, s.pilot(), unit, "")
	tv.addon.out_dir = OS.get_temp_dir().path_join("f16-weapons-shot-%d" % OS.get_process_id())
	tv.addon.result = {"pass": true}
	w = tv.weapons
	var t1 := _target("Target 1")
	_put(t1.world.x, t1.world.y - 30000.0, 0.0, 4500.0)
	await fly(tv, 3.0)
	tv.views.set_cockpit(tv.views.COCKPIT)
	tv.in_cockpit = true
	tv._apply_view()
	tv.views.snap = Vector2.ZERO
	await fly(tv, 2.0)
	# 1. Delayed CCIP: the Mk 83, level, the impact point well below the view; the button held.
	w.select_ag()
	await _select("83", true)
	_key(KEY_A, "s")  # master arm
	await fly(tv, 1.0)
	# The impact point under the HUD; the button held until the time to go is 2.5 s (the release cue just above the marker).
	_put(t1.world.x, t1.world.y - 30000.0, 0.0, 900.0, 220.0)
	tv.throttle = 0.6
	await fly(tv, 1.5)
	_key(KEY_SPACE, "", false)
	for i in 600:
		if float(w.ag.ttg) <= 2.5 and float(w.ag.ttg) > 0.0:
			break
		await fly(tv, 0.1)
	print("ag off=", w.ag.off, " frozen=", w.ag.frozen, " ttg=", w.ag.ttg)
	await _crop("hud_ccip_delayed", HUD)
	_key(KEY_SPACE)
	# 2. The GPS bomb.
	_put(t1.world.x, t1.world.y - 20000.0, 0.0, 1200.0)
	await _select("gbu", true)
	await fly(tv, 3.0)
	w.radar_event(w.RADAR_GROUND, t1.world + Vector3(-4000.0, 0.0, 0.0))
	await fly(tv, 0.1)
	_key(KEY_SLASH)
	await fly(tv, 1.0)
	await _crop("hud_gps", HUD)
	for i in 900:
		if w.ag.gps.get("in_range", false):
			break
		await fly(tv, 0.1)
	print("gps in_range=", w.ag.gps.get("in_range"))
	await _crop("hud_gps_inrng", HUD)
	print("RESULT PASS")
	tv.queue_free()
	await frames(5)

