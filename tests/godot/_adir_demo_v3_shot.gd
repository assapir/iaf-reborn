# Dev helper (not run by tools/test.sh): the F-35I Adir demo clip v3. Each part flies one mission as the game plays it:
# no moved units, no shields, no forced results; the missions' own AI, scripts, radio voices and subtitles. The player's
# jet is flown through its stick, throttle, levers, autopilot (A, W), time compression (C) and weapon keys; the
# cameras are the game's views (F1 cockpit, F3 padlock, F4 radar target, F6 wingman, F9 fly-by, F10 chase, F11
# weapon). Staged, for the clip only: the F-35I's internal EOTS (laser + FLIR without a pod store) is not built yet,
# so the 223 part sets the pod flag for the laser-guided strike (see _strike).
#   DEMO_PART=315  Cold Steel: the two-ship with the instructor's F-16 over Makhtesh Ramon (the clip's title).
#   DEMO_PART=223  Tumble Down: the fly-by over the Dead Sea, the laser-guided MK-84L at a moving T-72, the AMRAAM kill.
#   DEMO_PART=214  Damascus Blackout: home to Ramat David on the autopilot and the night landing.
# DEMO_SEED fixes the dice (default 35). Prints "SEG <name> <first frame> <last frame>" (process frames from the start: the movie's frames),
# "VOICE <first> <last>" for every radio call and "CAM <name> <closest jet m>" for the outside views;
# tools/demo/adir_demo.py renders the parts with Godot's movie writer and cuts the clip from these lines.
extends "res://../tests/godot/base.gd"

## Internal only: AMRAAM on D / F, MK-84L (the GBU-31 stand-in) on C / G (the Arming screen's pylons 0..8).
const ARM := [[0, 0], [0, 0], [54, 1], [8, 1], [0, 0], [8, 1], [54, 1], [0, 0], [0, 0]]
## The AMRAAM launch rule: radar lock, Rmin <= range <= 8 km and the steering point centred (within this share of the
## launch circle's radius).
const MAX_LAUNCH := 8000.0
const CENTRED := 0.25
## Makhtesh Ramon (30.60 N 34.80 E, engine metres).
var _bogies_done := false
## When the jet leaves the route for the MiG-29s (mission time, s).
var TURN_NORTH := float(OS.get_environment("DEMO_TURN")) if OS.get_environment("DEMO_TURN") != "" else 180.0
const CRATER := Vector2(315482.0, 379382.0)
## Ramat David's runway (iaf.ibx [David]).
const DAVID := Vector2(356483.0, 602383.0)

var tv: Node
var w: Node
## Where the scripted pilot points the jet (a Callable giving a world point), null = hands off.
var aim = null
var aim_alt := 0.0
var _events := {}
var _voice_from := -1
var _cam_seg := ""
var _cam_min := INF


## As base.gd's, but quits right after the result (no wait for the audio to fade).
func _initialize() -> void:
	await process_frame
	await run()
	print("RESULT %s" % ("FAIL" if failures > 0 else "PASS"))
	quit(1 if failures > 0 else 0)


func run() -> void:
	var s := Settings()
	var detailed := {
		"models": "detailed",
		"sky": "atmospheric",
		"water": true,
		"particle_effects": true,
		"airbases": "detailed",
		"terrain_closeup": true,
		"night_lights": "detailed",
		"rolling_wheels": true,
		"antialiasing": "taa",
		"imagery_israel": "mapi2015",
		"imagery_outside": "sentinel2",
		"external_stores": true,
		"show_info": false,
		"hud_style": "real"
	}
	for k in detailed:
		s.set(k, detailed[k])
	seed(int(OS.get_environment("DEMO_SEED")) if OS.get_environment("DEMO_SEED") != "" else 35)
	s.jet_id = 4
	s.f35i_slot = 4  # the Jet list's Lavi button flies the F-35I (Extras)
	s.arm_loadouts = {1: ARM}
	var part := OS.get_environment("DEMO_PART")
	tv = await start_mission(int(part))
	w = tv.weapons
	_log_radio()
	var helper := Helper.new()
	helper.demo = self
	helper.process_priority = -1000
	tv.add_child(helper)
	match part:
		"315":
			await _m315()
		"223":
			await _m223()
		"214":
			await _m214()
	check(true, "demo part %s done" % part)


