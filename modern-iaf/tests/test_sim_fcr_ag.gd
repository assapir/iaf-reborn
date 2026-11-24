# The F-16s' real fire-control radar air to ground (the Sufa's, then the Barak's: base.gd sim_f16s) on the weapons range
# (avionics-plan.md §6 slice 3, G9-G12; docs/radar.md §9.7), headless, on each jet's range mission with a SPICE 1000 and
# an Mk 83 loaded:
# - GM (R): the range's hulks drawn where they are on the PPI fan, the radar picture over the terrain;
# - the field of view (Ctrl + ;): EXP, DBS1, DBS2 draw the ground 4, 8 and 64 times larger about the cursor; DBS2 on
#   the home base's runway shows it dark;
# - FZ (Alt + ;) holds the picture while the jet flies on; GMT (Q) lists only the towed hulk; SEA (Q) only the barge;
# - TMS up (/) off the returns designates the cursor's point, on a hulk tracks it (FTT): the HUD's TD box, and the
#   SPICE 1000 in VIS aims at either; TMS down (Shift + /) drops it;
# - AGR: the Mk 83's CCIP ranges along its aim line; the HUD's slant range reads it.
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_sim_fcr_ag.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

## mfd.gd, loaded at run time (a preload would compile it before the Settings autoload exists).
var mfd_gd: GDScript

var tv: Node
var w


func _press(k: Key, shift := false, alt := false, ctrl := false, down := true) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.shift_pressed = shift
	e.alt_pressed = alt
	e.ctrl_pressed = ctrl
	e.pressed = down
	tv._unhandled_input(e)


func _tap(k: Key, shift := false, alt := false, ctrl := false) -> void:
	_press(k, shift, alt, ctrl)
	_press(k, shift, alt, ctrl, false)


## The jet airborne 3000 m above the ground at world (x, y), flying north at 220 m/s.
func _put(x: float, y: float) -> void:
	var g = tv.mission_ground(Vector3(x, y, 0.0))
	var pos: Vector3 = tv.world_to_scene(Vector3(x, y, float(g if g != null else 0.0) + 3000.0))
	tv.rig.position = pos
	tv.flight.start(
		settings().own_dir(), tv.player.fm_section, pos, Vector3.ZERO, Vector3(0, 0, -220), airborne_flags()
	)
	tv.gear_down = false
	tv.throttle = 0.85


func _ag() -> Dictionary:
	return w.radar.real.get("ag", {})


func _keys() -> Array:
	return w.radar.contacts.map(func(c): return String(c.key))


func _target(name: String) -> Dictionary:
	for e in tv.runtime.entities.values():
		if String(e.get("name", "")) == name:
			return e
	return {}


## The picture's luminance and alpha at a world point (radar.rs PIC_WINDOW over the picture's own frame).
func _pic_at(p: Vector3) -> Vector2i:
	var pic: Dictionary = _ag().pic
	var q: Vector2 = mfd_gd.ag_px(pic.frame, p) - Rect2(pic.window).position
	var wd := int(Rect2(pic.window).size.x)
	var i := 2 * (int(q.y) * wd + int(q.x))
	var b: PackedByteArray = w.radar.pic
	return Vector2i(b[i], b[i + 1]) if i >= 0 and i + 1 < b.size() else Vector2i(-1, -1)


## Presses '[' until the selected store's name holds `part` (at most 8).
func _select(part: String) -> bool:
	for i in 16:
		if String(w.stores.current_name()).to_lower().contains(part):
			return true
		_tap(KEY_BRACKETLEFT)
		await frames(2)
	return String(w.stores.current_name()).to_lower().contains(part)


func run() -> void:
	await require_data()
	for unit in sim_f16s():
		print("-- %s" % unit)
		await _jet(unit, sim_f16s()[unit])