# --- 315 Cold Steel ---------------------------------------------------------------------------------


func _m315() -> void:
	await _secs(1.0)
	var wm: Node3D = tv.wingman()
	print("315 wingman %s" % [wm.name if wm != null else "none"])
	# The take-off is not in the clip: the mission's start spot is off the runway (the instructor says to taxi to it),
	# and the jet rolls straight from there.
	tv.brakes = false
	tv.throttle = 1.0
	await _until(func(): return float(tv.flight.state().speed_kt) > 150.0, 40.0)
	tv.scripted_stick = Vector2(0, 0.55)
	await _until(func(): return not tv.flight.state().on_ground, 5.0)
	await _secs(0.7)
	tv.scripted_stick = Vector2(0, 0.2)
	await _secs(0.8)
	tv._toggle_gear()  # G
	await _secs(2.5)
	tv._flaps_lever()  # F
	await _secs(2.0)
	tv.scripted_stick = null
	# The route on the autopilot (A: level, A: NAV), time compression (C C: x4) to Makhtesh Ramon.
	tv.autopilot.key()
	tv.autopilot.key()
	tv.throttle = 0.9
	tv._time_compress()
	tv._time_compress()
	tv.radio.wingman_command(6)  # close formation
	await _until(
		func(): return _dist2(CRATER + Vector2(9000, 5000)) < 9000.0 and tv.cockpit.current_waypoint >= 2, 900.0
	)
	tv._set_time_factor(1)
	await _secs(2.0)
	# 3. The two-ship over the crater: F6, the wingman view.
	tv._view_command(0x18)
	var f0 := _begin("crater")
	_title("F-35I ADIR", "IAF Reborn")
	await _secs(7.0)
	_seg("crater", f0)


# --- 223 Tumble Down --------------------------------------------------------------------------------


func _m223() -> void:
	tv.autopilot.key()  # A: level -> NAV (the route)
	tv.radio.wingman_command(6)  # close formation
	# 4. The fly-by over the Dead Sea's north end: F9.
	await _until(func(): return tv.runtime.now >= 52.0, 60.0)
	tv._view_command(0x13)
	var f0 := _begin("deadsea")
	await _secs(6.0)
	_seg("deadsea", f0)
	tv._view_command(1)
	# The wingman takes the chopper and the MiG-23 that come for Echo (radio: attack my target).
	await _until_event(21, 120.0)
	w.radar_event(0x2b)  # the radar to A-A
	await _secs(1.0)
	await _wingman_on("MI24")
	await _until_event(14, 60.0)
	await _secs(2.0)
	await _wingman_on("mig23-1-sec")
	await _strike()
	tv.radio.wingman_command(6)  # back to close formation
	await _amraam()
	await _until(func(): return _bogies_done, 120.0)