func _jet(unit: String, base: String) -> void:
	mfd_gd = load("res://shared/cockpit/mfd.gd")
	var s := settings()
	var db: String = s.records_db()
	var rec := ProjectSettings.globalize_path("res://data/db/units/%s.json" % unit)
	var load_out: String = IafBriefing.put(rec, IafBriefing.put(rec, "", 3, "spice-1000", true), 4, "mk-83", true)
	IafPilotLog.set_loadout(db, s.pilot(), unit, load_out)
	var id := sim_mission(base + "_range")
	load("res://flight/fly.gd").prepare(id)
	tv = await start_mission(id)
	s.mission_files_override = []
	IafPilotLog.set_loadout(db, s.pilot(), unit, "")
	tv.addon.out_dir = DirAccess.create_temp("modern-iaf-fcr-ag", false).get_current_dir()
	tv.addon.result = {"pass": true}
	w = tv.weapons
	var home := {}
	for b in load("res://shared/terrain/airbases.gd").bases():
		if String(b.name).contains(base.capitalize().get_slice(" ", base.count("_"))):  # airbases.json: "Ramon", "David"
			home = b
	check(not home.is_empty(), "%s's runways known" % base.capitalize())
	if home.is_empty():
		return
	var rw: Array = home.runways[0].ends
	var mid := Vector3((rw[0][0] + rw[1][0]) / 2.0, (rw[0][1] + rw[1][1]) / 2.0, 0.0)
	var hulks := []
	for n in ["Target 1", "Target 2", "Target 3", "Target 4", "Target 5"]:
		hulks.append(_target(n))
	check(hulks.all(func(e): return not e.is_empty()), "five ground targets on the range")
	if not hulks.all(func(e): return not e.is_empty()):
		return
	# 22 km east and 35.7 km south of Target 1: the range's hulks about 30° left, 42 km out (each range's targets lie
	# alike about their Target 1).
	var at := Vector2(hulks[0].world.x + 22000.0, hulks[0].world.y - 35700.0)
	_put(at.x, at.y)
	tv._command([213, 0, 0])  # the avionics: the FCR up in STBY, CRM by itself in the air
	await fly(tv, 3.0)
	_tap(KEY_R)
	await fly(tv, 2.5)
	check(_ag().get("name") == "GM", "R: GM (%s)" % _ag().get("name"))
	# GM: every hulk where it is on the PPI fan (94 px = the 40 NM scale from the apex, heading-up).
	var fr: Dictionary = _ag().frame
	var o: Dictionary = w.own()
	var placed := 0
	for e in hulks:
		var rel: Vector3 = e.world - o.pos
		var b: float = atan2(rel.x, rel.y) - float(o.yaw)
		var want := Vector2(66, 109) + Vector2(sin(b), -cos(b)) * Vector2(rel.x, rel.y).length() / float(fr.k)
		if _keys().has(String(e.key)) and mfd_gd.ag_px(fr, e.world).distance_to(want) < 0.5:
			placed += 1
	check(placed == 5, "GM: the five hulks listed and drawn where they are (%d)" % placed)
	var lit := 0
	for k in range(0, w.radar.pic.size(), 2):
		if w.radar.pic[k + 1] == 255 and w.radar.pic[k] > 0:
			lit += 1
	check(lit > 1000, "GM: the radar picture shows the ground (%d px lit)" % lit)
	check(_pic_at(hulks[0].world).x == 255, "GM: Target 1 a bright return in the picture")
	# The frame's cost: one radar frame (a scan; its picture paints on its own thread) in ms, on this machine. Painted in
	# the frame it took 11-23 ms on the Linux laptop (docs/radar.md §9.7).
	var t0 := Time.get_ticks_usec()
	w.radar.scan(w.now)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("GM radar frame: %.1f ms" % ms)
	check(ms < 5.0, "GM: a radar frame under 5 ms, its picture painted off the frame (%.1f ms)" % ms)
	# EXP / DBS1 / DBS2 about the cursor on Target 1: Target 1 to Target 2 drawn 4, 8, 64 times farther apart.
	w.radar_event(w.RADAR_GROUND, hulks[0].world)
	await fly(tv, 0.1)
	var gap := func() -> float:
		var f: Dictionary = _ag().frame
		return mfd_gd.ag_px(f, hulks[0].world).distance_to(mfd_gd.ag_px(f, hulks[1].world))
	var norm: float = gap.call()
	var steps := []
	for want in [["EXP", 4.0], ["DBS1", 8.0], ["DBS2", 64.0], ["NORM", 1.0]]:
		_tap(KEY_SEMICOLON, false, false, true)
		await fly(tv, 0.1)
		var k: float = gap.call() / norm
		steps.append("%s %.1f" % [_ag().fov, k])
		check(
			_ag().fov == want[0] and absf(k - want[1]) < want[1] * 0.02,
			"Ctrl + ;: %s × %s (%s)" % [want[0], want[1], steps]
		)
	# DBS2 on the home base's runway (12 m a px), from 12.7 km east and 8.6 km south of it (the base 56° left): the
	# runway dark, the ground beside it lit.
	_put(mid.x + 12700.0, mid.y - 8600.0)
	await fly(tv, 2.5)
	w.radar_event(w.RADAR_GROUND, mid)
	for i in 3:
		_tap(KEY_SEMICOLON, false, false, true)
	await fly(tv, 2.5)
	var dir := Vector2(rw[1][0] - rw[0][0], rw[1][1] - rw[0][1]).normalized()
	var beside := mid + Vector3(-dir.y, dir.x, 0.0) * (float(home.runways[0].width) / 2.0 + 120.0)
	var on := _pic_at(mid)
	var off := _pic_at(beside)
	check(
		_ag().fov == "DBS2" and on == Vector2i(0, 255) and off.x > 10,
		"DBS2: the runway dark %s, beside it %s" % [on, off]
	)
	_tap(KEY_SEMICOLON, false, false, true)
	await fly(tv, 2.5)
	# FZ: the picture and its frame held while the jet flies on; the jet moves over it.
	_tap(KEY_SEMICOLON, false, true)
	await fly(tv, 0.1)
	var serial := int(_ag().pic.serial)
	var frozen: Dictionary = _ag().frame
	var own0: Vector2 = mfd_gd.ag_px(frozen, w.own().pos)
	await fly(tv, 4.0)
	check(_ag().frozen and int(_ag().pic.serial) == serial, "Alt + ;: FZ holds the picture")
	check(
		w.radar.pic.size() == 108 * 106 * 2 and not _ag().pic.frame.is_empty(),
		"FZ: the held picture still drawn (%d bytes, frame %s)" % [w.radar.pic.size(), _ag().pic.frame]
	)
	var own1: Vector2 = mfd_gd.ag_px(_ag().frame, w.own().pos)
	check(own1.distance_to(own0) > 880.0 / float(frozen.k) * 0.8, "FZ: the jet moves over the frozen map")
	_tap(KEY_SEMICOLON, false, true)
	await fly(tv, 2.5)
	check(not _ag().frozen and int(_ag().pic.serial) > serial, "Alt + ; again: a new picture")
	# GMT: only the towed hulk; SEA: only the barge.
	_put(at.x, at.y)
	await fly(tv, 2.5)
	_tap(KEY_Q)
	await fly(tv, 2.5)
	check(_ag().name == "GMT" and _keys() == [String(hulks[4].key)], "Q: GMT lists Target 5 only (%s)" % [_keys()])
	_tap(KEY_Q)
	var barge := _target("Target 6")
	check(not barge.is_empty() and int(barge.klass) == 15, "the range's barge, a ship (class 15)")
	_put(barge.world.x, barge.world.y - 30000.0)
	await fly(tv, 2.5)
	check(_ag().name == "SEA" and _keys() == [String(barge.key)], "Q: SEA lists the barge only (%s)" % [_keys()])
	_tap(KEY_Q)
	_put(at.x, at.y)
	await fly(tv, 2.5)
	check(_ag().name == "GM", "Q: GM again")
	# TMS up off the returns: the cursor's point designated; the HUD's TD box; the SPICE 1000 in VIS aims there.
	var spot: Vector3 = hulks[0].world + Vector3(-6000.0, 0.0, 0.0)  # 8 px aside at 40 NM: off the returns
	w.radar_event(w.RADAR_GROUND, spot)
	await fly(tv, 0.1)
	_tap(KEY_SLASH)
	await fly(tv, 0.2)
	var spi = w.radar.spi
	check(
		spi != null and Vector2(spi.x, spi.y).distance_to(Vector2(spot.x, spot.y)) < 1.0 and _ag().tgt,
		"/ off the returns: the point designated, TGT (%s)" % [spi]
	)
	check(not tv.cockpit.hud.target_box(1.0).is_empty(), "the HUD's TD box on the designation")
	tv.cockpit.hud.real_hud()
	check(not tv.cockpit.hud._real_in.get("target", {}).is_empty(), "the Real HUD's target: the designated point")
	check(await _select("spice"), "[: the SPICE 1000 (%s)" % w.stores.current_name())
	w.gps_mode_key()  # K: VIS
	var a: Array = w.gps_aim(Vector3.ZERO)
	check(
		a[1] and Vector2(a[0].x, a[0].y).distance_to(Vector2(spot.x, spot.y)) < 1.0,
		"VIS: the SPICE aims there (%s)" % [a]
	)
	# TMS up on Target 1: FTT; the SPICE aims at the hulk.
	w.radar_event(w.RADAR_GROUND, hulks[0].world)
	await fly(tv, 0.1)
	_tap(KEY_SLASH)
	await fly(tv, 0.2)
	spi = w.radar.spi
	check(
		(
			w.radar.has_lock()
			and spi != null
			and Vector2(spi.x, spi.y).distance_to(Vector2(hulks[0].world.x, hulks[0].world.y)) < 1.0
		),
		(
			"/ on Target 1: FTT, the weapons' point on the hulk (%s, lock %s, hulk %s, mode %d)"
			% [spi, w.radar.has_lock(), hulks[0].world, w.radar.mode]
		)
	)
	a = w.gps_aim(Vector3.ZERO)
	check(
		Vector2(a[0].x, a[0].y).distance_to(Vector2(hulks[0].world.x, hulks[0].world.y)) < 1.0,
		"VIS: the SPICE on the hulk"
	)
	_tap(KEY_SLASH, true)
	await fly(tv, 0.2)
	check(w.radar.spi == null and not w.radar.has_lock(), "Shift + /: the track dropped")
	# AGR: the Mk 83's CCIP ranges along its aim line; the HUD's slant range reads it.
	check(await _select("83"), "[: the Mk 83 (%s)" % w.stores.current_name())
	await fly(tv, 0.5)
	var agr := float(_ag().get("agr", -1.0))
	var aim: Vector3 = w.ag.target if w.ag.off else w.ag.impact
	var want_m: float = aim.distance_to(w.own().pos)
	check(
		_ag().name == "AGR" and absf(agr - want_m) < want_m * 0.05,
		"AGR: the slant range %.0f m to the pipper's point (%.0f m)" % [agr, want_m]
	)
	tv.cockpit.hud.real_hud()
	check(tv.cockpit.hud._real_in.get("agr_m") != null, "the Real HUD's slant range reads AGR")
	tv.queue_free()
	await frames(5)