## 8-10: event 1's T-72s rolling west out of Amman; the laser-guided MK-84L from the bay.
func _strike() -> void:
	var tank := _ent("t72_north")
	# Out to the south-west and back, the tanks ahead when they roll.
	tv.autopilot.key()  # NAV -> off
	tv.throttle = 0.85
	aim_alt = 2500.0
	aim = func(): return Vector3(402000.0, 498000.0, 2500.0)
	await _until(func(): return tv.runtime.now > 112.0, 60.0)
	aim = func(): return tv.runtime._world_of(tank) + Vector3(0, 0, 1500.0)
	await _until(func(): return _events.has(1) and _hdist(tank) < 9000.0, 60.0)
	# The radar to A-G, the lock on the lead T-72.
	w.radar_event(0x2b)
	await _until(func(): return w.radar.contacts.any(func(c): return c.get("key", "") == tank.key), 10.0)
	w.radar_event(0x2a, tank.key)
	await process_frame
	print(
		(
			"STRIKE lock %s aa %s t %.1f d %.0f"
			% [w.radar.locked().get("key", "none"), w.radar.aa, tv.runtime.now, _dist(tank)]
		)
	)
	# 8. The tanks rolling west: F4, the radar-target view.
	tv._view_command(9)
	var f0 := _begin("tanks")
	await _secs(5.0)
	_seg("tanks", f0)
	# 9. The cockpit: '[' selects the MK-84L (master 5: the FLIR on the radar's target), L the laser, Space.
	tv._view_command(1)
	f0 = _begin("laser")
	# STAGED: the F-35I's internal EOTS (laser + FLIR with no pod store) is not built yet; the flag stands in for it.
	w.flir_pod = true
	w.select_ag()
	w.ripple_qty = 1
	await _secs(1.0)
	w.mfd_event(0x6a)  # L: the laser
	print(
		(
			"STRIKE sel %s master %d laser %s eo %d on unit %s"
			% [w.stores.current_name(), w.master, w.eo.laser, w.eo.mode, w.eo_on_unit]
		)
	)
	# Down to 350 m over the tank's ground and in level; Space 1.4 km out. The bomb flies to the designated tank's
	# position at the release (no lead, docs/weapons.md §9.8).
	aim = func(): return tv.runtime._world_of(tank) + Vector3(0, 0, 350.0)
	await _until(func(): return _hdist(tank) < 1400.0, 60.0)
	print("STRIKE run-in hdist %.0f agl %.0f off %s" % [_hdist(tank), _me().z - tv.runtime._world_of(tank).z, w.ag.off])
	var ahead: Vector3 = tv.runtime._world_of(tank) + (tv.runtime._world_of(tank) - _me()) * Vector3(1, 1, 0) * 6.0
	aim = func(): return ahead + Vector3(0, 0, 1200.0)
	w.fire_selected()  # Space held until the release
	await _until(func(): return not _mine(w.guided).is_empty(), 8.0)
	w.release_selected()
	var bomb = _mine(w.guided)[0] if not _mine(w.guided).is_empty() else null
	var rel := Engine.get_process_frames()
	var rel_t: float = tv.runtime.now
	print(
		(
			"STRIKE release t %.1f hdist %.0f bomb %s aim %s tank %s"
			% [rel_t, _hdist(tank), bomb != null, bomb.aim if bomb != null else null, tv.runtime._world_of(tank)]
		)
	)
	await _secs(1.5)
	_seg("laser", maxi(f0, rel - 150))
	# 10. The impact: F4 on the tank; the last seconds of the bomb's fall are kept.
	tv._view_command(9)
	var fv := _begin("bombhit")
	var bl := [Vector3.ZERO]
	await _until(
		func():
			if bomb != null and bomb in w.guided:
				bl[0] = bomb.position(w.now)
				return false
			return true,
		30.0
	)
	var hit := Engine.get_process_frames()
	var tof: float = tv.runtime.now - rel_t
	await _secs(2.0)
	print(
		(
			"STRIKE end tof %.1f miss %.0f m tank state %s"
			% [
				tof,
				Vector2(bl[0].x - tv.runtime._world_of(tank).x, bl[0].y - tv.runtime._world_of(tank).y).length(),
				tank.get("state")
			]
		)
	)
	_seg("bombhit", maxi(fv, hit - 75))
	aim = null
	tv.scripted_stick = null
	tv.autopilot.key()  # A: level
	tv.autopilot.key()  # A: NAV, the route again
	tv._view_command(1)
	w.radar_event(0x2b)  # the radar back to A-A


## 5-7: "Incoming bogies from the north!" (Echo, event 22), the lock on a MiG-29, the AMRAAM, the hit, the
## burning MiG.
func _amraam() -> void:
	var mig := _ent("mig29-2-first")
	var bogies := func():
		await _until_event(22, 200.0)
		var fb := Engine.get_process_frames()
		await _secs(3.5)
		print("SEG bogies %d %d" % [fb - 15, Engine.get_process_frames()])
		_bogies_done = true
	bogies.call()
	await _until(func(): return tv.runtime.now >= TURN_NORTH, 90.0)
	tv.autopilot.key()  # NAV -> off
	tv.throttle = 0.9
	aim_alt = 4000.0
	aim = func():
		var sg: Dictionary = w._sight(w.own(), w._units())
		return sg.pred if sg.pred != null else tv.runtime._world_of(mig)
	w.nav_key(0)
	w.select_aa()
	print("AMRAAM sel %s type %d" % [w.stores.current_name(), w.stores.current_type()])
	var f0 := Engine.get_process_frames()
	var fired := false
	var launch_f := 0
	var closest := INF
	var n := 0
	while n < 30 * 120 and is_instance_valid(w):
		await process_frame
		n += 1
		for m in _mine(w.missiles):
			closest = minf(closest, m.position(w.now).distance_to(tv.runtime._world_of(mig)))
		if int(mig.get("state", 1)) != 1:
			break
		if w.radar.locked().get("key", "") != mig.key:
			if w.radar.contacts.any(func(c): return c.get("key", "") == mig.key):
				w.radar_event(0x2a, mig.key)
			continue
		if fired:
			if _mine(w.missiles).is_empty() and Engine.get_process_frames() - launch_f > 60:
				break
			continue
		var r := _rule()
		if r.ok:
			print("LAUNCH t %.1f %s" % [tv.runtime.now, r.text])
			tv._view_command(0x16)  # F3 stores the padlock target
			tv._view_command(1)
			w.fire_selected()
			await process_frame
			w.release_selected()
			fired = true
			launch_f = Engine.get_process_frames()
			await _secs(1.5)
			_seg("launch", maxi(f0, launch_f - 120))
			# 6. F11: the AMRAAM; its last seconds and the hit are kept.
			tv._view_command(0x1b)
			f0 = _begin("amraam")
	if not is_instance_valid(w):
		check(false, "the Adir survives the engagement")
		return
	var hit := Engine.get_process_frames()
	await _secs(1.0)
	var ok: bool = fired and int(mig.get("state", 1)) != 1 and closest < 100.0
	print(
		(
			"OUTCOME %s mig state %s t %.1f missile closest %.0f m"
			% ["hit" if ok else "no hit", mig.get("state"), tv.runtime.now, closest]
		)
	)
	check(ok, "the AMRAAM kills the MiG-29")
	_seg("amraam", maxi(f0, hit - 75))
	# 7. F3: the burning MiG falls.
	tv._view_command(0x16)
	f0 = _begin("falls")
	await _secs(5.0)
	_seg("falls", f0)
	tv._view_command(1)
	aim = null
	tv.scripted_stick = null


## The launch rule: radar lock, inside Rmin..8 km and the steering point centred in the launch circle.
func _rule() -> Dictionary:
	var o: Dictionary = w.own()
	var sg: Dictionary = w._sight(o, w._units())
	if sg.target.is_empty() or sg.dlz.is_empty() or sg.pred == null:
		return {"ok": false, "text": "no sight"}
	var off = w.IrSeeker.screen_offset(o, sg.pred)
	var rad: float = float(sg.r) * 12.0
	var d_px: float = (off as Vector2).length() if off != null else INF
	var ok: bool = sg.locked and sg.dist >= float(sg.dlz[1]) and sg.dist <= MAX_LAUNCH and d_px <= CENTRED * rad
	return {
		"ok": ok,
		"text":
		(
			"range %.0f Rmin %.0f Rmax %.0f dot %.1f px circle %.1f px q %.2f"
			% [sg.dist, sg.dlz[1], sg.dlz[0], d_px, rad, sg.q]
		)
	}


func _wingman_on(prefix: String) -> void:
	var e := _ent(prefix)
	if e.is_empty() or int(e.get("state", 1)) != 1:
		return
	await _until(func(): return w.radar.contacts.any(func(c): return c.get("key", "") == e.key), 30.0)
	w.radar_event(0x2a, e.key)
	await process_frame
	tv.radio.wingman_command(3)
	print("WINGMAN on %s lock %s" % [prefix, w.radar.locked().get("key", "none")])


# --- 214 Damascus Blackout --------------------------------------------------------------------------


func _m214() -> void:
	# A: level -> NAV; W W W: the Home waypoint (its landing action: the autopilot's circuit and landing); C C: x4.
	tv.autopilot.key()
	for i in 3:
		tv.autopilot.set_waypoint(tv.cockpit.current_waypoint + 1)
	tv._time_compress()
	tv._time_compress()
	# x1 again on the final approach (heading west, below 350 m over the ground).
	await _until(
		func():
			return (
				absf(wrapf(float(tv.flight.state().heading) - 270.0, -180, 180)) < 10.0
				and _dist2(DAVID) < 8000.0
				and _me().z - _ground_y() < 350.0
			),
		1200.0
	)
	tv._set_time_factor(1)
	if not tv.gear_down:
		tv._toggle_gear()  # G: the gear down on final (our autopilot's landing leaves it up)
	print("214 final t %.1f kt %d %s" % [tv.runtime.now, tv.flight.state().speed_kt, _gear_text()])
	# 11. The approach and the touchdown: F9 gliding into the chase; the last 10 s before the touchdown are kept.
	tv._view_command(0x13)
	var f0 := _begin("landing")
	await _until(func(): return tv.flight.state().on_ground, 90.0)
	var td := Engine.get_process_frames()
	print("214 %s" % _gear_text())
	check(tv.gear_down and tv.gear_legs == [2, 2, 2], "214 touchdown on the gear (%s)" % _gear_text())
	var me := _me()
	print(
		(
			"214 touchdown t %.1f kt %d ab %s throttle %.2f gear_down %s at %d %d (runway %d %d)"
			% [
				tv.runtime.now,
				tv.flight.state().speed_kt,
				tv.flight.state().get("afterburner"),
				tv.throttle,
				tv.gear_down,
				me.x,
				me.y,
				DAVID.x,
				DAVID.y
			]
		)
	)
	await _secs(2.0)
	_title("F-35I ADIR", "IAF Reborn")
	await _secs(4.5)
	_seg("landing", maxi(f0, td - 300))


func _gear_text() -> String:
	var st: Dictionary = tv.flight.state()
	return (
		"lever %s legs %s fm gear %s gear_down %s on_ground %s"
		% [tv.gear_down, tv.gear_legs, st.get("gear"), st.get("gear_down"), st.get("on_ground")]
	)


# --- per frame ---------------------------------------------------------------------------------------


## Pure pursuit of `aim` (a world point): roll the point into the lift plane and pull toward it; near the nose,
## small stick in both axes. Far away the point is held at `aim_alt`.
func _fly() -> void:
	if aim == null or tv == null or tv.flight == null or not is_instance_valid(w):
		return
	var p: Vector3 = aim.call()
	var o: Dictionary = w.own()
	if Vector2(p.x - o.pos.x, p.y - o.pos.y).length() > 20000.0:
		p.z = aim_alt
	var v: Vector3 = (p - o.pos).normalized()
	var x: float = v.dot(o.right)
	var y: float = v.dot(o.up)
	var ang := acos(clampf(v.dot(o.fwd), -1.0, 1.0))
	var roll := deg_to_rad(float(tv.flight.state().roll))
	var stick: Vector2
	if ang > deg_to_rad(4.0):
		stick = Vector2(
			clampf(atan2(x, y) * 1.5, -1.0, 1.0), clampf(ang * 4.0, 0.0, 0.7) if absf(atan2(x, y)) < 1.2 else 0.1
		)
	else:
		stick = Vector2(
			clampf(x * 15.0, -0.6, 0.6), clampf(y * 15.0 + 0.5 * (1.0 / maxf(cos(roll), 0.3) - 1.0), -0.6, 0.8)
		)
	tv.scripted_stick = stick


## The radio calls (any speech player playing) as frame intervals; the closest jet to an outside camera.
func _watch() -> void:
	if tv == null or not is_instance_valid(tv) or tv.flight == null:
		return
	if Engine.get_process_frames() % 300 == 0:
		var st: Dictionary = tv.flight.state()
		var me := _me()
		var wm: Node3D = tv.wingman()
		print(
			(
				"ST t %.1f x%d me %d %d %d kt %d hdg %d gnd %s gear %s ab %s wp %d wing %.0f m"
				% [
					tv.runtime.now,
					tv.time_factor,
					me.x,
					me.y,
					me.z,
					st.speed_kt,
					st.heading,
					st.on_ground,
					tv.gear_down,
					st.get("afterburner"),
					tv.cockpit.current_waypoint,
					wm.global_position.distance_to(tv.rig.global_position) if wm != null else -1.0
				]
			)
		)
	var busy := false
	for p in tv.sounds.get_children() + [tv._voice]:
		if p is AudioStreamPlayer and p.bus == "IafSpeech" and p.playing:
			busy = true
			break
	var f := Engine.get_process_frames()
	if busy and _voice_from < 0:
		_voice_from = f
	elif not busy and _voice_from >= 0:
		print("VOICE %d %d" % [_voice_from, f])
		_voice_from = -1
	if _cam_seg == "" or tv.views.cockpit_like():
		return
	var cam := root.get_viewport().get_camera_3d()
	if cam == null:
		return
	var jets: Array = [tv.rig]
	for e in tv.runtime.entities.values():
		if e.get("pilot") != null and e.get("node") is Node3D and is_instance_valid(e.node):
			jets.append(e.node)
	for j in jets:
		_cam_min = minf(_cam_min, cam.global_position.distance_to(j.global_position))


class Helper:
	extends Node
	var demo

	func _process(_delta: float) -> void:
		demo._fly()
		demo._watch()


# --- helpers ----------------------------------------------------------------------------------------


func _log_radio() -> void:
	tv.runtime.subtitle.connect(func(t): print("SUB %.1f f%d %s" % [tv.runtime.now, Engine.get_process_frames(), t]))
	tv.runtime.event_fired.connect(
		func(id, n):
			_events[id] = true
			print("EVT %.1f %d %s" % [tv.runtime.now, id, n])
	)


## A shot's first frame (the closest-jet watch starts).
func _begin(name: String) -> int:
	_cam_seg = name
	_cam_min = INF
	return Engine.get_process_frames()


func _seg(name: String, f0: int) -> void:
	print("SEG %s %d %d" % [name, f0, Engine.get_process_frames()])
	if _cam_min < INF:
		print("CAM %s %.1f" % [name, _cam_min])
	_cam_seg = ""


## The clip's title: in for 1 s, held, out by 5 s.
func _title(text: String, sub: String) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	tv.add_child(layer)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	layer.add_child(box)
	var h := float(root.get_viewport().get_visible_rect().size.y)
	for t in [[text, h / 11.0], [sub, h / 30.0]]:
		var l := Label.new()
		l.text = t[0]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", int(t[1]))
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
		l.add_theme_constant_override("shadow_offset_x", int(h / 400.0))
		l.add_theme_constant_override("shadow_offset_y", int(h / 400.0))
		box.add_child(l)
	box.modulate.a = 0.0
	var tw := box.create_tween()
	tw.tween_property(box, "modulate:a", 1.0, 1.0)
	tw.tween_interval(3.0)
	tw.tween_property(box, "modulate:a", 0.0, 1.0)
	tw.tween_callback(layer.queue_free)


func _until_event(id: int, max_s: float) -> void:
	await _until(func(): return _events.has(id), max_s)


func _ent(prefix: String) -> Dictionary:
	for e in tv.runtime.entities.values():
		if String(e.name).begins_with(prefix):
			return e
	return {}


func _me() -> Vector3:
	return tv.scene_to_world(tv.rig.global_position)


func _dist(e: Dictionary) -> float:
	return (tv.runtime._world_of(e) - _me()).length()


func _hdist(e: Dictionary) -> float:
	var p: Vector3 = tv.runtime._world_of(e)
	return _dist2(Vector2(p.x, p.y))


func _dist2(p: Vector2) -> float:
	var me := _me()
	return Vector2(me.x - p.x, me.y - p.y).length()


func _ground_y() -> float:
	var g = tv.terrain.height_at(tv.rig.global_position)
	return float(g) if g != null else 0.0


func _mine(list: Array) -> Array:
	return list.filter(func(m): return is_same(m.get_meta("owner", null), w._me()))


func _secs(s: float) -> void:
	await frames(int(round(s * 30.0)))


func _until(cond: Callable, max_s: float) -> void:
	var n := 0
	while not cond.call() and n < int(max_s * 30.0 * Engine.time_scale):
		await process_frame
		n += 1
